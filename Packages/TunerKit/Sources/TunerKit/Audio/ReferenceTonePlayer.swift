import Foundation
import AVFoundation
import os

/// 参考音播放器：任意音高持续发声，直到调用 `stop()`。
public final class ReferenceTonePlayer {
    public var configuresAudioSession = true
    public private(set) var isPlaying = false
    /// 拨弦类参考音自然衰减播完时调用（主线程）；被 `stop()` 打断或重新播放则不调用。
    public var onEnded: (() -> Void)?
    private var generation = 0

    private let engine = AVAudioEngine()
    private let synth = OSAllocatedUnfairLock(initialState: ToneSynth())
    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44100

    public init() {}

    /// 当前乐器（`.instrument` 音色用）。
    private var voice: InstrumentTone.Voice = .piano

    /// 开始（或切换到）一个新的频率。`.instrument` 音色会先按 `voice` 把这个音渲染好。
    public func play(frequency: Double, timbre: ToneTimbre = .sine, amplitude: Float = 0.3,
                     voice: InstrumentTone.Voice = .piano) throws {
        try prepareIfNeeded()
        self.voice = voice
        generation += 1
        let mine = generation
        // 优先用真实采样；采样库里没有这件乐器才退回合成
        let playback: SamplePlayback?
        if timbre == .instrument, let sample = SampleBank.shared.sample(for: voice, nearestTo: frequency) {
            playback = SamplePlayback(sample: sample, frequency: frequency, outputRate: sampleRate)
        } else {
            playback = nil
        }
        let rendered = (timbre == .instrument && playback == nil)
            ? Self.renderTone(voice, frequency: frequency, sampleRate: sampleRate) : nil
        synth.withLock {
            $0.frequency = frequency
            $0.timbre = timbre
            $0.amplitude = amplitude
            if let playback { $0.load(playback: playback) }
            else if let rendered { $0.load(sample: rendered.sample, loopStart: rendered.loopStart) }
            $0.start()
        }
        if !engine.isRunning { try engine.start() }
        isPlaying = true
        if let length = playback?.estimatedDuration {
            DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in
                guard let self, self.generation == mine, self.isPlaying else { return }
                self.finish()
            }
        }
    }

    private func finish() {
        isPlaying = false
        synth.withLock { $0.stop() }
        onEnded?()
        let engine = engine
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard self?.isPlaying == false else { return }
            engine.pause()
        }
    }

    public func play(pitch: Pitch, a4: Double = TunerDefaults.a4,
                     timbre: ToneTimbre = .sine, amplitude: Float = 0.3, voice: InstrumentTone.Voice = .piano) throws {
        try play(frequency: pitch.frequency(a4: a4), timbre: timbre, amplitude: amplitude, voice: voice)
    }

    /// 实时调整正在发声的频率（例如 A4 改变时）。乐器音色需要重新渲染。
    public func update(frequency: Double) {
        let (isInstrument, sampled) = synth.withLock { ($0.timbre == .instrument, $0.hasSampler) }
        if sampled {                       // 真实采样：只改播放速度，声音不中断
            synth.withLock { $0.retune(frequency: frequency) }
            return
        }
        let rendered = isInstrument ? Self.renderTone(voice, frequency: frequency, sampleRate: sampleRate) : nil
        synth.withLock {
            $0.frequency = frequency
            if let rendered { $0.load(sample: rendered.sample, loopStart: rendered.loopStart) }
        }
    }

    /// 拨弦类渲染 2.6 秒（每 2.4 秒重拨）；弓弦类渲染 3 秒，起音后循环。
    static func renderTone(_ voice: InstrumentTone.Voice, frequency: Double, sampleRate: Double) -> (sample: [Float], loopStart: Int?) {
        let duration = voice.isSustained ? 3.0 : 2.6
        let sample = InstrumentTone.render(voice, frequency: frequency, sampleRate: sampleRate, duration: duration, amplitude: 1)
        return (sample, voice.isSustained ? InstrumentTone.loopStart(sampleRate: sampleRate) : nil)
    }

    public func stop() {
        guard isPlaying else { return }
        generation += 1
        synth.withLock { $0.stop() }
        isPlaying = false
        // 留出淡出时间再关引擎
        let engine = engine
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard self?.isPlaying == false else { return }
            engine.pause()
        }
    }

    private func prepareIfNeeded() throws {
        guard sourceNode == nil else { return }
        #if os(iOS)
        if configuresAudioSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        }
        #endif
        let output = engine.outputNode
        let hwFormat = output.inputFormat(forBus: 0)
        sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let rate = sampleRate
        let lock = synth
        let node = AVAudioSourceNode(format: format) { _, _, frames, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = abl.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frames)
            let ok = lock.withLockIfAvailable { s -> Bool in
                s.render(into: data, count: n, sampleRate: rate)
                return true
            }
            if ok == nil { for i in 0..<n { data[i] = 0 } }
            // 复制到其余声道
            for b in abl.dropFirst() {
                if let d = b.mData?.assumingMemoryBound(to: Float.self) { d.update(from: data, count: n) }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }
}

import Foundation
import AVFoundation
import TunerKit

/// 试听：把按法按弦序拨一遍（声音用 TunerKit 内置的真实乐器采样，没有采样才回退到合成）。
///
/// 每次试听先离线渲染成一段缓冲再播放，所以不需要音频渲染线程里的任何状态。
@MainActor
public final class ChordPlayer {
    /// 是否由本类设置音频会话（iOS）。App 自己统一管理会话时设 false。
    public var configuresAudioSession = true
    public var a4: Double = TunerDefaults.a4
    /// 琶音（`play(pitches:)`）里相邻两个音的间隔（秒）。
    public var strumGap: Double = 0.06
    /// 扫弦（`play(_ voicing:)`）里相邻两根弦的间隔（秒）：真实扫弦约 25–40 毫秒，固定用这个值，不受 `strumGap` 影响。
    public var voicingStrumGap: Double = ChordStrummer.defaultGap
    /// 贝斯只弹根音：`play(pitches:)` 在 `voice == .bass` 时只取第一个音。
    public var bassPlaysRootOnly = true
    /// 用哪件乐器的声音（吉他、尤克里里、贝斯）。
    public var voice: InstrumentTone.Voice = .guitar
    public private(set) var isPlaying = false
    /// 一次试听自然播完时调用（被打断或 `stop()` 不调用）。
    public var onFinish: (() -> Void)?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attached = false
    private var sampleRate: Double = 44100
    private var generation = 0
    private var current: ChordPlayback?
    private var loopSeconds: Double?

    public init() {}

    /// 播放一个吉他/尤克里里按法（扫弦）；已有的声音会被打断。
    public func play(_ voicing: ChordVoicing) {
        play(PlaybackBuilder.strum(voicing: voicing, voice: voice, a4: a4, gap: voicingStrumGap))
    }

    /// 播放一段事件表：扫弦播一遍，分解和弦循环到 `stop()`。已有的声音会被打断。
    ///
    /// 事件的时间就是它在缓冲里的位置；缓冲在音频线程里按采样时钟播放，`cyclePosition()` 读的也是这个时钟，
    /// 所以指法图的动画和声音对得上（不是靠定时器估计）。
    public func play(_ playback: ChordPlayback) {
        guard !playback.events.isEmpty else { return }
        do {
            try prepare()
            let samples = ChordStrummer.render(playback, sampleRate: sampleRate)
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            node.stop()
            generation += 1
            let mine = generation
            if !engine.isRunning { try engine.start() }
            isPlaying = true
            current = playback
            loopSeconds = playback.isLooping ? Double(samples.count) / sampleRate : nil
            if playback.isLooping {
                node.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            } else {
                node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == mine else { return }
                        self.isPlaying = false
                        self.current = nil
                        self.onFinish?()
                    }
                }
            }
            node.play()
        } catch {
            isPlaying = false
            current = nil
        }
    }

    /// 当前这段播放里“耳朵听到的位置”（秒）：循环播放时已按周期取余；没在播放时是 nil。
    /// 读的是音频节点的渲染时钟，再减去输出延迟。
    public func cyclePosition() -> Double? {
        guard isPlaying, node.isPlaying, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime), playerTime.sampleRate > 0 else { return nil }
        var t = Double(playerTime.sampleTime) / playerTime.sampleRate - engine.outputNode.presentationLatency
        guard t >= 0 else { return nil }
        if let loop = loopSeconds, loop > 0 { t = t.truncatingRemainder(dividingBy: loop) }
        return t
    }

    /// 此刻每个元素距上一次被拨到过了多久（见 `PluckClock`）。
    public func pluckAges() -> [Int: Double] {
        guard let playback = current, let t = cyclePosition() else { return [:] }
        return PluckClock.ages(events: playback.events, cycle: loopSeconds ?? playback.cycle, time: t)
    }

    /// 依次拨一串音（测试用；贝斯时只弹根音）。
    public func play(pitches: [Pitch]) {
        play(frequencies: Self.frequencies(forPitches: pitches, voice: voice, a4: a4, bassRootOnly: bassPlaysRootOnly), gap: strumGap)
    }

    /// 琶音要播的频率：贝斯只取第一个音（根音），其他乐器全部按顺序。
    static func frequencies(forPitches pitches: [Pitch], voice: InstrumentTone.Voice, a4: Double, bassRootOnly: Bool) -> [Double] {
        let notes = (voice == .bass && bassRootOnly) ? Array(pitches.prefix(1)) : pitches
        return notes.map { $0.frequency(a4: a4) }
    }

    public func play(frequencies: [Double]) {
        play(frequencies: frequencies, gap: strumGap)
    }

    private func play(frequencies: [Double], gap: Double) {
        guard !frequencies.isEmpty else { return }
        do {
            try prepare()
            let samples = ChordStrummer.render(frequencies: frequencies, sampleRate: sampleRate, gap: gap, voice: voice)
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            node.stop()
            generation += 1
            let mine = generation
            current = nil
            if !engine.isRunning { try engine.start() }
            isPlaying = true
            node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == mine else { return }
                    self.isPlaying = false
                    self.onFinish?()
                }
            }
            node.play()
        } catch {
            isPlaying = false
        }
    }

    public func stop() {
        generation += 1
        node.stop()
        isPlaying = false
        current = nil
    }

    private func prepare() throws {
        guard !attached else { return }
        #if os(iOS)
        if configuresAudioSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        }
        #endif
        let hw = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = hw.sampleRate > 0 ? hw.sampleRate : 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        attached = true
    }
}

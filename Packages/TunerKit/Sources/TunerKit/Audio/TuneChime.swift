import Foundation
import AVFoundation

/// 调准提示音“叮—咚”：两声清脆的钟琴音，纯合成（没有外部素材）。
public enum TuneChime {
    /// 两个音（Hz）：默认 E6 → C6，“叮”高“咚”低。
    public static let firstFrequency = 1318.51
    public static let secondFrequency = 1046.50
    /// 第二个音比第一个晚多久出现（秒）。
    public static let noteGap = 0.17
    /// 整段提示音的长度（秒）。
    public static let duration = 0.85

    /// 渲染成单声道采样，峰值约 `peak`（默认 0.4，音量适中）。
    public static func render(sampleRate: Double, peak: Float = 0.4) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        addBell(&out, sampleRate: sampleRate, start: 0, frequency: firstFrequency, gain: 0.85, decay: 6.5)
        addBell(&out, sampleRate: sampleRate, start: noteGap, frequency: secondFrequency, gain: 1.0, decay: 5.0)
        let top = out.map { abs($0) }.max() ?? 1
        let scale = top > 0 ? peak / top : 0
        // 末尾 60 ms 淡出，保证不留咔哒
        let fade = Int(0.06 * sampleRate)
        for i in 0..<n {
            var v = out[i] * scale
            if i >= n - fade { v *= Float(n - 1 - i) / Float(fade) }
            out[i] = v
        }
        return out
    }

    /// 钟琴音：基频是主角，加一个很弱、衰减很快的非谐和泛音（2.76 倍）带出“敲击”的亮度，不刺耳。
    private static func addBell(_ out: inout [Float], sampleRate: Double, start: Double,
                                frequency: Double, gain: Double, decay: Double) {
        let first = Int(start * sampleRate)
        let attack = 0.004
        for i in first..<out.count {
            let t = Double(i - first) / sampleRate
            let env = min(1, t / attack) * exp(-decay * t)
            let body = sin(2 * .pi * frequency * t)
            let sparkle = 0.12 * sin(2 * .pi * frequency * 2.76 * t) * exp(-18 * t)
            let low = 0.18 * sin(2 * .pi * frequency * 0.5 * t) * exp(-9 * t)     // 一点点低八度的“咚”感
            out[i] += Float(gain * env * (body + sparkle + low))
        }
    }
}

/// 播放调准提示音。第一次播放时才建立音频引擎。
public final class TuneChimePlayer {
    public var configuresAudioSession = true
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attached = false
    private var buffer: AVAudioPCMBuffer?

    public init() {}

    /// 播放一次；返回是否成功开始播放。
    @discardableResult
    public func play() -> Bool {
        do {
            try prepare()
            guard let buffer else { return false }
            if !engine.isRunning { try engine.start() }
            node.stop()
            node.scheduleBuffer(buffer, at: nil, options: .interrupts)
            node.play()
            return true
        } catch {
            return false
        }
    }

    public func stop() {
        node.stop()
        if engine.isRunning { engine.pause() }
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
        let rate = hw.sampleRate > 0 ? hw.sampleRate : 44_100
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let samples = TuneChime.render(sampleRate: rate)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        buffer = b
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        attached = true
    }
}

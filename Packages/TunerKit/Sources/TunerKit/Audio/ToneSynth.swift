import Foundation

/// 参考音的音色。
public enum ToneTimbre: String, Codable, Sendable, CaseIterable {
    /// 纯正弦，最容易听出拍音。
    case sine
    /// 简单的拨弦合成：几个泛音按各自速度衰减，每隔一会儿重新拨一次，形成持续的“嗡”。
    case pluck
    /// 当前所选乐器的声音（吉他拨弦、小提琴拉弦……），见 `InstrumentTone`。
    case instrument
}

/// 参考音的合成核心：纯计算，没有音频硬件依赖，便于测试。
/// `render` 在音频渲染线程调用，参数由 `ReferenceTonePlayer` 加锁更新。
public struct ToneSynth: Sendable {
    public var frequency: Double = 440
    public var timbre: ToneTimbre = .sine
    public var amplitude: Float = 0.3
    /// 拨弦音色的重新拨弦间隔（秒）。
    public var pluckInterval: Double = 2.4

    /// `.instrument` 用的预渲染采样（在主线程渲染好再交给音频线程）。
    public private(set) var sample: [Float] = []
    /// 持续音（弓弦）从这里开始循环；nil 表示拨弦类，按 `pluckInterval` 重新触发。
    public private(set) var loopStart: Int?

    /// 真实采样播放（`.instrument` 且采样库里有这件乐器时用）；为 nil 时用合成。
    private var sampler: SamplePlayback?
    /// 采样路径的整体增益：默认 `amplitude`（0.3）对应 0.9。
    private static let sampleGainPerAmplitude: Float = 3

    private var phase = 0.0
    private var gain: Float = 0       // 用于淡入淡出，避免爆音
    private var target: Float = 0
    private var sincePluck = 0.0
    private var position = 0

    public init() {}

    public var isSounding: Bool { target > 0 || gain > 0.0001 }
    public var hasSampler: Bool { sampler != nil }
    /// 拨弦采样已经自然播完。
    public var isSampleFinished: Bool { sampler?.isFinished ?? false }

    public mutating func start() {
        if target == 0 { sincePluck = 0; position = 0 }
        target = 1
    }
    public mutating func stop() { target = 0 }

    /// 换成某件乐器的声音（主线程调用；渲染好的采样替换进来，从头播放）。
    public mutating func load(sample: [Float], loopStart: Int?) {
        self.sample = sample
        self.loopStart = loopStart
        position = 0
    }

    /// 换成真实采样（主线程调用）。随后调 `start()`。
    public mutating func load(playback: SamplePlayback) {
        sampler = playback
        sample = []
        loopStart = nil
        position = 0
    }

    /// 改变正在发声的采样的频率，不重新开始。
    public mutating func retune(frequency: Double) {
        self.frequency = frequency
        sampler?.retune(frequency: frequency)
    }

    private static let partials: [(ratio: Double, level: Double, decay: Double)] = [
        (1, 1.0, 1.1), (2, 0.55, 1.8), (3, 0.30, 2.6), (4, 0.18, 3.6), (5, 0.10, 5.0), (6, 0.06, 6.5),
    ]

    public mutating func render(into out: UnsafeMutablePointer<Float>, count: Int, sampleRate: Double) {
        if timbre == .instrument, sampler != nil {
            sampler!.render(into: out, count: count)
            let fadeIn = Float(1 / (0.01 * sampleRate)), fadeOut = Float(1 / (0.08 * sampleRate))
            let scale = amplitude * Self.sampleGainPerAmplitude
            for i in 0..<count {
                if gain < target { gain = min(target, gain + fadeIn) }
                else if gain > target { gain = max(target, gain - fadeOut) }
                out[i] *= gain * scale
            }
            return
        }
        let dt = 1 / sampleRate
        let step = frequency / sampleRate
        let fade = Float(1 / (0.01 * sampleRate))     // 10 ms 淡入淡出
        let pluckLength = Int(pluckInterval * sampleRate)
        let crossfade = Int(0.12 * sampleRate)
        for i in 0..<count {
            if gain < target { gain = min(target, gain + fade) }
            else if gain > target { gain = max(target, gain - fade) }

            var v: Double
            switch timbre {
            case .sine:
                v = sin(2 * .pi * phase)
            case .pluck:
                if sincePluck >= pluckInterval { sincePluck -= pluckInterval }
                let t = sincePluck
                v = 0
                for p in Self.partials where frequency * p.ratio < sampleRate / 2 {
                    v += p.level * exp(-p.decay * t) * sin(2 * .pi * phase * p.ratio)
                }
                // 起音很短的弱化，避免咔哒声；整体压低以与正弦同响度
                v *= min(1, t / 0.004 + 0.0) * 0.6
                sincePluck += dt
            case .instrument:
                v = 0
                let n = sample.count
                if n > 0 {
                    if let loop = loopStart, loop + crossfade < n {
                        // 弓弦：起音之后在 [loop, n) 里循环，接缝处交叉淡化
                        var s = Double(sample[position])
                        let tailStart = n - crossfade
                        if position >= tailStart {
                            let w = Double(position - tailStart) / Double(crossfade)
                            s = s * (1 - w) + Double(sample[loop + position - tailStart]) * w
                        }
                        v = s
                        position += 1
                        if position >= n { position = loop + crossfade }
                    } else {
                        // 拨弦：每隔 pluckInterval 重新拨一次；上一次的尾音在 5 ms 内淡出
                        let length = min(n, pluckLength)
                        if position >= length { position = 0 }
                        v = Double(sample[position])
                        let remaining = length - position
                        let tailFade = Int(0.005 * sampleRate)
                        if remaining < tailFade { v *= Double(remaining) / Double(tailFade) }
                        position += 1
                    }
                }
            }
            out[i] = Float(v) * amplitude * gain
            phase += step
            if phase >= 1 { phase -= 1 }
        }
        if timbre == .sine { sincePluck = 0 }
    }
}

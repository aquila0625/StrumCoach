import Foundation

/// 用一段采样发出任意音高的声音：按 目标频率 ÷ 采样基频 的比例做四点 Hermite 插值重采样。
/// 拉弦采样在循环区间里无缝循环（位置按小数累加，接缝处不会错位）；拨弦采样播完就结束。
/// 纯计算、没有音频硬件依赖，可以在渲染线程里用，也可以离线渲染测音准。
public struct SamplePlayback: Sendable {
    private let data: [Float]
    private let sourceRate: Double
    private let root: Double
    private let loopStart: Int
    private let loopEnd: Int            // 0 表示不循环
    private let outputRate: Double
    private var step: Double
    private var position = 0.0

    public private(set) var isFinished = false
    public var isLooping: Bool { loopEnd > 0 }
    /// 采样本身的时长（秒）。
    public let sampleDuration: Double

    public init(sample: SampleBuffer, frequency: Double, outputRate: Double) {
        data = sample.data
        sourceRate = sample.sampleRate
        root = sample.rootFrequency
        loopStart = sample.loop?.lowerBound ?? 0
        loopEnd = sample.loop?.upperBound ?? 0
        self.outputRate = outputRate
        step = frequency / sample.rootFrequency * sample.sampleRate / outputRate
        sampleDuration = sample.duration
    }

    /// 拨弦采样按当前音高播完还要多久（秒）；循环采样返回 nil。
    public var estimatedDuration: Double? {
        guard !isLooping else { return nil }
        return Double(data.count) / (step * outputRate / sourceRate) / outputRate
    }

    /// 在发声过程中改变目标频率（比如调整标准音 A4）；播放位置不动，所以不会有断点。
    public mutating func retune(frequency: Double) {
        step = frequency / root * sourceRate / outputRate
    }

    /// 写出 `count` 个采样（覆盖 `out`）；播完后补零。
    public mutating func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        let n = data.count
        guard n > 3, !isFinished else {
            for i in 0..<count { out[i] = 0 }
            return
        }
        let loopLength = loopEnd - loopStart
        data.withUnsafeBufferPointer { d in
            @inline(__always) func at(_ index: Int) -> Float {
                var i = index
                if loopEnd > 0, i >= loopEnd { i = loopStart + (i - loopStart) % loopLength }
                if i < 0 { return d[0] }
                if i >= n { return 0 }
                return d[i]
            }
            for k in 0..<count {
                if isFinished { out[k] = 0; continue }
                let i = Int(position)
                let t = Float(position - Double(i))
                let y0 = at(i - 1), y1 = at(i), y2 = at(i + 1), y3 = at(i + 2)
                let c1 = 0.5 * (y2 - y0)
                let c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
                let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
                out[k] = ((c3 * t + c2) * t + c1) * t + y1
                position += step
                if loopEnd > 0 {
                    if position >= Double(loopEnd) { position -= Double(loopLength) }
                } else if position >= Double(n - 2) {
                    isFinished = true
                }
            }
        }
    }

    /// 离线渲染 `duration` 秒。
    public static func render(_ sample: SampleBuffer, frequency: Double, sampleRate: Double, duration: Double) -> [Float] {
        let count = max(0, Int(duration * sampleRate))
        var out = [Float](repeating: 0, count: count)
        guard count > 0 else { return out }
        var playback = SamplePlayback(sample: sample, frequency: frequency, outputRate: sampleRate)
        out.withUnsafeMutableBufferPointer { playback.render(into: $0.baseAddress!, count: count) }
        return out
    }
}

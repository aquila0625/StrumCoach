import Foundation
import Accelerate

/// 检测器的原始输出（未平滑）。
public struct RawPitch: Equatable, Sendable {
    public var frequency: Double
    public var clarity: Double
}

/// McLeod 音高检测（MPM）：归一化平方差函数 + 峰值挑选 + 抛物线插值。
///
/// 对富含泛音的信号（吉他、提琴）比朴素自相关更不容易出现八度误判。
/// 实例带有复用的缓冲区，**不是线程安全的**：每个线程/队列用自己的实例。
public final class PitchDetector {
    public struct Configuration: Sendable {
        /// 能识别的最低频率（5 弦贝斯最低音 B0 ≈ 30.9 Hz，再留出调低的余量）。
        public var minFrequency: Double = 27
        /// 能识别的最高频率。
        public var maxFrequency: Double = 2100
        /// 低于这个 RMS（满量程为 1）视为静音，不输出音高。
        public var silenceRMS: Float = 0.003
        /// MPM 的峰值阈值 k：选第一个不低于 k × 最高峰的峰。
        public var peakThreshold: Double = 0.9
        /// 最高峰低于这个值就不算有音高（噪声、杂音）。
        public var minClarity: Double = 0.8

        public init() {}
    }

    public var configuration: Configuration

    private var nsdf: [Float] = []
    private var prefix: [Double] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// 建议的分析窗口长度：至少覆盖最低频率的两个周期。
    public static func recommendedFrameLength(sampleRate: Double,
                                              minFrequency: Double = Configuration().minFrequency) -> Int {
        Int((2.1 * sampleRate / minFrequency).rounded(.up))
    }

    public func detect(_ samples: [Float], sampleRate: Double) -> RawPitch? {
        samples.withUnsafeBufferPointer { detect($0, sampleRate: sampleRate) }
    }

    public func detect(_ x: UnsafeBufferPointer<Float>, sampleRate: Double) -> RawPitch? {
        let n = x.count
        guard n >= 64, sampleRate > 0, let base = x.baseAddress else { return nil }
        let cfg = configuration

        // 静音门限
        var rms: Float = 0
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(n))
        guard rms >= cfg.silenceRMS else { return nil }

        let minLag = max(2, Int(sampleRate / cfg.maxFrequency))
        let maxLag = min(Int(sampleRate / cfg.minFrequency), n / 2)
        guard maxLag > minLag + 2 else { return nil }

        // x² 的前缀和，用来 O(1) 得到每个 lag 的能量项 m(τ)
        if prefix.count != n + 1 { prefix = [Double](repeating: 0, count: n + 1) }
        var acc = 0.0
        prefix[0] = 0
        for i in 0..<n {
            let v = Double(base[i])
            acc += v * v
            prefix[i + 1] = acc
        }

        // NSDF(τ) = 2·r(τ) / m(τ)，r 为自相关，m 为两段能量之和；τ 从 1 开始以便跳过 τ=0 附近的主瓣
        if nsdf.count != maxLag + 2 { nsdf = [Float](repeating: 0, count: maxLag + 2) }
        for tau in 1...(maxLag + 1) {
            let len = n - tau
            var r: Float = 0
            vDSP_dotpr(base, 1, base + tau, 1, &r, vDSP_Length(len))
            let m = prefix[len] + (prefix[n] - prefix[tau])
            nsdf[tau] = m > 1e-12 ? Float(2 * Double(r) / m) : 0
        }

        // 跳过起始的正值主瓣，找到第一次下穿 0 的位置
        var tau = 1
        while tau <= maxLag && nsdf[tau] > 0 { tau += 1 }
        guard tau <= maxLag else { return nil }

        // 每个“正值区间”取一个峰
        var peaks: [(lag: Int, value: Float)] = []
        var bestValue: Float = 0
        while tau <= maxLag {
            while tau <= maxLag && nsdf[tau] <= 0 { tau += 1 }
            guard tau <= maxLag else { break }
            var peakLag = tau
            var peakValue = nsdf[tau]
            while tau <= maxLag && nsdf[tau] > 0 {
                if nsdf[tau] > peakValue { peakValue = nsdf[tau]; peakLag = tau }
                tau += 1
            }
            if peakLag >= minLag && peakLag <= maxLag {
                peaks.append((peakLag, peakValue))
                bestValue = max(bestValue, peakValue)
            }
        }
        guard bestValue > 0 else { return nil }

        let limit = Float(cfg.peakThreshold) * bestValue
        guard let chosen = peaks.first(where: { $0.value >= limit }) else { return nil }

        // 抛物线插值求亚采样精度的周期
        let k = chosen.lag
        let a = nsdf[k - 1], b = nsdf[k], c = nsdf[k + 1]
        let denom = a - 2 * b + c
        var shift: Float = 0
        var value = b
        if abs(denom) > 1e-12 {
            shift = 0.5 * (a - c) / denom
            if abs(shift) > 1 { shift = 0 }
            value = b - 0.25 * (a - c) * shift
        }
        let clarity = Double(min(max(value, 0), 1))
        guard clarity >= cfg.minClarity else { return nil }

        let period = Double(k) + Double(shift)
        return RawPitch(frequency: sampleRate / period, clarity: clarity)
    }
}

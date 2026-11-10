import Foundation

/// 测试用的合成信号。
enum Signal {
    enum Shape { case sine, sawtooth, harmonics }

    static func make(_ shape: Shape, frequency: Double, sampleRate: Double = 44100,
                     count: Int = 4096, amplitude: Float = 0.5, phase: Double = 0) -> [Float] {
        (0..<count).map { i in
            let t = Double(i) / sampleRate
            let ph = frequency * t + phase
            switch shape {
            case .sine:
                return amplitude * Float(sin(2 * .pi * ph))
            case .sawtooth:
                let frac = ph - ph.rounded(.down)
                return amplitude * Float(2 * frac - 1)
            case .harmonics:
                // 基频很弱、二三次泛音更强的“吉他式”音色
                var v = 0.0
                for (h, a) in [(1, 0.35), (2, 1.0), (3, 0.8), (4, 0.5), (5, 0.3)] {
                    v += a * sin(2 * .pi * Double(h) * ph)
                }
                return amplitude * Float(v / 2.2)
            }
        }
    }

    /// 加高斯白噪声，`snrDB` 为信噪比（按功率）。固定种子，结果可复现。
    static func addNoise(_ x: [Float], snrDB: Double, seed: UInt64 = 42) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let power = x.reduce(0.0) { $0 + Double($1 * $1) } / Double(x.count)
        let sigma = (power / pow(10, snrDB / 10)).squareRoot()
        return x.map { v in
            let u1 = max(rng.nextUnit(), 1e-12), u2 = rng.nextUnit()
            let g = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
            return v + Float(sigma * g)
        }
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

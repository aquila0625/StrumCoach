import Foundation

/// 按乐器合成一个音（参考音、和弦试听共用）。纯计算，没有音频硬件依赖，可以离线渲染测音准。
///
/// - 吉他、尤克里里、贝斯：Karplus-Strong 拨弦模型 + 拨弦位置（梳状滤波）+ 琴体共鸣（几个二阶谐振器）。
/// - 小提琴、中提琴、大提琴：弓弦的谐波模型（锯齿波谱、略带不谐和）+ 琴体共振峰 + 轻微弓噪声和揉弦。
/// - 自动（半音阶）：钢琴式击弦，谐波略带不谐和，按频率衰减。
public enum InstrumentTone {
    public enum Voice: String, Codable, Sendable, CaseIterable {
        case piano, guitar, ukulele, bass, violin, viola, cello

        public init(family: InstrumentFamily) {
            switch family {
            case .chromatic: self = .piano
            case .guitar: self = .guitar
            case .ukulele: self = .ukulele
            case .bass: self = .bass
            case .violin: self = .violin
            case .viola: self = .viola
            case .cello: self = .cello
            }
        }

        /// 拨弦/击弦类会自然衰减，需要定时重新触发；弓弦类可以一直拉。
        public var isSustained: Bool { self == .violin || self == .viola || self == .cello }
    }

    /// 渲染一个音，峰值约 `amplitude`。弓弦类渲染的是一段可以循环的持续音（见 `loopStart`）。
    ///
    /// 默认用内置的真实乐器采样（`SampleBank`）按目标频率重采样；采样库里没有这件乐器、或 `useSamples` 为 false 时，
    /// 回退到下面的物理建模合成。
    public static func render(_ voice: Voice, frequency: Double, sampleRate: Double,
                              duration: Double, amplitude: Float = 0.5, seed: UInt64 = 1,
                              useSamples: Bool = true) -> [Float] {
        let n = max(0, Int(duration * sampleRate))
        guard n > 0, frequency > 10 else { return [Float](repeating: 0, count: n) }
        if useSamples, let sample = SampleBank.shared.sample(for: voice, nearestTo: frequency) {
            var out = SamplePlayback.render(sample, frequency: frequency, sampleRate: sampleRate, duration: duration)
            let fadeOut = min(n, Int(0.03 * sampleRate))     // 截断处（循环采样或被截短的拨弦）淡出，避免咔哒
            for i in 0..<fadeOut { out[n - 1 - i] *= Float(i) / Float(fadeOut) }
            normalize(&out, peak: amplitude)
            return out
        }
        var out: [Float]
        switch voice {
        case .guitar:
            out = pluck(frequency, sampleRate, n, seed: seed, decaySeconds: 3.2, brightness: 0.72, pickPosition: 0.14,
                        body: [(110, 0.35, 8), (215, 0.25, 10), (420, 0.12, 12), (2800, 0.05, 3)])
        case .ukulele:
            out = pluck(frequency, sampleRate, n, seed: seed, decaySeconds: 2.6, brightness: 0.42, pickPosition: 0.18,
                        body: [(250, 0.30, 8), (480, 0.18, 10), (1100, 0.06, 6)])
        case .bass:
            out = pluck(frequency, sampleRate, n, seed: seed, decaySeconds: 4.5, brightness: 0.35, pickPosition: 0.22,
                        body: [(80, 0.20, 6), (160, 0.10, 8)])
            lowpass(&out, cutoff: 2_400, sampleRate: sampleRate)
        case .violin:
            out = bowed(frequency, sampleRate, n, seed: seed, formants: [(280, 0.9, 5), (480, 0.7, 6), (1_000, 0.6, 3), (2_600, 0.8, 2.5), (4_200, 0.3, 3)])
        case .viola:
            out = bowed(frequency, sampleRate, n, seed: seed, formants: [(230, 0.9, 5), (400, 0.7, 6), (900, 0.6, 3), (2_200, 0.6, 2.5)])
        case .cello:
            out = bowed(frequency, sampleRate, n, seed: seed, formants: [(110, 0.8, 5), (220, 0.9, 6), (520, 0.6, 4), (1_500, 0.4, 3)])
        case .piano:
            out = struck(frequency, sampleRate, n)
        }
        normalize(&out, peak: amplitude)
        return out
    }

    /// 弓弦类持续音从这里开始可以循环（起音之后）。
    public static func loopStart(sampleRate: Double) -> Int { Int(0.6 * sampleRate) }

    // MARK: 拨弦

    private static func pluck(_ f: Double, _ sr: Double, _ count: Int, seed: UInt64, decaySeconds: Double,
                              brightness: Double, pickPosition: Double,
                              body: [(freq: Double, gain: Float, q: Double)]) -> [Float] {
        // 每圈衰减：让基音大约 decaySeconds 秒衰减 60 dB
        let loopsPerSecond = f
        let decay = pow(0.001, 1 / (decaySeconds * loopsPerSecond))
        var ks = KS(frequency: f, sampleRate: sr, decay: decay, brightness: brightness, pickPosition: pickPosition, seed: seed)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count { out[i] = ks.next() }
        // 琴体共鸣：几个谐振器并联，加回原信号
        if !body.isEmpty {
            var resonators = body.map { Biquad.bandpass(freq: $0.freq, q: $0.q, sampleRate: sr) }
            for i in 0..<count {
                let x = out[i]
                var y = x
                for r in resonators.indices { y += resonators[r].process(x) * body[r].gain }
                out[i] = y
            }
        }
        // 2 ms 起音斜坡，去掉咔哒
        let ramp = max(1, Int(0.002 * sr))
        for i in 0..<min(ramp, count) { out[i] *= Float(i) / Float(ramp) }
        return out
    }

    /// Karplus-Strong：噪声激励 + 拨弦位置梳状滤波 + 回路低通 + 全通小数延迟（音准误差几个音分以内）。
    private struct KS {
        var line: [Float]
        var pos = 0
        var lpPrev: Float = 0
        var apX: Float = 0, apY: Float = 0
        let a: Float
        let g: Float

        init(frequency: Double, sampleRate: Double, decay: Double, brightness: Double, pickPosition: Double, seed: UInt64) {
            let total = sampleRate / frequency - 0.5
            let n = max(2, Int((total - 0.5).rounded(.down)))
            let delta = total - Double(n)
            a = Float((1 - delta) / (1 + delta))
            g = Float(decay)
            var rng = seed == 0 ? 1 : seed
            func noise() -> Float {
                rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
                return Float(Double(rng % 200_001) / 100_000 - 1)
            }
            var buf = [Float](repeating: 0, count: n)
            var prev: Float = 0
            let k = Float(0.12 + 0.88 * brightness)
            for i in 0..<n { prev += k * (noise() - prev); buf[i] = prev }
            // 拨弦位置：减去延迟 βN 的自身，去掉相应的谐波（离琴桥越近声音越亮越薄）
            let d = max(1, Int(pickPosition * Double(n)))
            let original = buf
            for i in 0..<n { buf[i] = original[i] - original[(i + n - d) % n] }
            let mean = buf.reduce(0, +) / Float(n)
            for i in 0..<n { buf[i] -= mean }
            line = buf
        }

        mutating func next() -> Float {
            let head = line[pos]
            let lp = 0.5 * (head + lpPrev); lpPrev = head
            let ap = a * lp + apX - a * apY
            apX = lp; apY = ap
            line[pos] = ap * g
            pos += 1; if pos == line.count { pos = 0 }
            return head
        }
    }

    // MARK: 弓弦

    private static func bowed(_ f: Double, _ sr: Double, _ count: Int, seed: UInt64,
                              formants: [(freq: Double, gain: Float, q: Double)]) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        // 一个周期的波表：锯齿波谱（弓弦是 Helmholtz 运动），高次稍微压低；只到 9 kHz 以下，避免混叠
        let maxHarmonic = max(1, min(40, Int(min(9_000, sr / 2.2) / f)))
        let tableSize = 2048
        var table = [Float](repeating: 0, count: tableSize + 1)
        for k in 1...maxHarmonic {
            let level = 1 / Double(k) * exp(-Double(k) / 28)
            for j in 0..<tableSize { table[j] += Float(level * sin(2 * .pi * Double(k * j) / Double(tableSize))) }
        }
        table[tableSize] = table[0]
        var rng = seed == 0 ? 7 : seed
        func noise() -> Double {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return Double(rng % 200_001) / 100_000 - 1
        }
        var noiseLP = 0.0
        var phase = 0.0
        let attack = 0.12, vibratoStart = 0.5
        for i in 0..<count {
            let t = Double(i) / sr
            // 很浅的揉弦（±3 音分，5.3 Hz），起音后慢慢加入；平均音高不变
            let vib = min(1, max(0, (t - vibratoStart) / 0.6)) * 0.0017 * sin(2 * .pi * 5.3 * t)
            phase += f * (1 + vib) / sr
            if phase >= 1 { phase -= 1 }
            let x = phase * Double(tableSize)
            let j = Int(x), frac = Float(x - Double(j))
            var v = Double(table[j] + (table[j + 1] - table[j]) * frac)
            // 弓噪声：低通后的噪声，随弓压轻微起伏
            noiseLP += 0.08 * (noise() - noiseLP)
            v += noiseLP * 0.05 * (1 + 0.3 * sin(2 * .pi * 0.7 * t))
            let env = t < attack ? (t / attack) * (t / attack) : 1
            out[i] = Float(v * env * (1 + 0.02 * sin(2 * .pi * 3.1 * t)))
        }
        // 琴体共振峰：并联带通再和直达声混合
        var filters = formants.map { Biquad.bandpass(freq: $0.freq, q: $0.q, sampleRate: sr) }
        for i in 0..<count {
            let x = out[i]
            var y = x * 0.35
            for r in filters.indices { y += filters[r].process(x) * formants[r].gain }
            out[i] = y
        }
        return out
    }

    // MARK: 击弦（钢琴式）

    private static func struck(_ f: Double, _ sr: Double, _ count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let b = 0.00006 // 不谐和系数（太大会让听感音高偏高）
        let partials = max(1, min(16, Int((sr / 2.2) / f)))
        for i in 0..<count {
            let t = Double(i) / sr
            var v = 0.0
            for k in 1...partials {
                let kk = Double(k)
                let fk = f * kk * (1 + b * kk * kk).squareRoot()
                let decay = 0.6 + 0.35 * kk + f / 400
                v += (1 / kk) * exp(-decay * t) * sin(2 * .pi * fk * t)
            }
            let attack = min(1, t / 0.003)
            out[i] = Float(v * attack)
        }
        return out
    }

    // MARK: 工具

    private static func lowpass(_ x: inout [Float], cutoff: Double, sampleRate: Double) {
        let k = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
        var y: Float = 0
        for i in x.indices { y += k * (x[i] - y); x[i] = y }
    }

    private static func normalize(_ x: inout [Float], peak: Float) {
        let m = x.map { abs($0) }.max() ?? 0
        guard m > 0 else { return }
        let s = peak / m
        for i in x.indices { x[i] *= s }
    }
}

/// 二阶带通（RBJ cookbook，0 dB 峰值增益）。
struct Biquad {
    var b0, b1, b2, a1, a2: Float
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    static func bandpass(freq: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(freq, sampleRate * 0.45) / sampleRate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(b0: Float(alpha / a0), b1: 0, b2: Float(-alpha / a0),
                      a1: Float(-2 * cos(w) / a0), a2: Float((1 - alpha) / a0))
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

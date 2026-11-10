import Foundation

/// 程序合成的点击音色，不用任何采样素材。每个音的起音点都在第 0 个采样，保证落拍准确。
public enum ClickSynth {
    /// 合成一个音。返回峰值归一化到 0.95 的单声道采样。
    public static func make(_ sound: SoundKind, _ level: VoiceLevel, sampleRate: Double) -> [Float] {
        let sr = sampleRate
        switch sound {
        case .woodblock: return woodblock(level, sr)
        case .electronic: return electronic(level, sr)
        case .cowbell: return cowbell(level, sr)
        case .tick: return tick(level, sr)
        case .block: return block(level, sr)
        case .clave: return clave(level, sr)
        case .click, .voice: return click(level, sr)    // 人声报数的切分点、还没生成好时用咔嗒
        case .digital: return digital(level, sr)
        case .sonar: return sonar(level, sr)
        case .rimshot: return rimshot(level, sr)
        case .hihat: return hihat(level, sr)
        case .kickSnare: return kickSnare(level, sr)
        case .shaker: return shaker(level, sr)
        case .marimba: return marimba(level, sr)
        case .triangle: return triangle(level, sr)
        case .bell: return bell(level, sr)
        case .custom: return woodblock(level, sr)      // 还没录时用木鱼
        }
    }

    /// 木鱼：衰减很快的正弦基音 + 非谐波泛音 + 一点噪声起音。
    private static func woodblock(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [1650, 1320, 1050][level.rawValue]
        var noise = Noise()
        return render(seconds: 0.12, sr) { t in
            let body = sin(2 * .pi * f * t) * exp(-t / 0.018)
            let overtone = 0.35 * sin(2 * .pi * f * 2.76 * t) * exp(-t / 0.007)
            let knock = 0.25 * noise.next() * exp(-t / 0.0015)
            return body + overtone + knock
        }
    }

    /// 哔声：带一点三次谐波的短促 beep。
    private static func electronic(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [2093, 1760, 1319][level.rawValue]
        return render(seconds: 0.07, sr) { t in
            let wave = sin(2 * .pi * f * t) + 0.25 * sin(2 * .pi * 3 * f * t)
            let release = t > 0.055 ? max(0, 1 - (t - 0.055) / 0.015) : 1
            return wave * exp(-t / 0.03) * release
        }
    }

    /// 牛铃：仿 808 的两个方波（只取奇次谐波防止混叠），快衰减加慢尾音。
    private static func cowbell(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let pitch: Double = [1.12, 1.0, 0.89][level.rawValue]
        let f1 = 587 * pitch, f2 = 845 * pitch
        return render(seconds: 0.3, sr) { t in
            let env = 0.65 * exp(-t / 0.012) + 0.35 * exp(-t / 0.09)
            return (square(f1, t, sr) + square(f2, t, sr)) * env
        }
    }

    /// 机械摆锤：金属棘轮的“嘀/嗒”——一下噪声敲击加两个高频共振，强拍多一个低一点的木质“哒”。
    private static func tick(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let p: Double = [1.0, 0.9, 0.82][level.rawValue]
        var noise = Noise(state: 0x2468_ACE0)
        return render(seconds: 0.06, sr) { t in
            let hit = noise.next() * exp(-t / 0.0007)
            let ring = 0.6 * sin(2 * .pi * 3300 * p * t) * exp(-t / 0.006)
                + 0.4 * sin(2 * .pi * 4870 * p * t) * exp(-t / 0.004)
            let tock = level == .strong ? 0.5 * sin(2 * .pi * 1250 * t) * exp(-t / 0.012) : 0
            return hit + ring + tock
        }
    }

    /// 木块：比木鱼低、更“空”的两个模态。
    private static func block(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [1180, 990, 860][level.rawValue]
        var noise = Noise(state: 0x1357_9BDF)
        return render(seconds: 0.1, sr) { t in
            let body = sin(2 * .pi * f * t) * exp(-t / 0.022)
            let second = 0.45 * sin(2 * .pi * f * 1.58 * t) * exp(-t / 0.012)
            let knock = 0.3 * noise.next() * exp(-t / 0.001)
            return body + second + knock
        }
    }

    /// 响棒：几乎是纯音的清脆短音，带一点下滑。
    private static func clave(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [2650, 2450, 2250][level.rawValue]
        return render(seconds: 0.08, sr) { t in
            let phase = 2 * .pi * f * (t - 0.6 * t * t)
            return sin(phase) * exp(-t / 0.016)
        }
    }

    /// 咔嗒：很短的高频脉冲（声音只有几毫秒，缓冲区留长一点给尾巴归零）。
    private static func click(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [5200, 4300, 3500][level.rawValue]
        var noise = Noise(state: 0x0F0F_1234)
        return render(seconds: 0.03, sr) { t in
            sin(2 * .pi * f * t) * exp(-t / 0.0012) + 0.3 * noise.next() * exp(-t / 0.0004)
        }
    }

    /// 数码：短方波（老式电子节拍器的 beep）。
    private static func digital(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [1200, 1000, 800][level.rawValue]
        return render(seconds: 0.06, sr) { t in
            let gate = t < 0.04 ? 1 : max(0, 1 - (t - 0.04) / 0.012)
            return square(f, t, sr) * gate
        }
    }

    /// 柔和：起音稍缓、尾音长的正弦，像声呐。
    private static func sonar(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [988, 784, 659][level.rawValue]
        return render(seconds: 0.25, sr) { t in
            let attack = min(1, t / 0.004)
            return (sin(2 * .pi * f * t) + 0.15 * sin(2 * .pi * 2 * f * t)) * attack * exp(-t / 0.06)
        }
    }

    /// 鼓边：噪声爆裂 + 鼓体低音 + 一点金属鸣响。
    private static func rimshot(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let p: Double = [1.1, 1.0, 0.9][level.rawValue]
        var noise = Noise(state: 0x5555_AAAA)
        return render(seconds: 0.12, sr) { t in
            let crack = noise.next() * exp(-t / 0.003)
            let body = 0.7 * sin(2 * .pi * 470 * p * t) * exp(-t / 0.02)
            let ring = 0.35 * sin(2 * .pi * 1750 * p * t) * exp(-t / 0.012)
            return crack + body + ring
        }
    }

    /// 踩镲：六个不协和方波叠加（仿 808），一阶差分去掉低频，强拍尾音长（半开），弱拍很短（闭合）。
    private static func hihat(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let decay: Double = [0.09, 0.05, 0.03][level.rawValue]
        let freqs: [Double] = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].map { $0 * 3.3 }
        var previous = 0.0
        return render(seconds: 0.25, sr) { t in
            var metal = 0.0
            for f in freqs { metal += sin(2 * .pi * f * t) >= 0 ? 1 : -1 }
            let high = metal - previous
            previous = metal
            return high * exp(-t / decay)
        }
    }

    /// 底鼓军鼓：强拍是底鼓（下滑的低音），次强、弱拍是军鼓（噪声 + 鼓体）。
    private static func kickSnare(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        if level == .strong {
            // 频率从 160 Hz 指数下滑到 50 Hz，相位是频率的积分
            return render(seconds: 0.3, sr) { t in
                let phase = 2 * .pi * (50 * t + 110 * 0.03 * (1 - exp(-t / 0.03)))
                return sin(phase) * exp(-t / 0.12) + 0.3 * sin(2 * .pi * 1000 * t) * exp(-t / 0.002)
            }
        }
        let decay: Double = level == .medium ? 0.09 : 0.05
        var noise = Noise(state: 0x7777_1111)
        return render(seconds: 0.2, sr) { t in
            let snares = noise.next() * exp(-t / decay)
            let body = 0.6 * sin(2 * .pi * 190 * t) * exp(-t / 0.04)
            return snares + body
        }
    }

    /// 沙锤：差分后的高频噪声，起音稍缓。
    private static func shaker(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let decay: Double = [0.045, 0.035, 0.025][level.rawValue]
        var noise = Noise(state: 0x3141_5926)
        var previous = 0.0
        return render(seconds: 0.15, sr) { t in
            let n = noise.next()
            let high = n - previous
            previous = n
            let attack = min(1, t / 0.006)
            return high * attack * exp(-t / decay)
        }
    }

    /// 马林巴：基音 + 4 倍泛音（音板的特征），强 C6、次强 G5、弱 E5。
    private static func marimba(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [1046.5, 784.0, 659.3][level.rawValue]
        return render(seconds: 0.35, sr) { t in
            sin(2 * .pi * f * t) * exp(-t / 0.09) + 0.25 * sin(2 * .pi * 3.93 * f * t) * exp(-t / 0.015)
        }
    }

    /// 三角铁：高频非谐波泛音，尾音长。
    private static func triangle(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [3150, 2900, 2650][level.rawValue]
        return render(seconds: 0.6, sr) { t in
            (sin(2 * .pi * f * t) + 0.6 * sin(2 * .pi * 2.76 * f * t) + 0.4 * sin(2 * .pi * 5.40 * f * t)) * exp(-t / 0.16)
        }
    }

    /// 铃：钟的几个典型分音（1、2、2.4、3、4.07）。
    private static func bell(_ level: VoiceLevel, _ sr: Double) -> [Float] {
        let f: Double = [1318.5, 1108.7, 987.8][level.rawValue]
        let partials: [(Double, Double, Double)] = [(1, 1, 0.14), (2, 0.6, 0.1), (2.4, 0.4, 0.08), (3, 0.3, 0.06), (4.07, 0.2, 0.04)]
        return render(seconds: 0.5, sr) { t in
            var s = 0.0
            for (ratio, amp, decay) in partials where ratio * f < sr / 2 {
                s += amp * sin(2 * .pi * ratio * f * t) * exp(-t / decay)
            }
            return s
        }
    }

    /// 只取奇次谐波的方波，频率超过奈奎斯特的谐波丢掉，避免混叠。
    private static func square(_ f: Double, _ t: Double, _ sr: Double) -> Double {
        var s = 0.0
        for k in stride(from: 1, through: 9, by: 2) where Double(k) * f < sr / 2 {
            s += sin(2 * .pi * Double(k) * f * t) / Double(k)
        }
        return s
    }

    /// 逐点采样，加 0.3 ms 起音斜坡防爆音，结尾 2 ms 淡出，最后峰值归一化。
    private static func render(seconds: Double, _ sr: Double, _ f: (Double) -> Double) -> [Float] {
        let n = Int(seconds * sr)
        let attack = max(1, Int(0.0003 * sr))
        let release = max(1, Int(0.002 * sr))
        var out = [Float](repeating: 0, count: n)
        var peak: Float = 0
        for i in 0..<n {
            let t = Double(i) / sr
            var v = f(t)
            if i < attack { v *= Double(i + 1) / Double(attack) }
            if i >= n - release { v *= Double(n - i) / Double(release) }
            out[i] = Float(v)
            peak = max(peak, abs(out[i]))
        }
        if peak > 0 {
            let scale = 0.95 / peak
            for i in 0..<n { out[i] *= scale }
        }
        return out
    }

    /// 可复现的白噪声（线性同余）。
    private struct Noise {
        var state: UInt32 = 0x1234_5678
        mutating func next() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
    }
}

/// 预先合成好的全部音色 × 3 档，存在固定内存里，音频线程只读。
///
/// 另有 18 个动态槽位：0、1 是“我的声音”的强拍、弱拍录音，2…17 是人声报数的 1…16。
/// 界面线程用 `setDynamic` 写入（会按本机采样率重采样），音频线程用 `dynamicBuffer` 读。
/// 写入时先把长度置 0、再拷数据、最后写长度，正在播的那一下最多听到半截，不会读越界。
public final class VoiceBank: @unchecked Sendable {
    public static let customStrongSlot = 0
    public static let customWeakSlot = 1
    public static let countSlots = 16
    public static let dynamicSlotCount = 2 + countSlots
    /// 每个动态槽位最长 2 秒。
    public static let dynamicMaxSeconds = 2.0

    public static func countSlot(_ beatInBar: Int) -> Int { 2 + min(max(beatInBar, 0), countSlots - 1) }

    public let sampleRate: Double
    private let storage: UnsafeMutablePointer<UnsafeMutableBufferPointer<Float>>
    private let slotCount = SoundKind.allCases.count * VoiceLevel.allCases.count
    private let dynamicCapacity: Int
    private let dynamicData: UnsafeMutablePointer<Float>
    private let dynamicLengths: UnsafeMutablePointer<Int>

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        storage = .allocate(capacity: slotCount)
        for sound in SoundKind.allCases {
            for level in VoiceLevel.allCases {
                let samples = ClickSynth.make(sound, level, sampleRate: sampleRate)
                let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
                _ = buffer.initialize(from: samples)
                (storage + Self.slot(sound, level)).initialize(to: buffer)
            }
        }
        dynamicCapacity = Int(Self.dynamicMaxSeconds * sampleRate)
        dynamicData = .allocate(capacity: dynamicCapacity * Self.dynamicSlotCount)
        dynamicData.initialize(repeating: 0, count: dynamicCapacity * Self.dynamicSlotCount)
        dynamicLengths = .allocate(capacity: Self.dynamicSlotCount)
        dynamicLengths.initialize(repeating: 0, count: Self.dynamicSlotCount)
    }

    deinit {
        for i in 0..<slotCount { storage[i].deallocate() }
        storage.deallocate()
        dynamicData.deallocate()
        dynamicLengths.deallocate()
    }

    public func buffer(_ sound: SoundKind, _ level: VoiceLevel) -> UnsafeMutableBufferPointer<Float> {
        storage[Self.slot(sound, level)]
    }

    /// 动态槽位的声音；还没写入时为 nil。音频线程调用。
    public func dynamicBuffer(_ slot: Int) -> UnsafeMutableBufferPointer<Float>? {
        let n = dynamicLengths[slot]
        guard n > 0 else { return nil }
        return UnsafeMutableBufferPointer(start: dynamicData + slot * dynamicCapacity, count: n)
    }

    /// 写入一个动态槽位（空数组表示清空）。`sourceRate` 和本机采样率不同时线性插值重采样。
    public func setDynamic(_ slot: Int, samples: [Float], sourceRate: Double) {
        guard (0..<Self.dynamicSlotCount).contains(slot) else { return }
        dynamicLengths[slot] = 0
        let resampled = Self.resample(samples, from: sourceRate, to: sampleRate)
        let n = min(resampled.count, dynamicCapacity)
        let base = dynamicData + slot * dynamicCapacity
        resampled.withUnsafeBufferPointer { src in
            if n > 0 { base.update(from: src.baseAddress!, count: n) }
        }
        dynamicLengths[slot] = n
    }

    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard !x.isEmpty, from > 0, to > 0, abs(from - to) > 0.5 else { return x }
        let ratio = from / to
        let count = Int(Double(x.count) / ratio)
        return (0..<count).map { i in
            let pos = Double(i) * ratio
            let j = Int(pos)
            let frac = Float(pos - Double(j))
            let a = x[min(j, x.count - 1)], b = x[min(j + 1, x.count - 1)]
            return a + (b - a) * frac
        }
    }

    // 音频线程会调用，不能用 allCases（可能分配内存），直接写死每种音色 3 档。
    private static func slot(_ sound: SoundKind, _ level: VoiceLevel) -> Int {
        sound.rawValue * 3 + level.rawValue
    }
}

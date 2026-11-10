import Foundation
import TunerKit

/// Karplus-Strong 拨弦合成：一段噪声在延迟线里循环并被低通，衰减后就是拨弦的声音。
/// 纯计算、不碰音频硬件，所以可以在测试里离线渲染并检测音高。
///
/// 用一阶全通滤波器做小数延迟，音准误差在几个音分以内（见测试）。
public struct KarplusStrong: Sendable {
    public let frequency: Double
    public let sampleRate: Double
    /// 每圈衰减系数，越接近 1 余音越长。
    public var decay: Double
    /// 噪声起音的亮度：0…1，越大越亮。
    public var brightness: Double

    public init(frequency: Double, sampleRate: Double = 44100, decay: Double = 0.996, brightness: Double = 0.6) {
        self.frequency = frequency; self.sampleRate = sampleRate
        self.decay = decay; self.brightness = brightness
    }

    /// 渲染 `duration` 秒的单声道采样，峰值约 `amplitude`。`seed` 决定噪声，相同参数结果完全一致。
    public func render(duration: Double, amplitude: Float = 0.5, seed: UInt64 = 1) -> [Float] {
        let count = max(0, Int(duration * sampleRate))
        guard count > 0, frequency > 10, frequency < sampleRate / 4 else { return [Float](repeating: 0, count: count) }

        // 回路里的低通 y = (x[n] + x[n-1]) / 2 带来 0.5 个采样的延迟，从总延迟里扣掉
        let total = sampleRate / frequency - 0.5
        let n = max(2, Int((total - 0.5).rounded(.down)))
        let delta = total - Double(n)                       // 0.5…1.5
        let a = Float((1 - delta) / (1 + delta))           // 全通系数：低频延迟 ≈ delta

        var rng = seed == 0 ? 1 : seed
        func noise() -> Float {                              // xorshift，-1…1
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return Float(Double(rng % 200_001) / 100_000 - 1)
        }
        // 起音：噪声 + 一阶低通，控制亮度
        var line = [Float](repeating: 0, count: n)
        var prev: Float = 0
        let k = Float(0.15 + 0.85 * brightness)
        for i in 0..<n {
            prev += k * (noise() - prev)
            line[i] = prev
        }
        let mean = line.reduce(0, +) / Float(n)
        for i in 0..<n { line[i] -= mean }
        let peak = max(line.map { abs($0) }.max() ?? 1, 0.0001)

        var out = [Float](repeating: 0, count: count)
        var pos = 0
        var lpPrev: Float = 0
        var apX: Float = 0, apY: Float = 0
        let g = Float(decay)
        for i in 0..<count {
            let head = line[pos]
            out[i] = head * amplitude / peak
            let lp = 0.5 * (head + lpPrev); lpPrev = head
            let ap = a * lp + apX - a * apY                  // 全通：y[n] = a·x[n] + x[n-1] − a·y[n-1]
            apX = lp; apY = ap
            line[pos] = ap * g
            pos += 1; if pos == n { pos = 0 }
        }
        return out
    }
}

/// 把一个按法按弦序扫一遍（扫弦）渲染成一段采样。
///
/// 声音来自 TunerKit 的真实乐器采样（`InstrumentTone` 默认用 `SampleBank`）：指法图上每根实际发声的弦各用一个采样，
/// 按弦序从低到高依次拨出，不弹的弦跳过。
public enum ChordStrummer {
    /// 扫弦时相邻两根弦的间隔（秒）：真实扫弦大约 25–40 毫秒。
    public static let defaultGap = 0.032

    /// 扫弦里每根弦的起拨时间（秒）：间隔带一点确定性的小抖动（±12%），同一个和弦每次一样。
    /// 声音和指法图动画共用它，所以画面和声音对得上。
    public static func strumTimes(count: Int, gap: Double = ChordStrummer.defaultGap, firstFrequency: Double) -> [Double] {
        var times: [Double] = []
        var start = 0.0
        for i in 0..<max(0, count) {
            if i > 0 {
                let jitter = 1 + 0.12 * sin(Double(i) * 2.399 + firstFrequency * 0.013)
                start += gap * jitter
            }
            times.append(start)
        }
        return times
    }

    /// - Parameters:
    ///   - gap: 相邻两根弦的间隔（秒）。每个间隔带一点确定性的小抖动（±12%），听起来不那么机械。
    ///   - tail: 最后一根弦之后留的余音（秒）；拨弦采样本身自然衰减约 3–4 秒。
    public static func render(frequencies: [Double], sampleRate: Double = 44100,
                              gap: Double = ChordStrummer.defaultGap, tail: Double = 3.0, amplitude: Float = 0.5,
                              voice: InstrumentTone.Voice? = nil) -> [Float] {
        guard !frequencies.isEmpty else { return [] }
        let total = Int((Double(frequencies.count - 1) * gap + tail) * sampleRate)
        var mix = [Float](repeating: 0, count: total)
        let each = amplitude / Float(max(2, frequencies.count)).squareRoot()
        let times = strumTimes(count: frequencies.count, gap: gap, firstFrequency: frequencies[0])
        for (i, f) in frequencies.enumerated() {
            let start = times[i]
            let startSample = min(total - 1, Int(start * sampleRate))
            let duration = Double(total - startSample) / sampleRate
            let seed = UInt64(i + 1) &* 7919
            // 向下扫弦：低音弦力度稍大，越往高音弦越轻
            let weight = Float(1 - 0.18 * Double(i) / Double(max(1, frequencies.count - 1)))
            // 指定乐器时用 InstrumentTone（真实采样，没有采样才回退到物理建模合成）；不指定时保持原来的 Karplus-Strong
            let tone = voice.map { InstrumentTone.render($0, frequency: f, sampleRate: sampleRate, duration: duration, amplitude: each * weight, seed: seed) }
                ?? KarplusStrong(frequency: f, sampleRate: sampleRate).render(duration: duration, amplitude: each * weight, seed: seed)
            for j in 0..<tone.count where startSample + j < total { mix[startSample + j] += tone[j] }
        }
        // 防削波：峰值超过 0.95 就整体压回去
        let peak = mix.map { abs($0) }.max() ?? 0
        if peak > 0.95 { let s = 0.95 / peak; for i in mix.indices { mix[i] *= s } }
        // 尾部淡出，避免咔哒
        let fade = min(total, Int(0.15 * sampleRate))
        for i in 0..<fade { mix[total - 1 - i] *= Float(i) / Float(fade) }
        return mix
    }

    /// 一个按法按物理弦序（从第一根弦到最后一根弦，即向下扫弦）的频率；不弹的弦跳过。
    public static func frequencies(for voicing: ChordVoicing, a4: Double = TunerDefaults.a4) -> [Double] {
        voicing.pitches.compactMap { $0?.frequency(a4: a4) }
    }

    // MARK: 按事件表渲染（扫弦、分解和弦共用）

    /// 把一段播放渲染成单声道采样。
    ///
    /// - 播一遍（`cycle == nil`）：长度 = 最后一下的时间 + 余音，末尾淡出；
    /// - 循环：长度正好是一个周期（取整到采样），超出周期的余音绕回开头叠加，所以接缝处听不出断点。
    /// 事件在缓冲里的位置就是 `Int(time × sampleRate)`，动画读到的播放位置和它是同一个时钟。
    public static func render(_ playback: ChordPlayback, sampleRate: Double) -> [Float] {
        guard !playback.events.isEmpty else { return [] }
        let lastStart = playback.events.map(\.time).max() ?? 0
        let noteSeconds = playback.noteSeconds ?? 2.6   // 每个音最长响多久（采样自然衰减约 3–4 秒，末尾再淡出）
        let total: Int
        if let cycle = playback.cycle { total = max(1, Int((cycle * sampleRate).rounded())) }
        else { total = Int((lastStart + playback.tail) * sampleRate) }
        // 同一个音在一段播放里长度固定，这样同一个音多次出现（连续扫弦）只渲染一次
        let noteDuration = playback.cycle == nil && playback.noteSeconds == nil
            ? min(noteSeconds + playback.tail, Double(total) / sampleRate) : noteSeconds
        var mix = [Float](repeating: 0, count: total)
        for e in playback.events {
            let startSample = Int((e.time * sampleRate).rounded())
            guard noteDuration > 0.01 else { continue }
            var tone = noteSamples(playback.voice, pitch: e.pitch, a4: playback.a4, sampleRate: sampleRate, duration: e.hold ?? noteDuration)
            // 循环时每个音在 noteSeconds 处淡出（最后 0.4 秒），避免突然截断；闷音（hold）很快切掉，只淡出最后 40 毫秒
            if e.hold != nil {
                let fade = min(tone.count, Int(0.04 * sampleRate))
                for k in 0..<fade { tone[tone.count - 1 - k] *= Float(k) / Float(fade) }
            } else if playback.cycle != nil || playback.noteSeconds != nil {
                let fade = min(tone.count, Int(0.4 * sampleRate))
                for k in 0..<fade { tone[tone.count - 1 - k] *= Float(k) / Float(fade) }
            }
            for j in 0..<tone.count {
                let index = startSample + j
                if index < total { mix[index] += tone[j] * e.gain }
                else if playback.cycle != nil { mix[index % total] += tone[j] * e.gain }
                else { break }
            }
        }
        let peak = mix.map { abs($0) }.max() ?? 0
        if peak > 0.95 { let s = 0.95 / peak; for i in mix.indices { mix[i] *= s } }
        if playback.cycle == nil {
            let fade = min(total, Int(0.15 * sampleRate))
            for i in 0..<fade { mix[total - 1 - i] *= Float(i) / Float(fade) }
        }
        return mix
    }

    // MARK: 单音缓存

    /// 一个音（峰值 1）。连续演奏时同一个和弦的音反复出现，缓存后只渲染一次。线程安全。
    static func noteSamples(_ voice: InstrumentTone.Voice, pitch: Pitch, a4: Double, sampleRate: Double, duration: Double) -> [Float] {
        let key = "\(voice.rawValue)|\(pitch.midi)|\(Int(a4 * 10))|\(Int(sampleRate))|\(Int((duration * 1000).rounded()))"
        noteCacheLock.lock()
        if let hit = noteCache[key] { noteCacheLock.unlock(); return hit }
        noteCacheLock.unlock()
        let tone = InstrumentTone.render(voice, frequency: pitch.frequency(a4: a4), sampleRate: sampleRate,
                                         duration: duration, amplitude: 1, seed: UInt64(pitch.midi) &* 7919)
        noteCacheLock.lock()
        if noteCacheOrder.count >= 240 { noteCache[noteCacheOrder.removeFirst()] = nil }
        noteCache[key] = tone
        noteCacheOrder.append(key)
        noteCacheLock.unlock()
        return tone
    }

    nonisolated(unsafe) private static var noteCache: [String: [Float]] = [:]
    nonisolated(unsafe) private static var noteCacheOrder: [String] = []
    private static let noteCacheLock = NSLock()
}

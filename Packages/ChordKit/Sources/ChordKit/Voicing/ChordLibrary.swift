import Foundation
import TunerKit

/// 和弦库的入口：给定乐器、定弦、和弦，返回按法列表。
///
/// ```swift
/// let c = Chord("C", .major7)!
/// let list = ChordLibrary.voicings(for: c, instrument: InstrumentLibrary.guitar)   // 吉他标准定弦
/// list[0].shorthand      // "x32000"
/// ```
public enum ChordLibrary {
    /// 和弦库里出现的乐器，顺序即界面上的分段控件顺序（设计稿 05：吉他、贝斯、尤克里里）。
    public static var instruments: [Instrument] {
        [InstrumentLibrary.guitar, InstrumentLibrary.bass, InstrumentLibrary.ukulele]
    }

    public static let types = ChordType.builtins

    /// 能扫弦的乐器大类：吉他、尤克里里。以后新增能扫弦的乐器（班卓、曼陀林……）在这里加一项，
    /// 训练页的扫弦节奏型、和弦库的“扫弦”模式都按这个属性决定哪些乐器可用；贝斯不能扫弦。
    public static let strummableFamilies: Set<InstrumentFamily> = [.guitar, .ukulele]

    /// 和弦库里能扫弦的乐器（顺序同 `instruments`）。
    public static var strummableInstruments: [Instrument] { instruments.filter(\.supportsStrumming) }

    /// 乐器是否有“指法图”（吉他、尤克里里）；贝斯用 `BassPositions`；其余乐器两者都没有。
    public static func supportsFingering(_ instrument: Instrument) -> Bool {
        VoicingRules.rules(for: instrument.family) != nil
    }

    /// 每个和弦最多保留的按法数。
    public static let maxVoicings = 8

    /// 某个和弦的按法，已按“开放把位优先 → 位置低优先 → 不弹的弦少优先”排好；
    /// 人工校对的标准按法排最前。贝斯和不支持的乐器返回空数组。
    public static func voicings(for chord: Chord, instrument: Instrument, tuning: Tuning? = nil) -> [ChordVoicing] {
        let tuning = tuning ?? instrument.defaultTuning
        let key = "\(instrument.id)/\(tuning.id)/\(tuning.strings.map { String($0.pitch.midi) }.joined(separator: ","))/\(chord.id)"
        return cache.value(for: key) {
            VoicingGenerator.voicings(chord: chord, instrumentID: instrument.id, tuning: tuning,
                                      family: instrument.family, limit: maxVoicings)
        }
    }

    private static let cache = VoicingCache()
}

/// 简单的线程安全缓存：和弦生成要穷举一遍，翻页时不该重复算。
final class VoicingCache: @unchecked Sendable {
    private var storage: [String: [ChordVoicing]] = [:]
    private let lock = NSLock()

    func value(for key: String, make: () -> [ChordVoicing]) -> [ChordVoicing] {
        lock.lock()
        if let hit = storage[key] { lock.unlock(); return hit }
        lock.unlock()
        let made = make()
        lock.lock(); storage[key] = made; lock.unlock()
        return made
    }
}

extension InstrumentFamily {
    /// 这类乐器能不能扫弦（见 `ChordLibrary.strummableFamilies`）。
    public var supportsStrumming: Bool { ChordLibrary.strummableFamilies.contains(self) }
}

extension Instrument {
    /// 这件乐器能不能扫弦：吉他、尤克里里是，贝斯不是。`RhythmStrummer` 只对能扫弦的乐器发声。
    public var supportsStrumming: Bool { family.supportsStrumming }
}

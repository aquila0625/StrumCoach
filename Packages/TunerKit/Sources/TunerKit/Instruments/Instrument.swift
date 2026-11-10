import Foundation

/// 乐器大类。调音器和以后的和弦库共用。
public enum InstrumentFamily: String, Codable, Sendable, CaseIterable {
    /// 半音阶（自动识别任意音，没有琴弦）。
    case chromatic
    case guitar, bass, ukulele
    case violin, viola, cello
}

/// 一根弦。
public struct InstrumentString: Hashable, Codable, Sendable, Identifiable {
    /// 在定弦里的位置，0 = 物理排列的第一根（吉他上是最粗的 6 弦）。
    public let index: Int
    /// 常规的弦号：吉他 6…1（6 弦最粗）。回弦乐器（如尤克里里）按物理位置编号。
    public let number: Int
    public let pitch: Pitch

    public var id: Int { index }

    public init(index: Int, number: Int, pitch: Pitch) {
        self.index = index; self.number = number; self.pitch = pitch
    }
}

/// 一种定弦，例如“吉他 · 标准 EADGBE”。
///
/// `strings` 按物理顺序排列（从最粗的一根到最细的一根），**不保证音高递增**：
/// 尤克里里的高音 G 定弦（G4 C4 E4 A4）第一根弦就比第二根高。
public struct Tuning: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let englishName: String
    public let strings: [InstrumentString]

    public init(id: String, name: String, englishName: String, pitches: [Pitch]) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.strings = pitches.enumerated().map {
            InstrumentString(index: $0.offset, number: pitches.count - $0.offset, pitch: $0.element)
        }
    }

    public init(id: String, name: String, englishName: String, notes: String) {
        let pitches = notes.split(separator: " ").compactMap { Pitch(String($0)) }
        self.init(id: id, name: name, englishName: englishName, pitches: pitches)
    }

    public var stringCount: Int { strings.count }
    public var isChromatic: Bool { strings.isEmpty }

    /// 去掉八度的音名简写，例如 "E A D G B E"。
    public func shortLabel(useFlats: Bool = false) -> String {
        strings.map { $0.pitch.name(useFlats: useFlats) }.joined(separator: " ")
    }
}

/// 一件乐器，带它的若干种定弦。
public struct Instrument: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let family: InstrumentFamily
    public let name: String
    public let englishName: String
    public let tunings: [Tuning]
    /// 默认定弦的 id（取 `tunings` 中的一个）。
    public let defaultTuningID: String

    public init(id: String, family: InstrumentFamily, name: String, englishName: String,
                tunings: [Tuning], defaultTuningID: String? = nil) {
        self.id = id
        self.family = family
        self.name = name
        self.englishName = englishName
        self.tunings = tunings
        self.defaultTuningID = defaultTuningID ?? tunings[0].id
    }

    public var defaultTuning: Tuning { tuning(id: defaultTuningID) ?? tunings[0] }
    public func tuning(id: String) -> Tuning? { tunings.first { $0.id == id } }
    public var isChromatic: Bool { family == .chromatic }
}

/// “选了哪件乐器、哪种定弦”：可存入 UserDefaults，调音器和和弦库共用。
public struct InstrumentSelection: Hashable, Codable, Sendable {
    public var instrumentID: String
    public var tuningID: String

    public init(instrumentID: String, tuningID: String) {
        self.instrumentID = instrumentID; self.tuningID = tuningID
    }

    public static let `default` = InstrumentSelection(instrumentID: "auto", tuningID: "chromatic")

    /// 解析为具体对象；id 失效时回退到该乐器的默认定弦，再回退到“自动”。
    public func resolve(in library: [Instrument] = InstrumentLibrary.all) -> (instrument: Instrument, tuning: Tuning) {
        let inst = library.first { $0.id == instrumentID } ?? library[0]
        let tuning = inst.tuning(id: tuningID) ?? inst.defaultTuning
        return (inst, tuning)
    }
}

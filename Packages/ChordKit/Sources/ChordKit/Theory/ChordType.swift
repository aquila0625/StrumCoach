import Foundation

/// 一种和弦类型：由距根音的半音数（`intervals`）定义。
///
/// **加新类型**：在 `ChordType.builtins` 里加一条即可（例如 `m6`、`9`），
/// 指法生成、组成音、界面网格都按数据工作，不需要改别处。
public struct ChordType: Hashable, Codable, Sendable, Identifiable {
    /// 稳定的标识，会被存进收藏，不要改已发布的 id。
    public let id: String
    /// 接在根音后面的和弦记号，例如 "maj7"；大三和弦为空串。
    public let symbol: String
    /// 界面按钮上的短名（设计稿 05 的“类型”网格）。
    public let shortName: String
    public let name: String
    public let englishName: String
    /// 各组成音距根音的半音数，第一个必须是 0（根音）。
    public let intervals: [Int]
    /// 各组成音的级数写法，与 `intervals` 一一对应，例如 ["1", "♭3", "5", "♭7"]。
    public let degrees: [String]
    /// 在弦不够用时允许省略的音（半音数）。通常是七和弦类的纯五度。
    public let optionalIntervals: [Int]

    public init(id: String, symbol: String, shortName: String, name: String, englishName: String,
                intervals: [Int], degrees: [String], optionalIntervals: [Int] = []) {
        precondition(intervals.first == 0 && intervals.count == degrees.count, "和弦类型定义不合法：\(id)")
        self.id = id; self.symbol = symbol; self.shortName = shortName
        self.name = name; self.englishName = englishName
        self.intervals = intervals; self.degrees = degrees; self.optionalIntervals = optionalIntervals
    }

    /// 内置类型，顺序即界面网格的显示顺序（设计稿 05）。
    public static let builtins: [ChordType] = [major, minor, dominant7, major7, minor7, sus2, sus4, diminished, augmented, add9]

    public static let major = ChordType(
        id: "major", symbol: "", shortName: "大三", name: "大三和弦", englishName: "Major",
        intervals: [0, 4, 7], degrees: ["1", "3", "5"])
    public static let minor = ChordType(
        id: "minor", symbol: "m", shortName: "小三", name: "小三和弦", englishName: "Minor",
        intervals: [0, 3, 7], degrees: ["1", "♭3", "5"])
    public static let dominant7 = ChordType(
        id: "dom7", symbol: "7", shortName: "7", name: "属七和弦", englishName: "Dominant 7th",
        intervals: [0, 4, 7, 10], degrees: ["1", "3", "5", "♭7"], optionalIntervals: [7])
    public static let major7 = ChordType(
        id: "maj7", symbol: "maj7", shortName: "maj7", name: "大七和弦", englishName: "Major 7th",
        intervals: [0, 4, 7, 11], degrees: ["1", "3", "5", "7"], optionalIntervals: [7])
    public static let minor7 = ChordType(
        id: "m7", symbol: "m7", shortName: "m7", name: "小七和弦", englishName: "Minor 7th",
        intervals: [0, 3, 7, 10], degrees: ["1", "♭3", "5", "♭7"], optionalIntervals: [7])
    public static let sus2 = ChordType(
        id: "sus2", symbol: "sus2", shortName: "sus2", name: "挂二和弦", englishName: "Suspended 2nd",
        intervals: [0, 2, 7], degrees: ["1", "2", "5"])
    public static let sus4 = ChordType(
        id: "sus4", symbol: "sus4", shortName: "sus4", name: "挂四和弦", englishName: "Suspended 4th",
        intervals: [0, 5, 7], degrees: ["1", "4", "5"])
    public static let diminished = ChordType(
        id: "dim", symbol: "dim", shortName: "dim", name: "减三和弦", englishName: "Diminished",
        intervals: [0, 3, 6], degrees: ["1", "♭3", "♭5"])
    public static let augmented = ChordType(
        id: "aug", symbol: "aug", shortName: "aug", name: "增三和弦", englishName: "Augmented",
        intervals: [0, 4, 8], degrees: ["1", "3", "♯5"])
    public static let add9 = ChordType(
        id: "add9", symbol: "add9", shortName: "add9", name: "加九和弦", englishName: "Add 9",
        intervals: [0, 4, 7, 14], degrees: ["1", "3", "5", "9"], optionalIntervals: [7])

    public static func type(id: String) -> ChordType? { builtins.first { $0.id == id } }

    /// 把八度以上的音折回一个八度之内（半音数 mod 12）。
    public var pitchClassIntervals: [Int] { intervals.map { $0 % 12 } }
    /// 允许省略的音（折回八度内）。
    var optionalPitchClasses: Set<Int> { Set(optionalIntervals.map { $0 % 12 }) }
}

import Foundation
import TunerKit

/// 节奏型里的一格。记号（`rawValue`）：
///
/// | 记号 | 含义 | 发声 |
/// | --- | --- | --- |
/// | `B` | 根音 | 只拨当前按法的**根音弦**一下（力度略重） |
/// | `D` | 下扫 · 全扫 | 从**根音弦**扫到 1 弦（根音弦以下的低音弦不扫） |
/// | `d` | 下扫 · 半扫 | 只扫高音的 3–4 根弦（吉他 1–4 弦或 1–3 弦，尤克里里 1–3 弦） |
/// | `U` | 上扫 | 半扫：从 1 弦往回扫高音的 3–4 根弦 |
/// | `X` | 闷音 | 手掌压弦扫一下，只有“嚓”的声音 |
/// | `.` / `-` | 空拍 | 不发声 |
///
/// 解析时**只有 `D` 和 `d` 区分大小写**，其他字母不分大小写（`b` = `B`，`u` = `U`，`x` = `X`）。
public enum StrumCell: Character, Codable, Sendable, CaseIterable {
    case down = "D"
    case up = "U"
    case mute = "X"
    case rest = "."
    /// 根音：只拨根音弦。
    case bass = "B"
    /// 下扫 · 半扫：只扫高音的几根弦。
    case downTreble = "d"

    /// 这一格要不要扫（闷音也要扫，有起音）。
    public var isStroke: Bool { self != .rest }

    /// 文字里的箭头（`D` 是 ↓，`d` 是 ⇣ 表示只扫一部分，`U` 是 ↑，`B` 是 ●）。界面里用大小不同的箭头画，见 `StrumGlyph`。
    public var arrow: String {
        switch self {
        case .down: return "↓"
        case .downTreble: return "⇣"
        case .up: return "↑"
        case .bass: return "●"
        case .mute: return "✕"
        case .rest: return "·"
        }
    }

    /// 从输入的一个字符认出一格：`D`（全扫）和 `d`（半扫）区分大小写，`B` `U` `X` 不分，`.` `-` 是空拍。
    public init?(typed ch: Character) {
        switch ch {
        case "D", "Ｄ": self = .down
        case "d", "ｄ": self = .downTreble
        case "B", "b", "Ｂ", "ｂ": self = .bass
        case "U", "u", "Ｕ", "ｕ": self = .up
        case "X", "x", "Ｘ", "ｘ": self = .mute
        case "-", ".": self = .rest
        default: return nil
        }
    }
}

/// 扫弦节奏型：一小节里按八分（或十六分）排好的格子。和弦库的“扫弦”模式和训练页的“扫弦节奏型”共用。
///
/// - `cellsPerBeat`：每拍几格，八分是 2、十六分是 4；
/// - 一小节的拍数 = 格数 ÷ 每拍格数（4/4 是 4 拍，3/4 是 3 拍，1…8 拍都可以）；
/// - 写法：`B` 根音、`D` 全扫、`d` 半扫、`U` 上扫、`X` 闷音、`.`（或 `-`）空拍，例如民谣 `D.DU.UDU`、乡村 `B.dUB.dU`（见 `StrumCell`）。
public struct StrumRhythm: Identifiable, Hashable, Sendable {
    public let id: String
    public let cells: [StrumCell]
    public let cellsPerBeat: Int
    /// 名称：预设是简体中文原文（String Catalog 的键），自定义是用户起的名字（空串表示用箭头当名字）。
    public let title: String
    public let englishTitle: String

    /// 格数必须是每拍格数的整数倍（至少一拍）；字符只能是 D U X . -。不合格返回 nil。
    public init?(id: String, code: String, cellsPerBeat: Int = 2, title: String = "", englishTitle: String = "") {
        let cells = code.compactMap { StrumCell(typed: $0) }
        guard cellsPerBeat > 0, cells.count == code.count, !cells.isEmpty, cells.count % cellsPerBeat == 0 else { return nil }
        self.id = id; self.cells = cells; self.cellsPerBeat = cellsPerBeat
        self.title = title; self.englishTitle = englishTitle
    }

    public var beatsPerBar: Int { cells.count / cellsPerBeat }
    public var isCustom: Bool { id.hasPrefix(Self.customPrefix) }
    public static let customPrefix = "custom-"

    /// 规范写法，例如 "D.DU.UDU"。
    public var code: String { String(cells.map(\.rawValue)) }

    /// 例如 "↓ · ↓↑ · ↑↓↑"：每拍一组。
    public var arrows: String {
        stride(from: 0, to: cells.count, by: cellsPerBeat).map { start in
            cells[start..<start + cellsPerBeat].map(\.arrow).joined()
        }.joined(separator: " ")
    }

    /// 第 i 格在拍子里的读法：1 & 2 &（十六分是 1 e & a）。
    public func countLabel(_ i: Int) -> String {
        let beat = i / cellsPerBeat + 1
        let sub = i % cellsPerBeat
        if sub == 0 { return "\(beat)" }
        if cellsPerBeat == 4 { return ["", "e", "&", "a"][sub] }
        return "&"
    }

    // MARK: 时间

    public static func beatDuration(bpm: Double) -> Double { 60 / min(max(bpm, 30), 300) }
    public func cellDuration(bpm: Double) -> Double { Self.beatDuration(bpm: bpm) / Double(cellsPerBeat) }
    /// 一小节的长度（秒）。
    public func barDuration(bpm: Double) -> Double { Self.beatDuration(bpm: bpm) * Double(beatsPerBar) }

    /// 一小节里每个要扫的格：序号、相对小节起点的时间（秒）、种类。不含空拍。
    public func strokes(bpm: Double) -> [(index: Int, time: Double, cell: StrumCell)] {
        let d = cellDuration(bpm: bpm)
        return cells.enumerated().compactMap { i, c in c.isStroke ? (i, Double(i) * d, c) : nil }
    }

    /// 某个时刻（相对小节起点，秒）落在第几格。
    public func cellIndex(at time: Double, bpm: Double) -> Int {
        let d = cellDuration(bpm: bpm)
        return min(cells.count - 1, max(0, Int((time / d).rounded(.down))))
    }

    /// 这一格扫的力度：小节第一下最重，其余拍点下扫次之，反拍的下扫更轻，上扫最轻；闷音居中。
    public func velocity(ofCell i: Int) -> Float {
        switch cells[i] {
        case .down: return i == 0 ? 1.25 : (i % cellsPerBeat == 0 ? 1.0 : 0.85)
        case .downTreble: return i % cellsPerBeat == 0 ? 0.9 : 0.8
        case .up: return 0.7
        case .bass: return i == 0 ? 1.3 : 1.15            // 根音单拨：力度略重
        case .mute: return 0.9
        case .rest: return 0
        }
    }

    // MARK: 预设

    private static func preset(_ id: String, _ code: String, _ title: String, _ english: String, perBeat: Int = 2) -> StrumRhythm {
        StrumRhythm(id: id, code: code, cellsPerBeat: perBeat, title: title, englishTitle: english)!
    }

    public static let folk1 = preset("folk1", "D.DU.UDU", "民谣 1", "Folk 1")
    public static let folk2 = preset("folk2", "D.DUDUDU", "民谣 2", "Folk 2")
    public static let eighths = preset("eighths", "DUDUDUDU", "八分全扫", "All eighths")
    public static let quarters = preset("quarters", "D.D.D.D.", "四分", "Quarter")
    public static let waltz = preset("waltz", "D.DUDU", "慢摇 / 华尔兹 3/4", "Slow / Waltz 3/4")
    public static let chunk = preset("chunk", "D.XU.UXU", "切音节奏", "Chuck strum")
    public static let funk = preset("funk", "DUDUXUDUDUDUXUDU", "十六分 Funk", "16th Funk", perBeat: 4)
    /// 尤克里里：岛屿扫弦（D · D U · U D U）和常用的 D · D U D U D U。
    public static let island = preset("island", "D.DU.UDU", "岛屿扫弦", "Island strum")
    public static let ukeBasic = preset("ukeBasic", "D.DUDUDU", "基础扫弦", "Basic strum")

    /// 根音扫弦：根音、全扫、根音、全扫（每拍一下，四拍）。
    public static let rootStrum = preset("rootStrum", "B.D.B.D.", "根音扫弦", "Root strum")
    /// 乡村：根音、半扫下上、根音、半扫下上（八分）。
    public static let country = preset("country", "B.dUB.dU", "乡村", "Country")
    /// 华尔兹根音：根音、半扫、半扫（3/4）。
    public static let waltzBass = preset("waltzBass", "B.d.d.", "华尔兹根音", "Waltz bass")

    /// 所有预设（id 查找用）。
    public static let allPresets: [StrumRhythm] = [folk1, folk2, eighths, quarters, waltz, chunk, funk, island, ukeBasic,
                                                   rootStrum, country, waltzBass]

    /// 某类乐器推荐的预设，第一个是默认值。尤克里里以岛屿扫弦开头，其余（吉他和以后新增的可扫弦乐器）以民谣 1 开头。
    public static func presets(for family: InstrumentFamily) -> [StrumRhythm] {
        switch family {
        case .ukulele: return [island, ukeBasic, eighths, quarters, waltz, chunk, funk, rootStrum, country, waltzBass]
        default: return [folk1, folk2, eighths, quarters, waltz, chunk, funk, rootStrum, country, waltzBass]
        }
    }

    public static func preset(id: String) -> StrumRhythm? { allPresets.first { $0.id == id } }
}

// MARK: - 自定义输入

/// 解析用户输入的节奏型的结果。
public struct StrumParse: Equatable, Sendable {
    public enum Failure: Equatable, Sendable {
        case empty
        /// 有无法识别的字符（对应的 token 无效，界面标红）。
        case invalidCharacters
        /// 超过 `StrumInput.maxBeats` 拍。
        case tooLong
        /// 格数不是每拍格数的整数倍。
        case notWholeBeats
    }

    public struct Token: Equatable, Sendable {
        public let text: String
        public let isValid: Bool
    }

    public let tokens: [Token]
    public let cells: [StrumCell]
    public let failure: Failure?
    public var isValid: Bool { failure == nil }
    /// 规范写法，例如 "D.DU.UDU"。
    public var normalized: String { String(cells.map(\.rawValue)) }
}

/// 自定义节奏型的输入规则：每个字符一格，`B` 根音、`D` 全扫、`d` 半扫、`U` 上扫、`X` 闷音、`-` 或 `.` 空拍
/// （只有 `D` / `d` 区分大小写，其他字母不分大小写；早期版本里小写 `d` 等同 `D`，但保存的自定义节奏型一直存大写，所以数据不受影响）；
/// 空格、`|`、逗号只用来分组，不占格。格数必须是每拍格数（八分 2、十六分 4）的整数倍，最多 8 拍。
/// iPhone 的智能标点把 `--` / `...` 换成的 `–` / `…` 会按原来的个数还原成空拍（见 `parse`）。
public enum StrumInput {
    public static let maxBeats = 8
    public static let maxSaved = 10

    private static let separators: Set<Character> = [" ", "\t", "\n", "|", ",", "，", "、", ";", "；", "/"]

    public static func parse(_ text: String, cellsPerBeat: Int) -> StrumParse {
        var tokens: [StrumParse.Token] = []
        var cells: [StrumCell] = []
        func rests(_ n: Int) { for _ in 0..<n { cells.append(.rest); tokens.append(.init(text: ".", isValid: true)) } }
        for ch in text where !separators.contains(ch) && !ch.isWhitespace {
            // 记号：B 根音、D 全扫、d 半扫、U 上扫、X 闷音、- / . 空拍；只有 D 和 d 区分大小写
            if let cell = StrumCell(typed: ch) {
                cells.append(cell)
                tokens.append(.init(text: cell == .rest ? "." : String(cell.rawValue), isValid: true))
                continue
            }
            switch ch {
            case "．", "‐", "‑", "−", "－", "。", "·", "_": rests(1)
            // iPhone 的“智能标点”会把连着输入的 `--` 换成 `–`、`---` 换成 `—`、`..` 换成 `‥`、`...` 换成 `…`：
            // 按原来输入的个数还原成对应数量的空拍，连续的空拍就不会被吃掉或标红
            case "–", "‥": rests(2)
            case "—", "…": rests(3)
            default: tokens.append(.init(text: String(ch), isValid: false))
            }
        }
        let failure: StrumParse.Failure?
        if tokens.contains(where: { !$0.isValid }) { failure = .invalidCharacters }
        else if cells.isEmpty { failure = .empty }
        else if cells.count > maxBeats * cellsPerBeat { failure = .tooLong }
        else if cells.count % cellsPerBeat != 0 { failure = .notWholeBeats }
        else { failure = nil }
        return StrumParse(tokens: tokens, cells: cells, failure: failure)
    }
}

/// 用户保存的一个自定义节奏型。按乐器大类分别保存。
///
/// **存储格式版本**：`v = 2` 起小写 `d` 是半扫。没有 `v` 的旧数据里，小写 `d` 等同 `D`（旧版本不分大小写），
/// 所以解码时把没有版本号的 `code` 整体转成大写，保持原来的效果；旧版本存的本来就是大写的规范写法，所以通常没有变化。
public struct CustomStrumRhythm: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    /// 规范写法，例如 "D.DU.UDU"、"B.dUB.dU"。
    public var code: String
    /// 每拍几格（2 或 4）。
    public var cellsPerBeat: Int

    public static let formatVersion = 2

    public init(id: String = UUID().uuidString, name: String = "", code: String, cellsPerBeat: Int = 2) {
        self.id = id; self.name = name; self.code = code; self.cellsPerBeat = cellsPerBeat
    }

    private enum CodingKeys: String, CodingKey { case id, name, code, cellsPerBeat, v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let raw = try c.decode(String.self, forKey: .code)
        cellsPerBeat = try c.decode(Int.self, forKey: .cellsPerBeat)
        let version = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        code = version >= Self.formatVersion ? raw : raw.uppercased()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(code, forKey: .code)
        try c.encode(cellsPerBeat, forKey: .cellsPerBeat)
        try c.encode(Self.formatVersion, forKey: .v)
    }

    public var rhythm: StrumRhythm? {
        StrumRhythm(id: StrumRhythm.customPrefix + id, code: code, cellsPerBeat: cellsPerBeat, title: name, englishTitle: name)
    }
}

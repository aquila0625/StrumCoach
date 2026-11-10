import Foundation
import TunerKit

/// 自定义分解指法里的一步：一根弦、“当前和弦的根音弦”，或空拍（不弹，占一个音的时值）。
public enum ArpeggioStep: Hashable, Sendable {
    case string(Int)
    case root
    case rest
}

/// 解析用户输入的指法（一串弦号）的结果。
public struct ArpeggioParse: Equatable, Sendable {
    public enum Failure: Equatable, Sendable {
        /// 没有任何要弹的音（空的，或者全是空拍）。
        case empty
        /// 有无法识别的字符，或弦号超出这件乐器的弦数（对应的字符在 `tokens` 里标为无效，界面标红）。
        case invalidCharacters
        /// 超过 `ArpeggioInput.maxSteps` 个音。
        case tooLong
    }

    /// 输入里的每一个有意义的字符（分隔符不算）：原文和是否有效，界面据此把无效的标红。
    public struct Token: Equatable, Sendable {
        public let text: String
        public let isValid: Bool
    }

    public let tokens: [Token]
    /// 有效的步骤（顺序同输入）。出错时也尽量给出能识别的部分。
    public let steps: [ArpeggioStep]
    public let failure: Failure?

    public var isValid: Bool { failure == nil }

    /// 规范写法，例如 "R-3-2-1"、"5-3-2-3-1-3-2-3"。
    public var normalized: String { ArpeggioInput.normalized(steps) }
}

/// 自定义指法的输入规则。
///
/// - 每个数字是一个弦号（吉他 1–6，1 弦最细；尤克里里、贝斯 1–4）；字母 R（不分大小写）代表“当前和弦的根音弦”；
/// - **`-` 或 `0` 是空拍**：这一下不弹，但占一个音的时值（`5032` 是 5 弦、空拍、3 弦、2 弦；`5-3-2-` 是 5、空、3、空、2、空）；
/// - 空格、逗号、顿号等**只用来分隔**（不占拍），也可以连着写：`53231323`、`5 3 2 1`、`R 3 - 1` 都行；全角字符也认；
/// - 长度 1–32 个音（空拍也算一个），至少要有一个会响的音；超出弦数的数字、其他字符都算无效（标红）。
///
/// iPhone 的“智能标点”会把连着输入的 `--` 换成一个 `–`、`---` 换成 `—`：这里按原来输入的个数当成 2、3 个空拍，
/// 所以连续的空拍不会被吃掉。
///
/// **旧版本**里 `-` 是分隔符（保存的指法写成 `5-3-2-1`）；读取旧数据时会迁移（见 `CustomArpeggio` 的解码）。
public enum ArpeggioInput {
    public static let maxSteps = 32
    /// 每种乐器最多保存几个自定义指法。
    public static let maxSaved = 10

    private static let separators: Set<Character> = [" ", "\t", "\n", "_", ",", "，", "、", ";", "；", ".", "。", "·", "/", "|", "→", ">", "…", "‥"]

    /// 一个字符代表几个空拍：`-` 是 1 个；智能标点合并出来的 `–`（两个短横）是 2 个，`—`（三个）是 3 个。
    private static func restCount(_ ch: Character) -> Int? {
        switch ch {
        case "-", "‐", "‑", "−", "－": return 1
        case "–": return 2
        case "—": return 3
        default: return nil
        }
    }

    /// - Parameter stringCount: 当前乐器的弦数（吉他 6、尤克里里 4、贝斯 4 或 5）。
    public static func parse(_ text: String, stringCount: Int) -> ArpeggioParse {
        var tokens: [ArpeggioParse.Token] = []
        var steps: [ArpeggioStep] = []
        for ch in text where !separators.contains(ch) && !ch.isWhitespace {
            if let n = restCount(ch) {
                for _ in 0..<n { tokens.append(.init(text: "-", isValid: true)); steps.append(.rest) }
            } else if let n = digit(ch) {
                if n == 0 {
                    tokens.append(.init(text: "-", isValid: true)); steps.append(.rest)         // 0 也是空拍
                } else if n <= max(1, stringCount) {
                    tokens.append(.init(text: String(ch), isValid: true)); steps.append(.string(n))
                } else {
                    tokens.append(.init(text: String(ch), isValid: false))
                }
            } else if ch == "R" || ch == "r" || ch == "Ｒ" || ch == "ｒ" {
                tokens.append(.init(text: "R", isValid: true)); steps.append(.root)
            } else {
                tokens.append(.init(text: String(ch), isValid: false))
            }
        }
        let failure: ArpeggioParse.Failure?
        if tokens.contains(where: { !$0.isValid }) { failure = .invalidCharacters }
        else if steps.allSatisfy({ $0 == .rest }) { failure = .empty }                  // 空的，或者全是空拍
        else if tokens.count > maxSteps { failure = .tooLong }
        else { failure = nil }
        return ArpeggioParse(tokens: tokens, steps: steps, failure: failure)
    }

    /// ASCII 或全角数字 → 数值。
    private static func digit(_ ch: Character) -> Int? {
        if let d = ch.wholeNumberValue, ch.isNumber, String(ch).unicodeScalars.allSatisfy({ $0.isASCII || (0xFF10...0xFF19).contains($0.value) }) { return d }
        return nil
    }

    /// 规范写法：每步用空格隔开，空拍写 `-`，例如 `R 3 - 1`。（旧版本用短横隔开；现在短横是空拍。）
    public static func normalized(_ steps: [ArpeggioStep]) -> String {
        steps.map { step -> String in
            switch step {
            case .root: return "R"
            case .rest: return "-"
            case .string(let n): return String(n)
            }
        }.joined(separator: " ")
    }

    /// 旧版本保存的写法（`5-3-2-1`、`R-3-2-1`，短横是分隔符）→ 新写法（`5 3 2 1`、`R 3 2 1`）。
    /// 旧版本只存规范写法：每个字符是弦号或 R，用单个短横隔开，所以把短横去掉、逐字符重新用空格隔开即可。
    public static func migratedFromLegacy(_ text: String) -> String {
        let legacy = parseLegacy(text)
        return normalized(legacy)
    }

    private static func parseLegacy(_ text: String) -> [ArpeggioStep] {
        text.compactMap { ch -> ArpeggioStep? in
            if let n = digit(ch), n >= 1 { return .string(n) }
            if ch == "R" || ch == "r" { return .root }
            return nil                                                  // 短横、空格等分隔符
        }
    }
}

/// 用户保存的一个自定义指法。按乐器大类分别保存（见 `ChordLibraryModel`）。
///
/// **存储格式版本**：旧版本（没有 `v` 字段）的 `text` 是 `5-3-2-1`（短横分隔）；现在短横是空拍，规范写法是 `5 3 2 1`（空格分隔，
/// 空拍 `-`）。解码时发现没有 `v` 就迁移 `text`，编码时写 `v = 2`，所以保存过的旧指法含义不变、再次保存后就是新格式。
public struct CustomArpeggio: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// 名称；空串表示用数字串本身当名字。
    public var name: String
    /// 规范写法的数字串，例如 "R 3 - 1"。
    public var text: String

    public static let formatVersion = 2

    public init(id: String = UUID().uuidString, name: String = "", text: String) {
        self.id = id; self.name = name; self.text = text
    }

    private enum CodingKeys: String, CodingKey { case id, name, text, v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let raw = try c.decode(String.self, forKey: .text)
        let version = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        text = version >= Self.formatVersion ? raw : ArpeggioInput.migratedFromLegacy(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(text, forKey: .text)
        try c.encode(Self.formatVersion, forKey: .v)
    }

    /// 列表里显示的名字：有名字用名字，否则是数字串。
    public var displayName: String { name.isEmpty ? text : name }

    /// 转成可以演奏的指法。`stringCount` 只用来校验；存的数字超出时返回 nil。
    public func pattern(family: InstrumentFamily, stringCount: Int) -> ArpeggioPattern? {
        let parsed = ArpeggioInput.parse(text, stringCount: max(stringCount, 6))
        guard parsed.isValid else { return nil }
        return ArpeggioPattern(id: ArpeggioPattern.customPrefix + id, family: family, kind: .custom(parsed.steps),
                               digits: parsed.normalized, summary: name, englishSummary: name)
    }
}

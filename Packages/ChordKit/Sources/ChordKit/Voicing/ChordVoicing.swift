import Foundation
import TunerKit

/// 一个把位（指法）：每根弦按哪一品、用哪根手指，以及发出什么音。
///
/// 数组都按定弦里的**物理顺序**排（`Tuning.strings` 的顺序：吉他从 6 弦到 1 弦，
/// 尤克里里 G C E A）。指法图左边是第一根弦（左手模式下镜像）。
public struct ChordVoicing: Hashable, Codable, Sendable {
    /// 横按：食指（1 指）压住 `fromString`…`toString`（含）这几根弦的 `fret` 品。
    public struct Barre: Hashable, Codable, Sendable {
        public let fret: Int
        public let fromString: Int
        public let toString: Int
        public let finger: Int
        /// 只按 4 个以内的音、为了好按才用食指压住同一品的几根弦（比如尤克里里 Bm7 2222、吉他 Dm7 的 1 弦 2 弦）。
        /// 不影响“开放把位”的判定和排序。
        public let small: Bool

        public init(fret: Int, fromString: Int, toString: Int, finger: Int = 1, small: Bool = false) {
            self.fret = fret; self.fromString = fromString; self.toString = toString; self.finger = finger; self.small = small
        }

        private enum CodingKeys: String, CodingKey { case fret, fromString, toString, finger, small }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fret = try c.decode(Int.self, forKey: .fret)
            fromString = try c.decode(Int.self, forKey: .fromString)
            toString = try c.decode(Int.self, forKey: .toString)
            finger = try c.decode(Int.self, forKey: .finger)
            small = try c.decodeIfPresent(Bool.self, forKey: .small) ?? false      // 旧数据没有这个字段
        }
    }

    /// 每根弦按的品：-1 不弹，0 空弦，1… 品位。
    public let frets: [Int]
    /// 每根弦用的手指：1 食指 … 4 小指；0 表示空弦或不弹。横按覆盖的弦为横按的手指。
    public let fingers: [Int]
    public let barre: Barre?
    /// 每根弦发出的音；不弹的弦为 nil。
    public let pitches: [Pitch?]

    public init(frets: [Int], fingers: [Int], barre: Barre?, tuning: Tuning) {
        precondition(frets.count == tuning.strings.count && fingers.count == frets.count)
        self.frets = frets
        self.fingers = fingers
        self.barre = barre
        self.pitches = zip(tuning.strings, frets).map { $1 >= 0 ? $0.pitch.transposed(by: $1) : nil }
    }

    // MARK: 显示用

    public var stringCount: Int { frets.count }
    /// 每根弦发出的音名（升号写法），不弹的弦为空串。
    public var noteNames: [String] { pitches.map { $0.map { ChordRoot.name($0.pitchClass) } ?? "" } }

    /// 指法图第一行对应的品位：全部在 5 品以内时为 1（画琴枕），否则为最低的按弦品位。
    public var baseFret: Int { maxFret <= 5 ? 1 : minFret }
    /// 是否画琴枕（粗线）。
    public var showsNut: Bool { baseFret == 1 }

    // MARK: 统计

    public var mutedCount: Int { frets.filter { $0 < 0 }.count }
    public var soundingCount: Int { frets.count - mutedCount }
    public var openCount: Int { frets.filter { $0 == 0 }.count }
    /// 按下的最低品位（不含空弦）；没有按弦时为 0。
    public var minFret: Int { frets.filter { $0 > 0 }.min() ?? 0 }
    public var maxFret: Int { frets.max() ?? 0 }
    /// 手指跨度：最高按弦品与最低按弦品相隔的品数（同一品为 0）。
    public var span: Int { frets.contains { $0 > 0 } ? maxFret - minFret : 0 }
    /// 用到几根手指。
    public var fingerCount: Int { Set(fingers.filter { $0 > 0 }).count }
    /// “开放把位”：带空弦且最高不超过 4 品，不用横按。
    public var isOpenPosition: Bool { openCount > 0 && maxFret <= 4 && (barre == nil || barre!.small) }

    /// 发声的最低音（按音高）。
    public var lowestPitch: Pitch? { pitches.compactMap { $0 }.min() }

    /// 简写，例如 "x32010"；有 10 品以上时用 "-" 隔开，如 "x-8-10-10-9-8"。
    public var shorthand: String {
        let parts = frets.map { $0 < 0 ? "x" : String($0) }
        return frets.contains { $0 >= 10 } ? parts.joined(separator: "-") : parts.joined()
    }

    /// 发声的弦（物理序号）。
    public var soundingStrings: [Int] { frets.indices.filter { frets[$0] >= 0 } }

    /// 用在 VoiceOver 上的读法。
    public func spokenDescription(strings: [InstrumentString]) -> String {
        zip(strings, frets).map { s, f in
            f < 0 ? "\(s.number) 弦不弹" : (f == 0 ? "\(s.number) 弦空弦" : "\(s.number) 弦 \(f) 品")
        }.joined(separator: "，")
    }
}

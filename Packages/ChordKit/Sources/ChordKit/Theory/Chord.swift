import Foundation

/// 12 个根音（升号写法）。
public enum ChordRoot {
    public static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    public static let all = Array(0..<12)
    /// 0…11 → "C#" 等；越界会先折回。
    public static func name(_ pitchClass: Int) -> String { names[((pitchClass % 12) + 12) % 12] }
}

/// 一个和弦：根音 + 类型。
public struct Chord: Hashable, Codable, Sendable, Identifiable {
    /// 根音的音级，0…11，C = 0。
    public let root: Int
    public let type: ChordType

    public init(root: Int, type: ChordType) {
        self.root = ((root % 12) + 12) % 12
        self.type = type
    }

    /// 例如 `Chord("C#", .minor7)`；根音写 "C#" 或 "C♯" 或 "Db" 都行。
    public init?(_ rootName: String, _ type: ChordType) {
        guard let pc = Chord.pitchClass(of: rootName) else { return nil }
        self.init(root: pc, type: type)
    }

    public var id: String { "\(root)-\(type.id)" }

    public var rootName: String { ChordRoot.name(root) }
    /// 完整的和弦名，例如 "Cmaj7"、"F#m"、"G"。
    public var name: String { rootName + type.symbol }

    /// 组成音的音级（0…11），顺序与 `type.intervals` 一致。
    public var pitchClasses: [Int] { type.intervals.map { (root + $0) % 12 } }
    /// 组成音的音名，例如 ["C", "E", "G", "B"]。
    public var toneNames: [String] { pitchClasses.map(ChordRoot.name) }

    /// 音级 → 它在和弦里的级数序号（0 = 根音）。
    func degreeIndex(ofPitchClass pc: Int) -> Int? {
        pitchClasses.firstIndex(of: ((pc % 12) + 12) % 12)
    }

    static func pitchClass(of name: String) -> Int? {
        let chars = Array(name.trimmingCharacters(in: .whitespaces))
        guard let first = chars.first else { return nil }
        let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard var pc = base[Character(first.uppercased())] else { return nil }
        for c in chars.dropFirst() {
            switch c {
            case "#", "♯": pc += 1
            case "b", "♭": pc -= 1
            default: return nil
            }
        }
        return ((pc % 12) + 12) % 12
    }
}

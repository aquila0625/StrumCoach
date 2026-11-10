import ChordKit
import Foundation

/// 和弦进行里的一格：一个和弦，持续几小节。
struct ProgressionChord: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// 根音音级 0…11（C = 0）
    var root: Int
    var typeID: String
    /// 持续几小节（1 / 2 / 4）
    var bars: Int = 1

    static let barChoices = [1, 2, 4]

    init(root: Int, type: ChordType, bars: Int = 1) {
        self.root = root
        typeID = type.id
        self.bars = bars
    }

    var type: ChordType { ChordType.builtins.first { $0.id == typeID } ?? .major }
    var chord: Chord { Chord(root: root, type: type) }

    /// 同一个和弦（不比较 id 和小节数）
    func sameChord(as other: ProgressionChord) -> Bool { root == other.root && typeID == other.typeID }
}

/// 一个和弦进行：数量不限，可以命名保存。
struct ChordProgression: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var chords: [ProgressionChord]

    var totalBars: Int { chords.reduce(0) { $0 + $1.bars } }

    /// 例如 "C–G–Am–F"
    func label(_ name: (Chord) -> String) -> String { chords.map { name($0.chord) }.joined(separator: "–") }

    // MARK: 编辑

    mutating func append(_ chord: ProgressionChord) { chords.append(chord) }

    mutating func update(_ chord: ProgressionChord) {
        guard let i = chords.firstIndex(where: { $0.id == chord.id }) else { return }
        chords[i] = chord
    }

    /// 把 `id` 移到 `target` 的位置（拖动排序）
    mutating func move(_ id: UUID, to target: UUID) {
        guard id != target, let from = chords.firstIndex(where: { $0.id == id }),
              let to = chords.firstIndex(where: { $0.id == target }) else { return }
        let item = chords.remove(at: from)
        chords.insert(item, at: to)
    }

    /// 删掉一个；至少留一个和弦
    mutating func delete(_ id: UUID) {
        guard chords.count > 1 else { return }
        chords.removeAll { $0.id == id }
    }

    /// 复制一个，放在它后面（新的 id）
    @discardableResult
    mutating func duplicate(_ id: UUID) -> UUID? {
        guard let i = chords.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = chords[i]
        copy.id = UUID()
        chords.insert(copy, at: i + 1)
        return copy.id
    }

    // MARK: 常用进行

    private static func p(_ name: String, _ items: [(String, ChordType, Int)]) -> ChordProgression {
        ChordProgression(name: name, chords: items.map { ProgressionChord(root: ChordRoot.names.firstIndex(of: $0.0) ?? 0, type: $0.1, bars: $0.2) })
    }

    static var presets: [ChordProgression] {
        [
            p("C–G–Am–F", [("C", .major, 1), ("G", .major, 1), ("A", .minor, 1), ("F", .major, 1)]),
            p("G–D–Em–C", [("G", .major, 1), ("D", .major, 1), ("E", .minor, 1), ("C", .major, 1)]),
            p("Am–F–C–G", [("A", .minor, 1), ("F", .major, 1), ("C", .major, 1), ("G", .major, 1)]),
            p("D–A–Bm–G", [("D", .major, 1), ("A", .major, 1), ("B", .minor, 1), ("G", .major, 1)]),
            p("C–Am–F–G", [("C", .major, 1), ("A", .minor, 1), ("F", .major, 1), ("G", .major, 1)]),
            // 12 小节布鲁斯（A）：A7 ×4 | D7 ×2 | A7 ×2 | E7 | D7 | A7 | E7
            p(String(localized: "12 小节布鲁斯（A）", bundle: .appLanguage, locale: .appLanguage),
              [("A", .dominant7, 4), ("D", .dominant7, 2), ("A", .dominant7, 2), ("E", .dominant7, 1), ("D", .dominant7, 1),
               ("A", .dominant7, 1), ("E", .dominant7, 1)]),
        ]
    }
}

/// 进行展开成一小节一小节：第几小节弹进行里的第几个和弦。
struct ProgressionPlan: Equatable, Sendable {
    /// 每小节对应进行里第几个和弦
    let barChord: [Int]
    /// 是否被截断（示范最多 8 小节）
    let truncated: Bool

    var bars: Int { barChord.count }

    /// - Parameters:
    ///   - loops: 走几遍
    ///   - minBars: 不够就循环补到这么多小节（跟练至少 4 小节）
    ///   - maxBars: 最多这么多小节（示范最多 8 小节）
    init(_ progression: ChordProgression, loops: Int = 1, minBars: Int = 0, maxBars: Int? = nil) {
        var once: [Int] = []
        for (i, c) in progression.chords.enumerated() { once += Array(repeating: i, count: max(1, c.bars)) }
        if once.isEmpty { once = [0] }
        var bars = Array((0..<max(1, loops)).flatMap { _ in once })
        // 不够就整遍循环补足（不截断半个进行）
        while bars.count < minBars { bars += once }
        if let maxBars, bars.count > maxBars {
            barChord = Array(bars.prefix(maxBars))
            truncated = true
        } else {
            barChord = bars
            truncated = false
        }
    }

    private init(barChord: [Int], truncated: Bool) {
        self.barChord = barChord
        self.truncated = truncated
    }

    /// 连着走 n 遍（多遍跟练的总成绩按它分段）
    func repeated(_ n: Int) -> ProgressionPlan {
        ProgressionPlan(barChord: Array((0..<max(1, n)).flatMap { _ in barChord }), truncated: truncated)
    }

    func chordIndex(atBar bar: Int) -> Int { barChord[min(max(bar, 0), barChord.count - 1)] }

    /// 换和弦的小节（这一小节的和弦和上一小节不同；第一小节不算）
    var changeBars: [Int] {
        (1..<max(1, barChord.count)).filter { barChord[$0] != barChord[$0 - 1] }
    }
}

/// 存在本机的和弦进行：当前用的一个，加上用户命名保存的（数量不限）。
struct ProgressionStore {
    private let defaults: UserDefaults
    private static let currentKey = "strum.progression"
    private static let savedKey = "strum.savedProgressions"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func loadCurrent() -> ChordProgression? {
        defaults.data(forKey: Self.currentKey).flatMap { try? JSONDecoder().decode(ChordProgression.self, from: $0) }
    }

    func saveCurrent(_ p: ChordProgression) {
        defaults.set(try? JSONEncoder().encode(p), forKey: Self.currentKey)
    }

    func loadSaved() -> [ChordProgression] {
        defaults.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode([ChordProgression].self, from: $0) } ?? []
    }

    func storeSaved(_ list: [ChordProgression]) {
        defaults.set(try? JSONEncoder().encode(list), forKey: Self.savedKey)
    }
}

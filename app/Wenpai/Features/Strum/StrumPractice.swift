import ChordKit
import Foundation
import TunerKit

/// 一次跟练：可以指定练几遍（一遍 = 整个和弦进行走一遍），也可以不限遍数一直练到用户点“结束”。
/// 每遍单独打分；结束（或中途退出）时只算已经练完的遍。
struct PracticeRun: Equatable {
    /// 要练几遍；nil = 一直练
    let target: Int?
    /// 每遍几小节
    let passBars: Int
    /// 已经练完的每一遍的成绩（按顺序）
    private(set) var passes: [StrumScore] = []

    static let targetRange = 1...99

    init(target: Int?, passBars: Int) {
        self.target = target.map { min(max($0, Self.targetRange.lowerBound), Self.targetRange.upperBound) }
        self.passBars = max(1, passBars)
    }

    mutating func add(_ score: StrumScore) { passes.append(score) }

    /// 练够指定的遍数就结束；一直练时永远不会自己结束
    var isComplete: Bool {
        guard let target else { return false }
        return passes.count >= target
    }

    /// 还要不要再排下一遍（已经排好的遍数 `scheduled`）
    func needsPass(after scheduled: Int) -> Bool {
        guard let target else { return true }
        return scheduled < target
    }

    var passScores: [Int] { passes.map(\.score) }

    /// 各遍的平均分（四舍五入）；一遍都没练完是 nil
    var averageScore: Int? {
        passes.isEmpty ? nil : Int((Double(passScores.reduce(0, +)) / Double(passes.count)).rounded())
    }

    /// 最好的一遍：第几遍（从 1 起）和分数
    var best: (pass: Int, score: Int)? {
        guard let i = passScores.indices.max(by: { passScores[$0] < passScores[$1] }) else { return nil }
        return (i + 1, passScores[i])
    }

    /// 把所有遍拼成一份成绩（小节号按遍往后接），用来算总的准 / 偏 / 漏、偏差和建议
    var combined: StrumScore? {
        guard !passes.isEmpty else { return nil }
        var hits: [StrumScore.Hit] = []
        var extras: [Double] = []
        for (k, p) in passes.enumerated() {
            hits += p.hits.map { var h = $0; h.bar += k * passBars; return h }
            extras += p.extras
        }
        return StrumScore(hits: hits, extras: extras)
    }
}

/// 节奏型的收藏、已掌握标记：按乐器分别存在本机。
struct RhythmMarks: Codable, Equatable {
    struct Family: Codable, Equatable {
        var favorites: Set<String> = []
        var mastered: Set<String> = []
        /// 提示过“标记为已掌握？”但用户选了不标的，不再提示
        var declined: Set<String> = []
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, favorites, learning
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "全部", bundle: .appLanguage, locale: .appLanguage)
            case .favorites: return String(localized: "收藏", bundle: .appLanguage, locale: .appLanguage)
            case .learning: return String(localized: "未掌握", bundle: .appLanguage, locale: .appLanguage)
            }
        }
    }

    private(set) var families: [String: Family] = [:]

    func isFavorite(_ id: String, family: InstrumentFamily) -> Bool { families[family.rawValue]?.favorites.contains(id) == true }
    func isMastered(_ id: String, family: InstrumentFamily) -> Bool { families[family.rawValue]?.mastered.contains(id) == true }

    mutating func setFavorite(_ on: Bool, _ id: String, family: InstrumentFamily) {
        update(family) { if on { $0.favorites.insert(id) } else { $0.favorites.remove(id) } }
    }

    mutating func setMastered(_ on: Bool, _ id: String, family: InstrumentFamily) {
        update(family) { if on { $0.mastered.insert(id) } else { $0.mastered.remove(id) } }
    }

    mutating func decline(_ id: String, family: InstrumentFamily) { update(family) { $0.declined.insert(id) } }

    private mutating func update(_ family: InstrumentFamily, _ body: (inout Family) -> Void) {
        var f = families[family.rawValue] ?? Family()
        body(&f)
        families[family.rawValue] = f
    }

    /// 排序：收藏的在前，然后没掌握的，已掌握的放最后；同一组里保持原来的顺序（预设在前、自定义在后）
    func sorted(_ rhythms: [StrumRhythm], family: InstrumentFamily) -> [StrumRhythm] {
        func rank(_ r: StrumRhythm) -> Int {
            if isFavorite(r.id, family: family) { return 0 }
            return isMastered(r.id, family: family) ? 2 : 1
        }
        return rhythms.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    func filtered(_ rhythms: [StrumRhythm], by filter: Filter, family: InstrumentFamily) -> [StrumRhythm] {
        let list = sorted(rhythms, family: family)
        switch filter {
        case .all: return list
        case .favorites: return list.filter { isFavorite($0.id, family: family) }
        case .learning: return list.filter { !isMastered($0.id, family: family) }
        }
    }

    /// 连续 3 次（这件乐器上这个节奏型最近的 3 次跟练）都 ≥ 90 分，而且还没标、也没拒绝过，就建议标记为已掌握
    static let masteryStreak = 3
    static let masteryScore = 90

    func suggestsMastered(_ id: String, family: InstrumentFamily, history: [StrumHistory.Entry]) -> Bool {
        guard !isMastered(id, family: family), families[family.rawValue]?.declined.contains(id) != true else { return false }
        let mine = history.filter { $0.patternID == id && ($0.family == nil || $0.family == family.rawValue) }
        let recent = mine.suffix(Self.masteryStreak)
        return recent.count == Self.masteryStreak && recent.allSatisfy { $0.score >= Self.masteryScore }
    }
}

/// 收藏、已掌握标记的本机存储
struct RhythmMarksStore {
    private let defaults: UserDefaults
    private static let key = "strum.rhythmMarks"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func load() -> RhythmMarks {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(RhythmMarks.self, from: $0) } ?? RhythmMarks()
    }

    func save(_ marks: RhythmMarks) { defaults.set(try? JSONEncoder().encode(marks), forKey: Self.key) }
}

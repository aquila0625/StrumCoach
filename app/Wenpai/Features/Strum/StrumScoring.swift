import ChordKit
import Foundation

/// 跟练评分。
///
/// - 每个应该扫的格，和检测到的起音一对一配对（按时间差从小到大配，每个起音只用一次）；
/// - 时间差在 ±60 毫秒内算“准”，±120 毫秒内算“偏”，配不上的算“漏”；
/// - 收音时间内没配上任何格的起音算“多扫”；
/// - 总分 = （准 × 1 + 偏 × 0.5 − 多扫 × 0.5）÷ 应扫次数 × 100，限制在 0…100；
/// - 第一版只看时间，不判断实际是上扫还是下扫。
struct StrumScore: Codable, Equatable, Sendable {
    enum Grade: String, Codable, Sendable { case good, off, missed }

    struct Hit: Codable, Equatable, Sendable {
        var bar: Int
        var step: Int
        var stroke: StrumCell
        var grade: Grade
        /// 实际 − 应该（秒）；正数 = 偏慢。漏掉的是 nil
        var offset: Double?
    }

    static let goodWindow = 0.060
    static let offWindow = 0.120
    static let extraPenalty = 0.5

    var hits: [Hit]
    /// 多扫的起音时间（相对第一格，秒）
    var extras: [Double]

    var expected: Int { hits.count }
    var good: Int { hits.filter { $0.grade == .good }.count }
    var off: Int { hits.filter { $0.grade == .off }.count }
    var missed: Int { hits.filter { $0.grade == .missed }.count }

    var score: Int {
        guard expected > 0 else { return 0 }
        let raw = (Double(good) + 0.5 * Double(off) - Self.extraPenalty * Double(extras.count)) / Double(expected) * 100
        return Int(min(100, max(0, raw)).rounded())
    }

    private var offsets: [Double] { hits.compactMap(\.offset) }

    /// 平均偏差（毫秒）：正数偏慢、负数偏快；没有配上的就是 nil
    var meanOffsetMs: Double? {
        offsets.isEmpty ? nil : offsets.reduce(0, +) / Double(offsets.count) * 1000
    }

    /// 稳定度：偏差的标准差（毫秒），越小越稳
    var spreadMs: Double? {
        guard offsets.count >= 2 else { return nil }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        let variance = offsets.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(offsets.count)
        return variance.squareRoot() * 1000
    }

    /// 应该是某种扫法（下扫 / 上扫）的格的平均偏差（毫秒）。这是按节奏型里的位置分组，不是识别出来的方向。
    func meanOffsetMs(for stroke: StrumCell) -> (ms: Double, count: Int)? { meanOffsetMs(forAny: [stroke]) }

    /// 同上，几种记号合在一起算（比如全扫 D 和半扫 d 都是下扫）
    func meanOffsetMs(forAny strokes: Set<StrumCell>) -> (ms: Double, count: Int)? {
        let list = hits.filter { strokes.contains($0.stroke) }.compactMap(\.offset)
        return list.isEmpty ? nil : (list.reduce(0, +) / Double(list.count) * 1000, list.count)
    }

    /// 给 `timeline` 打分；`onsets` 是检测到的起音时间（和 timeline 同一时钟）。
    /// 只算收音窗口（第一格前 `offWindow` 到最后一小节结束）里的起音。
    ///
    /// - Parameter guards: 连续练很多遍时，相邻两遍挨着的那一下（上一遍最后一下、下一遍第一下）的时间。
    ///   它们也参与配对：落在这一遍窗口里、其实属于邻居的起音被它们“认领”，不算这一遍的多扫；它们本身不计分。
    static func grade(_ timeline: StrumTimeline, onsets: [Double], guards: [Double] = []) -> StrumScore {
        let strokes = timeline.strokes
        let window = (timeline.start - offWindow)...(timeline.end)
        let candidates = onsets.filter { window.contains($0) }.sorted()
        // 所有在 ±120 ms 内的（格, 起音）组合，按时间差从小到大一对一配对；护栏的序号接在格子后面
        let times = strokes.map(\.time) + guards
        var pairs: [(stroke: Int, onset: Int, dt: Double)] = []
        for (i, time) in times.enumerated() {
            for (j, t) in candidates.enumerated() where abs(t - time) <= offWindow {
                pairs.append((i, j, t - time))
            }
        }
        pairs.sort { abs($0.dt) < abs($1.dt) }
        var strokeMatch = [Int: Double]()
        var usedOnsets = Set<Int>()
        for p in pairs where strokeMatch[p.stroke] == nil && !usedOnsets.contains(p.onset) {
            strokeMatch[p.stroke] = p.dt
            usedOnsets.insert(p.onset)
        }
        let hits = strokes.enumerated().map { i, s -> Hit in
            guard let dt = strokeMatch[i] else { return Hit(bar: s.bar, step: s.step, stroke: s.stroke, grade: .missed, offset: nil) }
            return Hit(bar: s.bar, step: s.step, stroke: s.stroke, grade: abs(dt) <= goodWindow ? .good : .off, offset: dt)
        }
        let extras = candidates.enumerated().filter { !usedOnsets.contains($0.offset) }.map { $0.element - timeline.start }
        return StrumScore(hits: hits, extras: extras)
    }

    /// 一句按数据给出的建议（只说时间上的事；方向只用“节奏型里该上扫的格”这种说法）。
    var advice: String {
        func ms(_ v: Double) -> Int { Int(abs(v).rounded()) }
        if expected == 0 { return "" }
        if Double(missed) / Double(expected) > 0.4 {
            return String(localized: "很多下没有收到声音：把手机放近一点，扫得干脆一些，或者先在安静的地方练。", bundle: .appLanguage, locale: .appLanguage)
        }
        if let up = meanOffsetMs(for: .up), let down = meanOffsetMs(forAny: [.down, .downTreble]), up.count >= 3, down.count >= 3, up.ms - down.ms > 25 {
            return String(localized: "该上扫的那几下平均比下扫慢 \(ms(up.ms - down.ms)) 毫秒，回扫时手腕放松、别停顿。", bundle: .appLanguage, locale: .appLanguage)
        }
        if let up = meanOffsetMs(for: .up), let down = meanOffsetMs(forAny: [.down, .downTreble]), up.count >= 3, down.count >= 3, down.ms - up.ms > 25 {
            return String(localized: "该上扫的那几下平均比下扫快 \(ms(down.ms - up.ms)) 毫秒，上扫别急，等到“&”再扫。", bundle: .appLanguage, locale: .appLanguage)
        }
        if let mean = meanOffsetMs, mean > 30 {
            return String(localized: "整体平均慢了 \(ms(mean)) 毫秒，试着提前一点点下手。", bundle: .appLanguage, locale: .appLanguage)
        }
        if let mean = meanOffsetMs, mean < -30 {
            return String(localized: "整体平均快了 \(ms(mean)) 毫秒，有点抢拍，跟着高亮再稳一点。", bundle: .appLanguage, locale: .appLanguage)
        }
        if extras.count >= 2 {
            return String(localized: "多扫了 \(extras.count) 下，注意空拍时手要继续摆动但不碰弦。", bundle: .appLanguage, locale: .appLanguage)
        }
        if let spread = spreadMs, spread > 35 {
            return String(localized: "快慢不太稳（偏差约 ±\(ms(spread)) 毫秒），先把速度调慢 10 BPM 练熟。", bundle: .appLanguage, locale: .appLanguage)
        }
        if score >= 90 {
            return String(localized: "很稳！可以把速度加 5 BPM 再试试。", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(localized: "不错，继续保持手腕匀速摆动，空拍也别停。", bundle: .appLanguage, locale: .appLanguage)
    }
}

/// 和弦进行的分段成绩：每个和弦（进行里的位置）各自的得分，以及“换和弦后第一下扫弦”的偏差。
struct ProgressionReport: Codable, Equatable, Sendable {
    struct Segment: Codable, Equatable, Sendable {
        /// 进行里第几个和弦
        var index: Int
        var name: String
        var score: Int
        var expected: Int
    }

    struct Change: Codable, Equatable, Sendable {
        /// 换到进行里第几个和弦
        var index: Int
        var name: String
        /// 换过去后第一下的平均偏差（毫秒，正数 = 慢）；全都漏了是 nil
        var meanMs: Double?
        /// 统计到的次数（含漏掉的）
        var count: Int
        var missed: Int
    }

    var segments: [Segment]
    var changes: [Change]
    /// 所有换和弦后第一下的平均偏差 / 其余各下的平均偏差（毫秒）
    var changeMeanMs: Double?
    var otherMeanMs: Double?

    /// - Parameter names: 进行里每个和弦的名字（按当前的音名写法）
    static func make(score: StrumScore, timeline: StrumTimeline, plan: ProgressionPlan, names: [String]) -> ProgressionReport {
        // 每个和弦一段：只算属于它的小节里的格；多扫按它落在哪一小节算给那个和弦
        let segments = names.indices.map { i -> Segment in
            let hits = score.hits.filter { plan.chordIndex(atBar: $0.bar) == i }
            let extras = score.extras.filter { plan.chordIndex(atBar: Int(max(0, $0) / timeline.barDuration)) == i }
            let part = StrumScore(hits: hits, extras: extras)
            return Segment(index: i, name: names[i], score: part.score, expected: part.expected)
        }.filter { $0.expected > 0 }

        // 换和弦处：这一小节第一个该扫的格
        var firstAtChange: [(target: Int, hit: StrumScore.Hit)] = []
        let changeBars = Set(plan.changeBars)
        for bar in plan.changeBars {
            if let first = score.hits.filter({ $0.bar == bar }).min(by: { $0.step < $1.step }) {
                firstAtChange.append((plan.chordIndex(atBar: bar), first))
            }
        }
        var changes: [Change] = []
        for target in Set(firstAtChange.map(\.target)).sorted() {
            let list = firstAtChange.filter { $0.target == target }.map(\.hit)
            let offsets = list.compactMap(\.offset)
            changes.append(Change(index: target, name: names[target],
                                  meanMs: offsets.isEmpty ? nil : offsets.reduce(0, +) / Double(offsets.count) * 1000,
                                  count: list.count, missed: list.filter { $0.grade == .missed }.count))
        }
        let changeOffsets = firstAtChange.compactMap(\.hit.offset)
        let firstKeys = Set(firstAtChange.map { "\($0.hit.bar)-\($0.hit.step)" })
        let otherOffsets = score.hits.filter { !(changeBars.contains($0.bar) && firstKeys.contains("\($0.bar)-\($0.step)")) }.compactMap(\.offset)
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) * 1000 }
        return ProgressionReport(segments: segments, changes: changes, changeMeanMs: mean(changeOffsets), otherMeanMs: mean(otherOffsets))
    }

    /// 换和弦处的建议；没什么问题就是 nil
    var advice: String? {
        func ms(_ v: Double) -> Int { Int(abs(v).rounded()) }
        // 最慢的那个“换到 X”
        if let worst = changes.filter({ ($0.meanMs ?? 0) > 40 }).max(by: { ($0.meanMs ?? 0) < ($1.meanMs ?? 0) }), let late = worst.meanMs {
            return String(localized: "换到 \(worst.name) 时普遍晚了 \(ms(late)) 毫秒，可以提前准备按法。", bundle: .appLanguage, locale: .appLanguage)
        }
        let atChanges = changes.reduce(0) { $0 + $1.count }
        let missedAtChanges = changes.reduce(0) { $0 + $1.missed }
        if atChanges >= 2, Double(missedAtChanges) / Double(atChanges) >= 0.5 {
            return String(localized: "换和弦后的第一下常常没扫到，换把时右手别停，先扫空弦也可以。", bundle: .appLanguage, locale: .appLanguage)
        }
        if let c = changeMeanMs, let o = otherMeanMs, c - o > 30 {
            return String(localized: "换和弦后的第一下平均比其他时候晚 \(ms(c - o)) 毫秒，在上一小节最后一拍就开始换把。", bundle: .appLanguage, locale: .appLanguage)
        }
        return nil
    }
}

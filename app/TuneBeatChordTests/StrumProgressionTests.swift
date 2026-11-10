import ChordKit
import XCTest
@testable import TuneBeatChord

/// 和弦进行：编辑、保存读取、展开成时间轴、换和弦处的统计。
final class StrumProgressionTests: XCTestCase {
    private func prog(_ items: [(Int, ChordType, Int)]) -> ChordProgression {
        ChordProgression(name: "", chords: items.map { ProgressionChord(root: $0.0, type: $0.1, bars: $0.2) })
    }

    // MARK: 编辑

    func testEditingOperations() {
        var p = prog([(0, .major, 1), (7, .major, 1), (9, .minor, 1), (5, .major, 1)])   // C G Am F
        let ids = p.chords.map(\.id)
        // 拖动排序：F 拖到 G 的位置 → C F G Am
        p.move(ids[3], to: ids[1])
        XCTAssertEqual(p.chords.map(\.root), [0, 5, 7, 9])
        // 往后拖：C 拖到 Am 的位置 → F G Am C
        p.move(ids[0], to: ids[2])
        XCTAssertEqual(p.chords.map(\.root), [5, 7, 9, 0])
        // 复制：放在后面，新的 id
        let copy = p.duplicate(ids[1])!
        XCTAssertEqual(p.chords.map(\.root), [5, 7, 7, 9, 0])
        XCTAssertNotEqual(copy, ids[1])
        // 修改
        var g = p.chords[2]; g.bars = 4; g.typeID = ChordType.dominant7.id
        p.update(g)
        XCTAssertEqual(p.chords[2].bars, 4)
        XCTAssertEqual(p.chords[2].type, .dominant7)
        XCTAssertEqual(p.totalBars, 8)
        // 删除；最后一个删不掉
        p.delete(copy)
        XCTAssertEqual(p.chords.count, 4)
        for c in p.chords.dropFirst() { p.delete(c.id) }
        XCTAssertEqual(p.chords.count, 1)
        p.delete(p.chords[0].id)
        XCTAssertEqual(p.chords.count, 1, "至少留一个和弦")
        // 添加不限数量
        for i in 0..<40 { p.append(ProgressionChord(root: i % 12, type: .major)) }
        XCTAssertEqual(p.chords.count, 41)
    }

    func testPresets() {
        let presets = ChordProgression.presets
        XCTAssertEqual(presets.count, 6)
        XCTAssertEqual(presets[0].label { $0.name }, "C–G–Am–F")
        XCTAssertEqual(presets[3].label { $0.name }, "D–A–Bm–G")
        let blues = presets[5]
        XCTAssertEqual(blues.totalBars, 12)
        XCTAssertEqual(ProgressionPlan(blues).barChord.map { blues.chords[$0].chord.name },
                       ["A7", "A7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"])
    }

    // MARK: 保存读取

    @MainActor
    func testSaveAndLoadProgressions() {
        let suite = "StrumProgressionTests"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        let t = StrumTrainer(bpm: 80, defaults: d)
        XCTAssertEqual(t.progression.chords.count, 1, "第一次用：一个 C")
        t.apply(ChordProgression.presets[1])
        t.progression.chords[0].bars = 2
        t.saveProgression(named: "我的 1")
        t.apply(ChordProgression.presets[0])
        t.saveProgression(named: "我的 2")
        t.saveProgression(named: "我的 1")   // 同名覆盖
        // 重新打开：当前进行和保存的都在
        let again = StrumTrainer(bpm: 80, defaults: d)
        XCTAssertEqual(again.progression.label { $0.name }, "C–G–Am–F")
        XCTAssertEqual(again.savedProgressions.map(\.name), ["我的 2", "我的 1"])
        XCTAssertEqual(again.savedProgressions[1].label { $0.name }, "C–G–Am–F")
        // 套用保存的进行是复制一份：再改不影响保存的
        again.apply(again.savedProgressions[0])
        again.progression.delete(again.progression.chords[0].id)
        XCTAssertEqual(again.savedProgressions[0].chords.count, 4)
        again.deleteSaved(again.savedProgressions[0].id)
        XCTAssertEqual(StrumTrainer(bpm: 80, defaults: d).savedProgressions.map(\.name), ["我的 1"])
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @MainActor
    func testOldSingleChordSettingBecomesFirstChord() {
        let suite = "StrumProgressionMigration"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        d.set(7, forKey: "strum.root")
        d.set(ChordType.minor.id, forKey: "strum.type")
        XCTAssertEqual(StrumTrainer(bpm: 80, defaults: d).progression.label { $0.name }, "Gm")
        UserDefaults().removePersistentDomain(forName: suite)
    }

    // MARK: 时间轴

    func testPlanWithDifferentBarCounts() {
        let p = prog([(0, .major, 2), (7, .major, 1), (5, .major, 4)])   // C×2 G×1 F×4 = 7 小节
        let once = ProgressionPlan(p)
        XCTAssertEqual(once.barChord, [0, 0, 1, 2, 2, 2, 2])
        XCTAssertEqual(once.changeBars, [2, 3])
        XCTAssertFalse(once.truncated)
        // 跟练循环 2 遍：14 小节，第二遍开头 F → C 也算换和弦
        let twice = ProgressionPlan(p, loops: 2, minBars: 4)
        XCTAssertEqual(twice.bars, 14)
        XCTAssertEqual(twice.changeBars, [2, 3, 7, 9, 10])
        // 示范最多 8 小节
        let demo = ProgressionPlan(ProgressionPlan_long, maxBars: 8)
        XCTAssertEqual(demo.bars, 8)
        XCTAssertTrue(demo.truncated)
        // 太短：一个和弦 1 小节 → 循环补到 4 小节
        XCTAssertEqual(ProgressionPlan(prog([(0, .major, 1)]), minBars: 4).barChord, [0, 0, 0, 0])
        // 3 小节的进行补足时整遍循环：6 小节
        XCTAssertEqual(ProgressionPlan(prog([(0, .major, 1), (7, .major, 2)]), minBars: 4).barChord, [0, 1, 1, 0, 1, 1])
    }

    private var ProgressionPlan_long: ChordProgression { ChordProgression.presets[5] }

    /// 时间轴：每小节的扫弦按小节号对应到和弦
    func testTimelineStrokesMapToChords() {
        let p = prog([(0, .major, 2), (7, .major, 1)])
        let plan = ProgressionPlan(p, minBars: 4)   // C C G C C G
        let tl = StrumTimeline(pattern: .preset(id: "quarters")!, bpm: 120, start: 0, bars: plan.bars)
        let byChord = Dictionary(grouping: tl.strokes) { plan.chordIndex(atBar: $0.bar) }.mapValues(\.count)
        XCTAssertEqual(byChord[0], 16)
        XCTAssertEqual(byChord[1], 8)
        XCTAssertEqual(tl.strokes.first { $0.bar == 2 }?.time ?? 0, 4.0, accuracy: 1e-9, "第 3 小节（G）从 4 秒开始")
    }

    // MARK: 换和弦处

    /// 换到 F 时每次都晚 70 ms，其余都准：报告找出 F，分段成绩 F 最低，建议点名 F。
    func testChangeOffsetsPointAtTheSlowChord() {
        let p = prog([(0, .major, 1), (7, .major, 1), (9, .minor, 1), (5, .major, 1)])
        let names = ["C", "G", "Am", "F"]
        let plan = ProgressionPlan(p, loops: 2)
        let tl = StrumTimeline(pattern: .preset(id: "folk1")!, bpm: 90, start: 0, bars: plan.bars)
        let onsets = tl.strokes.map { s -> Double in
            let toF = plan.changeBars.contains(s.bar) && s.step == 0 && plan.chordIndex(atBar: s.bar) == 3
            return s.time + (toF ? 0.07 : 0)
        }
        let score = StrumScore.grade(tl, onsets: onsets)
        let report = ProgressionReport.make(score: score, timeline: tl, plan: plan, names: names)
        XCTAssertEqual(report.segments.map(\.name), names)
        XCTAssertEqual(report.segments.min { $0.score < $1.score }?.name, "F")
        let f = report.changes.first { $0.name == "F" }!
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f.meanMs!, 70, accuracy: 1e-6)
        XCTAssertEqual(report.changes.first { $0.name == "G" }!.meanMs!, 0, accuracy: 1e-6)
        // 换和弦的点：G、Am、F 各两次，第二遍开头的 C 一次
        XCTAssertEqual(report.changes.map(\.count).reduce(0, +), 7)
        XCTAssertTrue(report.advice?.contains("F") == true, report.advice ?? "")
        XCTAssertTrue(report.advice?.contains("70") == true)
    }

    func testChangeAdviceWhenFirstStrokesAreMissed() {
        let p = prog([(0, .major, 1), (7, .major, 1)])
        let plan = ProgressionPlan(p, loops: 2)
        let tl = StrumTimeline(pattern: .preset(id: "quarters")!, bpm: 100, start: 0, bars: plan.bars)
        let onsets = tl.strokes.filter { !(plan.changeBars.contains($0.bar) && $0.step == 0) }.map(\.time)
        let report = ProgressionReport.make(score: StrumScore.grade(tl, onsets: onsets), timeline: tl, plan: plan, names: ["C", "G"])
        XCTAssertEqual(report.changes.reduce(0) { $0 + $1.missed }, 3)
        XCTAssertNotNil(report.advice)
    }

    func testNoChangeAdviceWhenEverythingIsOnTime() {
        let p = prog([(0, .major, 1), (7, .major, 1)])
        let plan = ProgressionPlan(p, loops: 2)
        let tl = StrumTimeline(pattern: .preset(id: "folk2")!, bpm: 100, start: 0, bars: plan.bars)
        let report = ProgressionReport.make(score: StrumScore.grade(tl, onsets: tl.strokes.map(\.time)), timeline: tl, plan: plan, names: ["C", "G"])
        XCTAssertNil(report.advice)
        XCTAssertEqual(report.segments.map(\.score), [100, 100])
    }
}

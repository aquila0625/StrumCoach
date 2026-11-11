import ChordKit
import XCTest
@testable import StrumCoach

/// 扫弦跟练的遍数、逐遍打分、离开页面停止，以及节奏型的收藏 / 已掌握。
final class StrumPracticeTests: XCTestCase {
    private func score(_ good: Int, missed: Int = 0) -> StrumScore {
        let hits = (0..<good).map { StrumScore.Hit(bar: 0, step: $0, stroke: .down, grade: .good, offset: 0.01) }
            + (0..<missed).map { StrumScore.Hit(bar: 0, step: good + $0, stroke: .down, grade: .missed, offset: nil) }
        return StrumScore(hits: hits, extras: [])
    }

    // MARK: 遍数

    func testEndlessRunNeverCompletesByItself() {
        var run = PracticeRun(target: nil, passBars: 4)
        for _ in 0..<50 { run.add(score(8)) }
        XCTAssertFalse(run.isComplete, "留空 = 一直练，只有点“结束”才停")
        XCTAssertTrue(run.needsPass(after: 50))
    }

    func testTargetRunEndsAfterThatManyPasses() {
        var run = PracticeRun(target: 3, passBars: 4)
        XCTAssertTrue(run.needsPass(after: 2))
        XCTAssertFalse(run.needsPass(after: 3), "第 3 遍排好后不再排下一遍")
        run.add(score(8)); run.add(score(6, missed: 2))
        XCTAssertFalse(run.isComplete)
        run.add(score(8))
        XCTAssertTrue(run.isComplete)
        XCTAssertEqual(run.passScores, [100, 75, 100])
        XCTAssertEqual(run.averageScore, 92)
        XCTAssertEqual(run.best?.pass, 1, "同分取最早的一遍")
        XCTAssertEqual(PracticeRun(target: 150, passBars: 4).target, 99)
        XCTAssertEqual(PracticeRun(target: 0, passBars: 4).target, 1)
    }

    func testCombinedScoreShiftsBarsPerPass() throws {
        var run = PracticeRun(target: nil, passBars: 4)
        run.add(score(2)); run.add(score(2))
        let combined = try XCTUnwrap(run.combined)
        XCTAssertEqual(combined.hits.map(\.bar), [0, 0, 4, 4])
        XCTAssertNil(PracticeRun(target: nil, passBars: 4).combined)
        XCTAssertEqual(ProgressionPlan(ChordProgression.presets[0]).repeated(2).bars, 8)
    }

    /// 连着练：下一遍第一下扫早了，落在这一遍的窗口里——由护栏认领，不算这一遍多扫
    func testGuardsKeepNeighbourPassOnsetsOutOfExtras() {
        let tl = StrumTimeline(pattern: .quarters, bpm: 120, start: 0, bars: 1)
        let next = tl.following()
        let onsets = tl.strokes.map(\.time) + [next.start - 0.05]
        XCTAssertEqual(StrumScore.grade(tl, onsets: onsets).extras.count, 1, "没有护栏时算成多扫")
        let guarded = StrumScore.grade(tl, onsets: onsets, guards: [next.strokes[0].time])
        XCTAssertEqual(guarded.extras.count, 0)
        XCTAssertEqual(guarded.score, 100)
        XCTAssertEqual(guarded.hits.count, tl.strokes.count, "护栏本身不计分")
    }

    // MARK: 离开页面

    @MainActor
    func testLeavingMidPracticeKeepsFinishedPasses() throws {
        let suite = "StrumPracticeLeave"
        UserDefaults().removePersistentDomain(forName: suite)
        let trainer = StrumTrainer(bpm: 80, defaults: UserDefaults(suiteName: suite)!)
        trainer.simulatePractice(passes: [score(8), score(6, missed: 2)], target: nil)
        XCTAssertTrue(trainer.isBusy)
        trainer.teardown()
        XCTAssertEqual(trainer.phase, .idle)
        let entry = try XCTUnwrap(trainer.history.last)
        XCTAssertEqual(entry.score, 88, "两遍的平均")
        XCTAssertEqual(entry.passes, 2)
        XCTAssertEqual(entry.family, "guitar")
        XCTAssertEqual(trainer.run?.passScores, [100, 75])
        XCTAssertNotNil(trainer.score)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @MainActor
    func testEndingBeforeAnyPassRecordsNothing() {
        let suite = "StrumPracticeNone"
        UserDefaults().removePersistentDomain(forName: suite)
        let trainer = StrumTrainer(bpm: 80, defaults: UserDefaults(suiteName: suite)!)
        trainer.simulatePractice(passes: [], target: 5)
        trainer.endPractice()
        XCTAssertEqual(trainer.phase, .idle)
        XCTAssertNil(trainer.history.last)
        XCTAssertNil(trainer.score)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @MainActor
    func testPracticeTargetIsRemembered() {
        let suite = "StrumPracticeTarget"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        let trainer = StrumTrainer(bpm: 80, defaults: d)
        XCTAssertNil(trainer.practiceTarget, "默认一直练")
        trainer.practiceTarget = 5
        XCTAssertEqual(StrumTrainer(bpm: 80, defaults: d).practiceTarget, 5)
        trainer.practiceTarget = nil
        XCTAssertNil(StrumTrainer(bpm: 80, defaults: d).practiceTarget)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    // MARK: 收藏、已掌握

    func testFavoritesFirstMasteredLast() {
        var marks = RhythmMarks()
        let list = StrumRhythm.presets(for: .guitar)   // folk1, folk2, eighths, quarters, waltz, chunk, funk, rootStrum, country, waltzBass
        marks.setFavorite(true, "funk", family: .guitar)
        marks.setMastered(true, "folk1", family: .guitar)
        marks.setMastered(true, "eighths", family: .guitar)
        marks.setFavorite(true, "eighths", family: .guitar)   // 收藏又掌握：收藏优先
        let ids = marks.sorted(list, family: .guitar).map(\.id)
        XCTAssertEqual(ids, ["eighths", "funk", "folk2", "quarters", "waltz", "chunk", "rootStrum", "country", "waltzBass", "folk1"])
        XCTAssertEqual(marks.filtered(list, by: .favorites, family: .guitar).map(\.id), ["eighths", "funk"])
        XCTAssertEqual(marks.filtered(list, by: .learning, family: .guitar).map(\.id),
                       ["funk", "folk2", "quarters", "waltz", "chunk", "rootStrum", "country", "waltzBass"])
        XCTAssertEqual(marks.sorted(list, family: .ukulele).map(\.id), list.map(\.id), "标记按乐器分开")
    }

    @MainActor
    func testMarksArePersistedPerInstrument() {
        let suite = "StrumMarks"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        let trainer = StrumTrainer(bpm: 80, defaults: d)
        trainer.instrumentID = "guitar"
        trainer.setFavorite(true, .waltz)
        trainer.filter = .favorites
        XCTAssertEqual(trainer.visiblePatterns.map(\.id), ["waltz"])
        XCTAssertEqual(trainer.patterns.first?.id, "waltz")
        let again = StrumTrainer(bpm: 80, defaults: d)
        XCTAssertTrue(again.isFavorite(.waltz))
        XCTAssertEqual(again.filter, .favorites)
        again.instrumentID = "ukulele"
        XCTAssertFalse(again.isFavorite(.waltz))
        XCTAssertTrue(again.visiblePatterns.isEmpty, "尤克里里还没有收藏")
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testMasterySuggestionNeedsThreeInARowAtNinety() {
        func entry(_ id: String, _ s: Int, family: String? = "guitar") -> StrumHistory.Entry {
            StrumHistory.Entry(date: Date(), patternID: id, chord: "C", bpm: 80, score: s, family: family)
        }
        var marks = RhythmMarks()
        XCTAssertFalse(marks.suggestsMastered("folk1", family: .guitar, history: [entry("folk1", 95), entry("folk1", 92)]), "只有 2 次")
        let three = [entry("folk1", 95), entry("folk2", 40), entry("folk1", 90), entry("folk1", 93)]
        XCTAssertTrue(marks.suggestsMastered("folk1", family: .guitar, history: three), "别的节奏型夹在中间不影响")
        XCTAssertFalse(marks.suggestsMastered("folk1", family: .guitar, history: three + [entry("folk1", 89)]), "最近一次没到 90")
        XCTAssertFalse(marks.suggestsMastered("folk1", family: .ukulele,
                                              history: three.map { var e = $0; e.family = "guitar"; return e }), "别的乐器的成绩不算")
        marks.decline("folk1", family: .guitar)
        XCTAssertFalse(marks.suggestsMastered("folk1", family: .guitar, history: three), "说过不标就不再问")
        var mastered = RhythmMarks()
        mastered.setMastered(true, "folk1", family: .guitar)
        XCTAssertFalse(mastered.suggestsMastered("folk1", family: .guitar, history: three), "已经标了")
    }

    @MainActor
    func testThirdHighScoreAsksToMarkMastered() {
        let suite = "StrumMastery"
        UserDefaults().removePersistentDomain(forName: suite)
        let trainer = StrumTrainer(bpm: 80, defaults: UserDefaults(suiteName: suite)!)
        trainer.instrumentID = "guitar"
        trainer.pattern = .folk2
        for _ in 0..<2 {
            trainer.simulatePractice(passes: [score(10)], target: 1)
            trainer.endPractice()
            XCTAssertNil(trainer.masterySuggestion)
        }
        trainer.simulatePractice(passes: [score(10)], target: 1)
        trainer.endPractice()
        XCTAssertEqual(trainer.masterySuggestion?.id, "folk2")
        trainer.answerMastery(true)
        XCTAssertTrue(trainer.isMastered(.folk2))
        XCTAssertNil(trainer.masterySuggestion)
        XCTAssertEqual(trainer.patterns.last?.id, "folk2", "已掌握的排到最后")
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

/// 和弦库新加的记号（根音 B、半扫 d）和新预设在训练页里的样子
final class StrumNotationTests: XCTestCase {
    func testNewPresetsAppearInTheTrainingList() {
        let ids = StrumRhythm.presets(for: .guitar).map(\.id)
        for id in ["rootStrum", "country", "waltzBass"] { XCTAssertTrue(ids.contains(id), id) }
    }

    func testMarksWorkForNewPresets() {
        var marks = RhythmMarks()
        let list = StrumRhythm.presets(for: .guitar)
        marks.setFavorite(true, "country", family: .guitar)
        marks.setMastered(true, "rootStrum", family: .guitar)
        let sorted = marks.sorted(list, family: .guitar).map(\.id)
        XCTAssertEqual(sorted.first, "country")
        XCTAssertEqual(sorted.last, "rootStrum")
        XCTAssertFalse(marks.filtered(list, by: .learning, family: .guitar).map(\.id).contains("rootStrum"))
    }

    /// 时间线里根音、半扫都算要扫的格；评分建议把全扫和半扫都当下扫
    func testTimelineKeepsNewCells() {
        let tl = StrumTimeline(pattern: .country, bpm: 100, start: 0, bars: 1)
        XCTAssertEqual(tl.strokes.map(\.stroke), [.bass, .downTreble, .up, .bass, .downTreble, .up])
        let late = tl.strokes.map { $0.time + ($0.stroke == .up ? 0.05 : 0) }
        let score = StrumScore.grade(StrumTimeline(pattern: .country, bpm: 100, start: 0, bars: 2), onsets: late + late.map { $0 + tl.barDuration })
        XCTAssertNotNil(score.meanOffsetMs(forAny: [.down, .downTreble]))
        XCTAssertEqual(StrumTrainer.bassWindows(tl, delay: 0.1).count, 2)
        XCTAssertEqual(StrumTrainer.bassWindows(tl, delay: 0.1)[0].lowerBound, 0.1 - StrumScore.offWindow, accuracy: 1e-9)
    }
}

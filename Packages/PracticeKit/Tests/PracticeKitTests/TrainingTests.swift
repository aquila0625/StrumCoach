import XCTest
@testable import PracticeKit

final class RampTests: XCTestCase {
    // 80 → 120，每 4 小节 +2
    let ramp = RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .hold)

    func testBpmAtBar() {
        XCTAssertEqual(ramp.bpm(atBar: 0), 80)
        XCTAssertEqual(ramp.bpm(atBar: 3), 80)
        XCTAssertEqual(ramp.bpm(atBar: 4), 82)
        XCTAssertEqual(ramp.bpm(atBar: 31), 94)
        XCTAssertEqual(ramp.bpm(atBar: 32), 96)   // 第 32 小节（从 0 数）= 96
        XCTAssertEqual(ramp.bpm(atBar: 79), 118)
        XCTAssertEqual(ramp.bpm(atBar: 80), 120)
        XCTAssertEqual(ramp.bpm(atBar: 10_000), 120)
        XCTAssertEqual(ramp.bpm(atBar: Int.max), 120)
        XCTAssertEqual(ramp.bpm(atBar: -5), 80)
    }

    func testStepMath() {
        XCTAssertEqual(ramp.stepCount, 20)
        XCTAssertEqual(ramp.barsToTarget, 80)
        XCTAssertEqual(ramp.cycleBars, 84)
    }

    func testProgress() {
        XCTAssertEqual(ramp.progress(atBar: 0), 0)
        XCTAssertEqual(ramp.progress(atBar: 40), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ramp.progress(atBar: 80), 1)
        XCTAssertEqual(ramp.progress(atBar: 500), 1)
    }

    func testLastStepLandsExactlyOnTarget() {
        let r = RampSettings(startBPM: 80, targetBPM: 121, step: 2, barsPerStep: 1)
        XCTAssertEqual(r.stepCount, 21)
        XCTAssertEqual(r.bpm(atBar: 20), 120)
        XCTAssertEqual(r.bpm(atBar: 21), 121)
        XCTAssertEqual(r.bpm(atBar: 22), 121)
    }

    func testStepLargerThanDistance() {
        let r = RampSettings(startBPM: 100, targetBPM: 103, step: 10, barsPerStep: 2)
        XCTAssertEqual(r.stepCount, 1)
        XCTAssertEqual(r.bpm(atBar: 1), 100)
        XCTAssertEqual(r.bpm(atBar: 2), 103)
    }

    func testDescending() {
        let r = RampSettings(startBPM: 120, targetBPM: 100, step: 5, barsPerStep: 2)
        XCTAssertFalse(r.isAscending)
        XCTAssertEqual(r.bpm(atBar: 0), 120)
        XCTAssertEqual(r.bpm(atBar: 2), 115)
        XCTAssertEqual(r.bpm(atBar: 6), 105)
        XCTAssertEqual(r.bpm(atBar: 8), 100)
        XCTAssertEqual(r.bpm(atBar: 50), 100)
    }

    func testStartEqualsTarget() {
        let r = RampSettings(startBPM: 100, targetBPM: 100, step: 5, barsPerStep: 4, endBehavior: .stop)
        XCTAssertEqual(r.stepCount, 0)
        XCTAssertEqual(r.bpm(atBar: 7), 100)
        XCTAssertEqual(r.progress(atBar: 0), 1)
        XCTAssertFalse(r.isFinished(atBar: 3))
        XCTAssertTrue(r.isFinished(atBar: 4))
    }

    func testStopFinishesAfterTargetStepPlays() {
        let r = RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .stop)
        XCTAssertFalse(r.isFinished(atBar: 80))   // 刚到 120，还在播
        XCTAssertFalse(r.isFinished(atBar: 83))
        XCTAssertTrue(r.isFinished(atBar: 84))
        XCTAssertEqual(r.bpm(atBar: 84), 120)
    }

    func testHoldNeverFinishes() {
        XCTAssertFalse(ramp.isFinished(atBar: 1_000_000))
    }

    func testLoopRestartsFromStart() {
        let r = RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .loop)
        XCTAssertEqual(r.bpm(atBar: 83), 120)
        XCTAssertEqual(r.bpm(atBar: 84), 80)
        XCTAssertEqual(r.bpm(atBar: 84 + 32), 96)
        XCTAssertEqual(r.progress(atBar: 84), 0)
        XCTAssertFalse(r.isFinished(atBar: 10_000))
    }

    func testInvalidParametersAreCorrected() {
        let r = RampSettings(startBPM: 5, targetBPM: 9999, step: 0, barsPerStep: -3)
        XCTAssertEqual(r.startBPM, 20)
        XCTAssertEqual(r.targetBPM, 400)
        XCTAssertEqual(r.step, 1)
        XCTAssertEqual(r.barsPerStep, 1)
        XCTAssertEqual(r.bpm(atBar: 1), 21)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(ramp)
        XCTAssertEqual(try JSONDecoder().decode(RampSettings.self, from: data), ramp)
    }
}

final class MuteTests: XCTestCase {
    func testBarCycle() {
        let m = MuteSettings.bars(audible: 2, muted: 1)
        let muted = (0..<9).map { m.isMuted(bar: $0, beat: 0) }
        XCTAssertEqual(muted, [false, false, true, false, false, true, false, false, true])
        // 同一小节所有拍一致
        XCTAssertEqual(m.isMuted(bar: 2, beat: 0), m.isMuted(bar: 2, beat: 3))
    }

    func testBarCycleDegenerateValues() {
        let neverMuted = MuteSettings.bars(audible: 3, muted: 0)
        XCTAssertTrue((0..<30).allSatisfy { !neverMuted.isMuted(bar: $0, beat: 0) })
        // audible 小于 1 按 1 算，第一小节永远有声
        let clamped = MuteSettings.bars(audible: 0, muted: 2)
        XCTAssertEqual((0..<6).map { clamped.isMuted(bar: $0, beat: 0) }, [false, true, true, false, true, true])
        XCTAssertFalse(MuteSettings.bars(audible: 1, muted: -4).isMuted(bar: 5, beat: 0))
    }

    func testRandomIsDeterministicPerSeed() {
        let a = MuteSettings.randomBeats(probability: 0.5, seed: 42)
        let b = MuteSettings.randomBeats(probability: 0.5, seed: 42)
        let c = MuteSettings.randomBeats(probability: 0.5, seed: 43)
        func pattern(_ m: MuteSettings) -> [Bool] {
            (0..<50).flatMap { bar in (0..<4).map { m.isMuted(bar: bar, beat: $0) } }
        }
        XCTAssertEqual(pattern(a), pattern(b))
        XCTAssertNotEqual(pattern(a), pattern(c))
        // 随机访问和顺序访问结果一致
        XCTAssertEqual(a.isMuted(bar: 37, beat: 2), pattern(a)[37 * 4 + 2])
    }

    func testRandomProbabilityExtremesAndRate() {
        let none = MuteSettings.randomBeats(probability: 0, seed: 1)
        let all = MuteSettings.randomBeats(probability: 1, seed: 1)
        let over = MuteSettings.randomBeats(probability: 7, seed: 1)
        let under = MuteSettings.randomBeats(probability: -1, seed: 1)
        for bar in 0..<200 {
            for beat in 0..<4 {
                XCTAssertFalse(none.isMuted(bar: bar, beat: beat))
                XCTAssertTrue(all.isMuted(bar: bar, beat: beat))
                XCTAssertTrue(over.isMuted(bar: bar, beat: beat))
                XCTAssertFalse(under.isMuted(bar: bar, beat: beat))
            }
        }
        let quarter = MuteSettings.randomBeats(probability: 0.25, seed: 2024)
        let count = (0..<2500).flatMap { bar in (0..<4).map { quarter.isMuted(bar: bar, beat: $0) } }.filter { $0 }.count
        XCTAssertEqual(Double(count) / 10_000, 0.25, accuracy: 0.03)
    }

    func testKeepsDownbeat() {
        let m = MuteSettings.randomBeats(probability: 1, seed: 9, keepsDownbeat: true)
        XCTAssertFalse(m.isMuted(bar: 3, beat: 0))
        XCTAssertTrue(m.isMuted(bar: 3, beat: 1))
    }

    func testCodable() throws {
        for m in [MuteSettings.bars(audible: 3, muted: 1),
                  MuteSettings.randomBeats(probability: 0.3, seed: UInt64.max, keepsDownbeat: true)] {
            let data = try JSONEncoder().encode(m)
            XCTAssertEqual(try JSONDecoder().decode(MuteSettings.self, from: data), m)
        }
    }
}

final class TrainingPlanTests: XCTestCase {
    func testModeReflectsEnabledTrainings() {
        let ramp = RampSettings(startBPM: 80, targetBPM: 100, step: 2, barsPerStep: 2)
        let mute = MuteSettings.bars(audible: 2, muted: 1)
        XCTAssertEqual(TrainingPlan(baseBPM: 90).mode, .free)
        XCTAssertEqual(TrainingPlan(baseBPM: 90, ramp: ramp).mode, .ramp)
        XCTAssertEqual(TrainingPlan(baseBPM: 90, mute: mute).mode, .mute)
        XCTAssertEqual(TrainingPlan(baseBPM: 90, ramp: ramp, mute: mute).mode, .rampAndMute)
    }

    func testBothTrainingsRunTogether() {
        let plan = TrainingPlan(
            baseBPM: 90,
            ramp: RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .stop),
            mute: .bars(audible: 2, muted: 1))
        XCTAssertEqual(plan.state(bar: 32, beat: 1), .init(bpm: 96, isMuted: true, isFinished: false))    // 32 % 3 == 2，静音
        XCTAssertEqual(plan.state(bar: 33, beat: 1), .init(bpm: 96, isMuted: false, isFinished: false)) // 33 % 3 == 0，有声
        XCTAssertFalse(plan.state(bar: 34, beat: 0).isMuted)   // 34 % 3 == 1，有声
        XCTAssertTrue(plan.state(bar: 35, beat: 0).isMuted)    // 35 % 3 == 2，静音
        XCTAssertEqual(plan.state(bar: 35, beat: 0).bpm, 96)
        XCTAssertTrue(plan.state(bar: 84, beat: 0).isFinished)
    }

    func testPlanWithoutTrainingIsPlainBase() {
        let plan = TrainingPlan(baseBPM: 100)
        XCTAssertEqual(plan.state(bar: 500, beat: 3), .init(bpm: 100, isMuted: false, isFinished: false))
        XCTAssertNil(plan.progress(atBar: 5))
        XCTAssertEqual(plan.bpmRange(throughBar: 500), 100...100)
    }

    func testBpmRangeForSessionRecord() {
        func plan(_ b: RampSettings.EndBehavior) -> TrainingPlan {
            TrainingPlan(baseBPM: 80, ramp: RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: b))
        }
        XCTAssertEqual(plan(.hold).bpmRange(throughBar: 32), 80...96)
        XCTAssertEqual(plan(.hold).bpmRange(throughBar: 5000), 80...120)
        XCTAssertEqual(plan(.stop).bpmRange(throughBar: 83), 80...120)
        XCTAssertEqual(plan(.loop).bpmRange(throughBar: 84), 80...120)   // 刚折回起点，范围仍含 120
        XCTAssertEqual(plan(.loop).bpmRange(throughBar: 0), 80...80)
        let down = TrainingPlan(baseBPM: 120, ramp: RampSettings(startBPM: 120, targetBPM: 100, step: 5, barsPerStep: 2))
        XCTAssertEqual(down.bpmRange(throughBar: 4), 110...120)
    }

    func testPlanCodable() throws {
        let plan = TrainingPlan(
            baseBPM: 90, ramp: RampSettings(startBPM: 80, targetBPM: 100, step: 2, barsPerStep: 2, endBehavior: .loop),
            mute: .randomBeats(probability: 0.2, seed: 5))
        let data = try JSONEncoder().encode(plan)
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data), plan)
    }
}

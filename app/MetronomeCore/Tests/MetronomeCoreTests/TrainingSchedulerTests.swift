import XCTest
@testable import MetronomeCore

/// 渐进提速、静音训练接到调度器上之后的采样位置。
final class TrainingSchedulerTests: XCTestCase {
    private let sr = 48_000.0

    private func run(_ config: MetronomeConfig, samples: Int64, chunk: Int = 512) -> (events: [ClickEvent], scheduler: BeatScheduler) {
        var s = BeatScheduler(sampleRate: sr, config: config)
        s.start(at: 0)
        var out: [ClickEvent] = []
        var pos: Int64 = 0
        while pos < samples {
            let n = Int(min(Int64(chunk), samples - pos))
            s.generate(from: pos, count: n) { out.append($0) }
            pos += Int64(n)
        }
        return (out, s)
    }

    /// 按训练方案逐拍累加出理论位置（连续时间，不取整），用来和调度结果比较。
    private func idealBeatPositions(_ plan: TrainingPlan, beatsPerBar: Int, beats: Int) -> [Double] {
        var t = 0.0
        var list: [Double] = []
        for n in 0..<beats {
            list.append(t)
            t += sr * 60 / Double(plan.bpm(atBar: n / beatsPerBar))
        }
        return list
    }

    func testRampChangesTempoAtBarBoundaries() {
        // 80 → 120，每 4 小节 +2（PracticeKit README 的例子：第 32 小节是 96）
        let ramp = RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .hold)
        let plan = TrainingPlan(baseBPM: 80, ramp: ramp)
        let config = MetronomeConfig(bpm: 200, training: plan)  // 开了提速时 config.bpm 不起作用
        let (events, _) = run(config, samples: Int64(sr * 60 * 4))
        let mains = events.filter(\.isMainBeat)
        XCTAssertEqual(mains.first(where: { $0.bar == 32 })?.bpm, 96)
        let ideal = idealBeatPositions(plan, beatsPerBar: 4, beats: mains.count)
        for (e, t) in zip(mains, ideal) {
            XCTAssertEqual(Double(e.sample), t, accuracy: 0.5, "beat \(e.beatSerial)")
            XCTAssertEqual(e.bpm, Double(plan.bpm(atBar: e.bar)))
            XCTAssertEqual(e.bar, Int(e.beatSerial) / 4)
        }
        // 换档发生在小节第一拍：上一拍的间隔还是旧速度
        let first82 = mains.firstIndex { $0.bpm == 82 }!
        XCTAssertEqual(mains[first82].beatInBar, 0)
        XCTAssertEqual(mains[first82].sample - mains[first82 - 1].sample, 36_000)  // 80 BPM 一拍
        XCTAssertEqual(mains[first82 + 1].sample - mains[first82].sample, Int64((sr * 60 / 82).rounded()), accuracy: 1)
    }

    func testRampWithSubdivisionsKeepsOffsetsInsideEachBeat() {
        let plan = TrainingPlan(baseBPM: 100, ramp: RampSettings(startBPM: 100, targetBPM: 140, step: 5, barsPerStep: 1))
        let (events, _) = run(MetronomeConfig(timeSignature: .threeFour, subdivision: .triplet, training: plan), samples: Int64(sr * 30))
        var i = 0
        while i + 2 < events.count {
            let beat = events[i]
            XCTAssertTrue(beat.isMainBeat)
            let length = sr * 60 / beat.bpm
            XCTAssertEqual(Double(events[i + 1].sample - beat.sample), length / 3, accuracy: 1)
            XCTAssertEqual(Double(events[i + 2].sample - beat.sample), length * 2 / 3, accuracy: 1)
            i += 3
        }
    }

    func testRampStopEndsPlayback() {
        let ramp = RampSettings(startBPM: 120, targetBPM: 124, step: 2, barsPerStep: 1, endBehavior: .stop)
        XCTAssertEqual(ramp.cycleBars, 3)
        let (events, s) = run(MetronomeConfig(training: TrainingPlan(baseBPM: 120, ramp: ramp)), samples: Int64(sr * 20))
        XCTAssertTrue(s.isFinished)
        XCTAssertFalse(s.isRunning)
        let mains = events.filter(\.isMainBeat)
        XCTAssertEqual(mains.count, 12, "3 小节 × 4 拍，然后停止")
        XCTAssertEqual(mains.map(\.bpm), Array(repeating: 120, count: 4) + Array(repeating: 122, count: 4) + Array(repeating: 124, count: 4))
    }

    func testRampLoopReturnsToStart() {
        let ramp = RampSettings(startBPM: 60, targetBPM: 64, step: 4, barsPerStep: 1, endBehavior: .loop)
        let (events, _) = run(MetronomeConfig(timeSignature: .twoFour, training: TrainingPlan(baseBPM: 60, ramp: ramp)), samples: Int64(sr * 12))
        let perBar = events.filter { $0.isMainBeat && $0.beatInBar == 0 }.map(\.bpm)
        XCTAssertEqual(Array(perBar.prefix(5)), [60, 64, 60, 64, 60])
    }

    func testMuteBarsSilenceWholeBarsButKeepTiming() {
        let plan = TrainingPlan(baseBPM: 120, mute: .bars(audible: 2, muted: 1))
        let (events, _) = run(MetronomeConfig(bpm: 120, subdivision: .eighth, training: plan), samples: 24_000 * 4 * 6)
        for e in events {
            let shouldMute = e.bar % 3 == 2
            XCTAssertEqual(e.isTrainingMuted, shouldMute, "bar \(e.bar)")
            if shouldMute { XCTAssertEqual(e.gain, 0) } else { XCTAssertGreaterThan(e.gain, 0) }
        }
        // 静音小节里节拍照常走：位置仍然是 n × 24000
        let mains = events.filter(\.isMainBeat)
        XCTAssertEqual(mains.map(\.sample), (0..<mains.count).map { Int64($0) * 24_000 })
    }

    func testRandomMuteFollowsPracticeKitPattern() {
        let mute = MuteSettings.randomBeats(probability: 0.4, seed: 7, keepsDownbeat: true)
        let plan = TrainingPlan(baseBPM: 150, mute: mute)
        let (events, _) = run(MetronomeConfig(bpm: 150, timeSignature: .sevenEight, training: plan), samples: Int64(sr * 30))
        var muted = 0
        for e in events where e.isMainBeat {
            XCTAssertEqual(e.isTrainingMuted, mute.isMuted(bar: e.bar, beat: e.beatInBar))
            if e.beatInBar == 0 { XCTAssertFalse(e.isTrainingMuted) }
            if e.isTrainingMuted { muted += 1 }
        }
        XCTAssertGreaterThan(muted, 0)
    }

    func testRampAndMuteTogether() {
        let ramp = RampSettings(startBPM: 90, targetBPM: 100, step: 5, barsPerStep: 2)
        let plan = TrainingPlan(baseBPM: 90, ramp: ramp, mute: .bars(audible: 3, muted: 1))
        XCTAssertEqual(plan.mode, .rampAndMute)
        let (events, _) = run(MetronomeConfig(training: plan), samples: Int64(sr * 40))
        let mains = events.filter(\.isMainBeat)
        let ideal = idealBeatPositions(plan, beatsPerBar: 4, beats: mains.count)
        for (e, t) in zip(mains, ideal) {
            XCTAssertEqual(Double(e.sample), t, accuracy: 0.5)
            XCTAssertEqual(e.isTrainingMuted, e.bar % 4 == 3)
            XCTAssertEqual(e.bpm, Double(ramp.bpm(atBar: e.bar)))
        }
    }

    func testTurningTrainingOnMidPlayAppliesAtNextBeat() {
        var s = BeatScheduler(sampleRate: sr, config: MetronomeConfig(bpm: 120))
        s.start(at: 0)
        var events: [ClickEvent] = []
        s.generate(from: 0, count: 30_000) { events.append($0) }
        var c = s.config
        c.training = TrainingPlan(baseBPM: 120, mute: .bars(audible: 1, muted: 1))
        s.update(c)
        s.generate(from: 30_000, count: 24_000 * 8) { events.append($0) }
        // 小节计数不重置：第 1 小节（bar 1）是静音小节
        XCTAssertEqual(events.map(\.isTrainingMuted), [false, false, false, false, true, true, true, true, false, false])
        XCTAssertEqual(events.map(\.sample), (0..<10).map { Int64($0) * 24_000 })
    }
}

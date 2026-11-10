import XCTest
@testable import TunerKit

final class SmootherTests: XCTestCase {
    func testSingleOutlierIsIgnored() {
        var s = PitchSmoother()
        for _ in 0..<6 { s.process(RawPitch(frequency: 440, clarity: 0.95), a4: 440) }
        let r = s.process(RawPitch(frequency: 880, clarity: 0.9), a4: 440)   // 一帧八度误判
        XCTAssertEqual(r?.frequency ?? 0, 440, accuracy: 0.5)
        let r2 = s.process(RawPitch(frequency: 440.5, clarity: 0.95), a4: 440)
        XCTAssertEqual(r2?.frequency ?? 0, 440, accuracy: 1)
    }

    func testJitterIsReduced() {
        var s = PitchSmoother()
        var rng = SplitMix64(seed: 3)
        var rawSpread = 0.0, outSpread = 0.0
        var outs: [Double] = []
        for i in 0..<60 {
            let jitterCents = (rng.nextUnit() - 0.5) * 8
            let f = 220 * pow(2, jitterCents / 1200)
            rawSpread = max(rawSpread, abs(jitterCents))
            let r = s.process(RawPitch(frequency: f, clarity: 0.9), a4: 440)
            if i > 10 { outs.append(1200 * log2(r!.frequency / 220)) }
        }
        outSpread = outs.map(abs).max()!
        XCTAssertLessThan(outSpread, rawSpread * 0.6)
    }

    func testRealNoteChangeIsAcceptedAfterConfirmation() {
        var s = PitchSmoother()
        for _ in 0..<6 { s.process(RawPitch(frequency: 110, clarity: 0.95), a4: 440) }
        var r: PitchReading?
        for _ in 0..<4 { r = s.process(RawPitch(frequency: 146.83, clarity: 0.95), a4: 440) }
        XCTAssertEqual(r?.frequency ?? 0, 146.83, accuracy: 1)
    }

    func testHoldsThenClears() {
        var s = PitchSmoother()
        s.holdFrames = 3
        s.process(RawPitch(frequency: 330, clarity: 0.95), a4: 440)
        for _ in 0..<3 { XCTAssertNotNil(s.process(nil, a4: 440)) }
        XCTAssertNil(s.process(nil, a4: 440))
        XCTAssertFalse(s.isActive)
    }
}

@MainActor
final class TunerModelTests: XCTestCase {
    /// 可控的时钟：每喂一帧前进 30 ms，测试里不依赖真实时间。
    private final class FakeClock { var now = 100.0 }
    private let clock = FakeClock()
    private var chimes = 0

    /// 造一个模型：用假时钟，提示音换成只计数（不真的出声）。
    private func makeModel(_ selection: InstrumentSelection = .default) -> TunerModel {
        UserDefaults.standard.removeObject(forKey: TunerModel.chimeDefaultsKey)
        let model = TunerModel(selection: selection)
        let clock = self.clock
        model.clock = { clock.now }
        model.playChime = { [unowned self] in self.chimes += 1; return true }
        return model
    }

    private func feed(_ model: TunerModel, _ f: Double, frames: Int = 12, noise: Bool = false) {
        for i in 0..<frames {
            clock.now += 0.03
            var x = Signal.make(.harmonics, frequency: f, phase: Double(i) * 0.31)
            if noise { x = Signal.addNoise(x, snrDB: 20, seed: UInt64(i + 1)) }
            model.ingest(samples: x, sampleRate: 44100)
        }
    }

    func testAutoRecognisesStringAndTicksWhenTuned() {
        let model = makeModel(InstrumentSelection(instrumentID: "guitar", tuningID: "standard"))
        feed(model, 110.0, frames: 30)
        XCTAssertEqual(model.result?.stringIndex, 1)
        XCTAssertEqual(model.result?.target.fullName, "A2")
        XCTAssertTrue(model.result?.isInTune ?? false)
        XCTAssertEqual(model.tunedStrings, [1])
        XCTAssertEqual(model.tunedEventCount, 1)

        // 调准时响了提示音，之后一小段时间忽略检测；等它过去，再弹成 30 音分偏差 → 不再是“已准”，勾选取消（偏出 10 音分以上取消）
        clock.now += 2
        feed(model, 110 * pow(2, 30.0 / 1200), frames: 12)
        XCTAssertFalse(model.result?.isInTune ?? true)
        XCTAssertEqual(model.tunedStrings, [])
    }

    func testLockedStringAndUnlock() {
        let model = makeModel(InstrumentSelection(instrumentID: "guitar", tuningID: "standard"))
        model.lockString(0)
        feed(model, 110)
        XCTAssertEqual(model.result?.stringIndex, 0)
        XCTAssertGreaterThan(model.result?.cents ?? 0, 400)
        model.lockString(0)    // 再点一次解锁
        XCTAssertNil(model.lockedString)
        XCTAssertEqual(model.result?.stringIndex, 1)
    }

    func testSilenceClearsReading() {
        let model = makeModel()
        feed(model, 440)
        XCTAssertNotNil(model.reading)
        for _ in 0..<20 { model.ingest(samples: [Float](repeating: 0, count: 4096), sampleRate: 44100) }
        XCTAssertNil(model.reading)
        XCTAssertNil(model.result)
        XCTAssertNotNil(model.lastReading)
    }

    func testChangingInstrumentResetsState() {
        let model = makeModel(InstrumentSelection(instrumentID: "guitar", tuningID: "standard"))
        feed(model, 110)
        model.lockString(2)
        model.select(instrument: InstrumentLibrary.bass)
        XCTAssertEqual(model.tuning.id, "4string")
        XCTAssertNil(model.lockedString)
        XCTAssertTrue(model.tunedStrings.isEmpty)
        XCTAssertEqual(model.selection, InstrumentSelection(instrumentID: "bass", tuningID: "4string"))
    }

    func testA4RangeAndEffect() {
        let model = makeModel()
        model.setA4(400); XCTAssertEqual(model.a4, 415)
        model.setA4(500); XCTAssertEqual(model.a4, 466)
        model.setA4(442); XCTAssertEqual(model.a4, 442)
        // A4=442 时，442 Hz 就是准的 A4
        feed(model, 442)
        XCTAssertEqual(model.result?.target.fullName, "A4")
        XCTAssertEqual(model.result?.cents ?? 99, 0, accuracy: 1)
    }
}

/// “调准”提示：持续时间、只提示一次、偏出后再回来才会再次提示、提示音期间忽略检测。
@MainActor
final class TuneChimeModelTests: XCTestCase {
    private final class FakeClock { var now = 100.0 }
    private let clock = FakeClock()
    private var chimes = 0

    private func makeModel(_ id: String = "guitar", tuning: String = "standard", chime: Bool = true) -> TunerModel {
        UserDefaults.standard.removeObject(forKey: TunerModel.chimeDefaultsKey)
        let model = TunerModel(selection: InstrumentSelection(instrumentID: id, tuningID: tuning))
        let clock = self.clock
        model.clock = { clock.now }
        model.playChime = { [unowned self] in self.chimes += 1; return true }
        model.tuneChimeEnabled = chime
        UserDefaults.standard.removeObject(forKey: TunerModel.chimeDefaultsKey)
        return model
    }

    /// 以 30 ms 一帧喂 `seconds` 秒的稳定读数（偏差 `cents`）。
    private func hold(_ model: TunerModel, _ f: Double, cents: Double = 0, seconds: Double) {
        let hz = f * pow(2, cents / 1200)
        for _ in 0..<Int((seconds / 0.03).rounded()) {
            clock.now += 0.03
            model.ingest(RawPitch(frequency: hz, clarity: 0.97))
        }
    }

    func testDoesNotFireBeforeHalfSecond() {
        let model = makeModel()
        hold(model, 110, seconds: 0.4)
        XCTAssertEqual(model.tunedEventCount, 0)
        XCTAssertEqual(chimes, 0)
        XCTAssertTrue(model.tunedStrings.isEmpty)
        hold(model, 110, seconds: 0.3)
        XCTAssertEqual(model.tunedEventCount, 1)
        XCTAssertEqual(chimes, 1)
        XCTAssertEqual(model.tunedStrings, [1])
        XCTAssertEqual(model.lastTunedEvent?.stringIndex, 1)
        XCTAssertEqual(model.lastTunedEvent?.pitch.fullName, "A2")
    }

    func testSweepingThroughTheTuneZoneDoesNotFire() {
        let model = makeModel()
        // 指针从 −30 扫到 +30 音分，经过准音区只有零点几秒
        for step in 0...20 {
            clock.now += 0.03
            model.ingest(RawPitch(frequency: 110 * pow(2, (Double(step) * 3 - 30) / 1200), clarity: 0.97))
        }
        XCTAssertEqual(model.tunedEventCount, 0)
        XCTAssertEqual(chimes, 0)
    }

    func testFiresOnlyOnceWhileStayingInTune() {
        let model = makeModel()
        hold(model, 110, seconds: 3)
        XCTAssertEqual(model.tunedEventCount, 1)
        XCTAssertEqual(chimes, 1)
    }

    func testFiresAgainOnlyAfterDriftingBeyondTenCentsAndReturning() {
        let model = makeModel()
        hold(model, 110, seconds: 1)
        XCTAssertEqual(chimes, 1)
        // 偏出 8 音分（在 5–10 之间）再回来：不算偏出，不再提示
        hold(model, 110, cents: 8, seconds: 1.5)
        hold(model, 110, seconds: 1.5)
        XCTAssertEqual(chimes, 1)
        XCTAssertEqual(model.tunedStrings, [1])
        // 偏出 20 音分：解锁并取消勾选；再回到准音区 0.5 秒才再次提示
        hold(model, 110, cents: 20, seconds: 1.5)
        XCTAssertEqual(model.tunedStrings, [])
        hold(model, 110, seconds: 1)
        XCTAssertEqual(chimes, 2)
        XCTAssertEqual(model.tunedEventCount, 2)
        XCTAssertEqual(model.tunedStrings, [1])
    }

    func testIgnoresDetectionWhileChimeIsPlayingAndShortlyAfter() {
        let model = makeModel()
        hold(model, 110, seconds: 1)
        XCTAssertEqual(chimes, 1)
        let before = model.reading?.frequency
        // 提示音期间（0.85 s）和之后 0.6 s：麦克风收到的“提示音”（≈1318 Hz）不能影响读数
        // （调准在第 0.5 s 触发，忽略窗口到约 1.95 s 结束）
        hold(model, 1318.51, seconds: 0.9)
        XCTAssertEqual(model.reading?.frequency ?? 0, before ?? 1, accuracy: 0.01)
        XCTAssertEqual(model.result?.stringIndex, 1)
        XCTAssertEqual(chimes, 1)
        // 窗口过后恢复检测：重新平滑后识别出新的音
        hold(model, 196, seconds: 0.8)
        XCTAssertEqual(model.result?.target.fullName, "G3")
    }

    func testDisabledChimeStillTicksAndCountsButDoesNotPlayOrBlindDetection() {
        let model = makeModel(chime: false)
        hold(model, 110, seconds: 1)
        XCTAssertEqual(model.tunedEventCount, 1)
        XCTAssertEqual(model.tunedStrings, [1])
        XCTAssertEqual(chimes, 0)
        hold(model, 196, seconds: 0.5)       // 没有提示音就没有忽略窗口，马上能跟上新的音
        XCTAssertEqual(model.result?.target.fullName, "G3")
    }

    func testChromaticModeFiresPerNoteName() {
        let model = makeModel("auto", tuning: "chromatic")
        hold(model, 440, seconds: 1)
        XCTAssertEqual(chimes, 1)
        XCTAssertNil(model.lastTunedEvent?.stringIndex)
        XCTAssertEqual(model.lastTunedEvent?.pitch.fullName, "A4")
        XCTAssertTrue(model.tunedStrings.isEmpty)
        hold(model, 440, seconds: 2)
        XCTAssertEqual(chimes, 1, "同一个音只提示一次")
        // 换到别的音（等忽略窗口过去）：这是另一个音，调准后再提示一次
        clock.now += 1.5
        hold(model, 329.63, seconds: 1.2)
        XCTAssertEqual(chimes, 2)
        XCTAssertEqual(model.lastTunedEvent?.pitch.fullName, "E4")
    }

    func testSwitchingTargetRestartsTheHold() {
        let model = makeModel()
        model.lockString(1)
        hold(model, 110, seconds: 0.4)
        model.lockString(3)                  // 换了目标：持续时间从头算
        hold(model, 110, seconds: 0.4)
        XCTAssertEqual(chimes, 0)
    }

    func testChimeSettingIsPersistedAndDefaultsToOn() {
        UserDefaults.standard.removeObject(forKey: TunerModel.chimeDefaultsKey)
        XCTAssertTrue(TunerModel().tuneChimeEnabled)
        let model = TunerModel()
        model.tuneChimeEnabled = false
        XCTAssertFalse(TunerModel().tuneChimeEnabled)
        model.tuneChimeEnabled = true
        XCTAssertTrue(TunerModel().tuneChimeEnabled)
        UserDefaults.standard.removeObject(forKey: TunerModel.chimeDefaultsKey)
    }
}

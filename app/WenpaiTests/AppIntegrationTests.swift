import ChordKit
import MetronomeCore
import SwiftData
import TunerKit
import XCTest
@testable import Wenpai

/// App 层把几个包接在一起的逻辑：乐器联动、训练方案、练习记录。
@MainActor
final class AppIntegrationTests: XCTestCase {
    /// 用演示参数构造，避免测试读写真实的 UserDefaults。
    private func makeController() -> MetronomeController {
        let demo = DemoOptions(config: .default, training: TrainingOptions(), playing: false, beat: nil, elapsed: 0,
                               liveBar: nil, liveBPM: nil, todaySeconds: nil, tab: .metronome, sheet: nil)
        return MetronomeController(demo: demo)
    }

    // MARK: 乐器联动

    func testChordInstrumentSwitchesTunerToStandardTuning() {
        let tuner = TunerModel(selection: .default)
        let chords = ChordLibraryModel()
        chords.select(instrument: InstrumentLibrary.bass)
        InstrumentSync.chordsChanged(chords, tuner: tuner)
        XCTAssertEqual(tuner.instrument.id, "bass")
        XCTAssertEqual(tuner.tuning.id, InstrumentLibrary.bass.defaultTuning.id)
    }

    func testTunerTuningSwitchesChordLibrary() {
        let tuner = TunerModel(selection: .default)
        let chords = ChordLibraryModel()
        let ukulele = InstrumentLibrary.ukulele
        tuner.select(instrument: ukulele, tuning: ukulele.tuning(id: "lowG"))
        InstrumentSync.tunerChanged(tuner, chords: chords)
        XCTAssertEqual(chords.instrument.id, "ukulele")
        XCTAssertEqual(chords.tuning.id, "lowG")
        // 回传一次不会把调音器改回标准定弦（不来回触发）
        InstrumentSync.chordsChanged(chords, tuner: tuner)
        XCTAssertEqual(tuner.tuning.id, "lowG")
    }

    func testTunerInstrumentsWithoutChordsLeaveChordLibraryAlone() {
        let tuner = TunerModel(selection: .default)
        let chords = ChordLibraryModel()
        tuner.select(instrument: InstrumentLibrary.violin)
        InstrumentSync.tunerChanged(tuner, chords: chords)
        XCTAssertEqual(chords.instrument.id, "guitar")
        tuner.select(instrument: InstrumentLibrary.auto)
        InstrumentSync.tunerChanged(tuner, chords: chords)
        XCTAssertEqual(chords.instrument.id, "guitar")
    }

    // MARK: 切分和训练全部可用

    func testEverySubdivisionAndTrainingModeIsAvailable() {
        let m = makeController()
        for sub in Subdivision.allCases {
            m.select(sub)
            XCTAssertEqual(m.config.subdivision, sub)
        }
        m.training.rampEnabled = true
        m.training.muteEnabled = true
        XCTAssertEqual(m.config.training?.mode, .rampAndMute)
    }

    // MARK: 训练方案

    func testTrainingOptionsDriveEngineConfig() {
        let m = makeController()
        XCTAssertNil(m.config.training)
        m.training.muteEnabled = true
        XCTAssertEqual(m.config.training?.mode, .mute)
        XCTAssertEqual(m.config.training?.mute, MuteSettings.bars(audible: 3, muted: 1))
        m.training.ramp = RampSettings(startBPM: 60, targetBPM: 90, step: 3, barsPerStep: 2, endBehavior: .stop)
        m.training.rampEnabled = true
        XCTAssertEqual(m.config.training?.ramp?.targetBPM, 90)
        XCTAssertTrue(m.tempoIsControlledByTraining)
        XCTAssertEqual(m.displayBPM, 60, "没在播放时显示提速的起始速度")
        m.nudge(5)
        XCTAssertEqual(m.bpm, 120, "提速控制速度时手动加减不起作用")
        m.training.timerEnabled = true
        XCTAssertEqual(m.config.training?.mode, .rampAndMute, "练习计时不影响引擎")
    }

    // MARK: 练习记录

    func testPracticeIsRecordedOnlyFrom30Seconds() throws {
        let container = try PracticeKitSchema.makeContainer(inMemory: true)
        let m = makeController()
        m.modelContext = container.mainContext
        m.recordPractice(duration: 29.9)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PracticeSession>()), 0)
        m.recordPractice(duration: 45)
        let sessions = try container.mainContext.fetch(FetchDescriptor<PracticeSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].duration, 45)
        XCTAssertEqual(sessions[0].mode, .free)
    }

    func testDemoSeedMatchesDesignWeek() throws {
        let container = try PracticeKitSchema.makeContainer(inMemory: true)
        DemoOptions.seed(container.mainContext)
        let sessions = try container.mainContext.fetch(FetchDescriptor<PracticeSession>())
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let stats = PracticeStatistics(calendar: calendar)
        XCTAssertEqual(stats.dailyDurations(of: sessions).map { Int($0.duration / 60) }, [35, 20, 48, 0, 30, 42, 30])
    }
}

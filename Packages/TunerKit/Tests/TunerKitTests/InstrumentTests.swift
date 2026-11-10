import XCTest
@testable import TunerKit

final class InstrumentTests: XCTestCase {
    func testPitchBasics() {
        XCTAssertEqual(Pitch("A4")?.midi, 69)
        XCTAssertEqual(Pitch("C4")?.midi, 60)
        XCTAssertEqual(Pitch("Eb2")?.midi, 39)
        XCTAssertEqual(Pitch("F#3")?.midi, 54)
        XCTAssertEqual(Pitch("B0")?.midi, 23)
        XCTAssertEqual(Pitch(midi: 69).frequency(), 440, accuracy: 1e-9)
        XCTAssertEqual(Pitch(midi: 40).frequency(), 82.4069, accuracy: 0.001)
        XCTAssertEqual(Pitch(midi: 70).name, "A♯")
        XCTAssertEqual(Pitch(midi: 23).fullName, "B0")
        XCTAssertNil(Pitch("H4"))
    }

    func testA4ShiftsFrequencies() {
        XCTAssertEqual(Pitch(midi: 69).frequency(a4: 415), 415, accuracy: 1e-9)
        XCTAssertEqual(Pitch(midi: 69).frequency(a4: 466), 466, accuracy: 1e-9)
        // 415 Hz 在 A4=415 下是 A4、偏差 0
        let n = Pitch.nearest(frequency: 415, a4: 415)
        XCTAssertEqual(n.pitch.midi, 69)
        XCTAssertEqual(n.cents, 0, accuracy: 1e-9)
    }

    private func notes(_ id: String, _ tuning: String) -> [String] {
        InstrumentLibrary.instrument(id: id)!.tuning(id: tuning)!.strings.map(\.pitch.fullName)
    }

    func testBuiltInTunings() {
        XCTAssertEqual(notes("guitar", "standard"), ["E2", "A2", "D3", "G3", "B3", "E4"])
        XCTAssertEqual(notes("guitar", "dropD"), ["D2", "A2", "D3", "G3", "B3", "E4"])
        XCTAssertEqual(notes("guitar", "halfDown"), ["D♯2", "G♯2", "C♯3", "F♯3", "A♯3", "D♯4"])
        XCTAssertEqual(notes("guitar", "dadgad"), ["D2", "A2", "D3", "G3", "A3", "D4"])
        XCTAssertEqual(notes("bass", "4string"), ["E1", "A1", "D2", "G2"])
        XCTAssertEqual(notes("bass", "5string"), ["B0", "E1", "A1", "D2", "G2"])
        XCTAssertEqual(notes("ukulele", "highG"), ["G4", "C4", "E4", "A4"])
        XCTAssertEqual(notes("ukulele", "lowG"), ["G3", "C4", "E4", "A4"])
        XCTAssertEqual(notes("violin", "standard"), ["G3", "D4", "A4", "E5"])
        XCTAssertEqual(notes("viola", "standard"), ["C3", "G3", "D4", "A4"])
        XCTAssertEqual(notes("cello", "standard"), ["C2", "G2", "D3", "A3"])
    }

    func testLibraryIsConsistent() {
        let ids = InstrumentLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(InstrumentLibrary.auto.defaultTuning.isChromatic)
        for inst in InstrumentLibrary.all {
            XCTAssertNotNil(inst.tuning(id: inst.defaultTuningID))
            for t in inst.tunings where !t.isChromatic {
                XCTAssertEqual(t.strings.map(\.number), Array((1...t.stringCount).reversed()))
            }
        }
    }

    func testSelectionResolveFallsBack() {
        let r = InstrumentSelection(instrumentID: "guitar", tuningID: "nonsense").resolve()
        XCTAssertEqual(r.instrument.id, "guitar")
        XCTAssertEqual(r.tuning.id, "standard")
        XCTAssertEqual(InstrumentSelection(instrumentID: "zzz", tuningID: "x").resolve().instrument.id, "auto")
        let data = try! JSONEncoder().encode(InstrumentSelection(instrumentID: "bass", tuningID: "5string"))
        XCTAssertEqual(try! JSONDecoder().decode(InstrumentSelection.self, from: data).tuningID, "5string")
    }

    // MARK: 弦匹配

    private func reading(_ f: Double, a4: Double = 440) -> PitchReading {
        PitchReading(frequency: f, clarity: 1, a4: a4)
    }

    func testAutoMatchPicksClosestString() {
        let guitar = InstrumentLibrary.guitar.defaultTuning
        let cases: [(Double, Int)] = [(82.41, 0), (110, 1), (146.83, 2), (196, 3), (246.94, 4), (329.63, 5),
                                      (84, 0), (108, 1), (200, 3), (320, 5)]
        for (f, idx) in cases {
            let r = guitar.match(reading(f))
            XCTAssertEqual(r.stringIndex, idx, "\(f) Hz")
        }
        let r = guitar.match(reading(110 * pow(2, 8.0 / 1200)))
        XCTAssertEqual(r.cents, 8, accuracy: 1e-6)
        XCTAssertTrue(r.isSharp)
        XCTAssertFalse(r.isInTune)
        XCTAssertTrue(guitar.match(reading(110 * pow(2, -4.0 / 1200))).isInTune)
    }

    func testOctaveWrongNoteChoosesNearestByPitchNotByOctave() {
        // E3（164.81 Hz）不是任何一根空弦：按真实音高取最近的 D3，而不是按音名去配 E2
        let guitar = InstrumentLibrary.guitar.defaultTuning
        let r = guitar.match(reading(164.81))
        XCTAssertEqual(r.stringIndex, 2)   // D3 = 146.83，差约 200 音分，仍是最近
    }

    func testUkuleleReentrantTuning() {
        let high = InstrumentLibrary.ukulele.tuning(id: "highG")!
        let low = InstrumentLibrary.ukulele.tuning(id: "lowG")!
        // G4 = 392 Hz 在高音 G 定弦里是第 1 根弦（index 0），并不是音高最低的那根
        XCTAssertEqual(high.match(reading(392)).stringIndex, 0)
        XCTAssertEqual(high.match(reading(392)).target.fullName, "G4")
        XCTAssertEqual(high.match(reading(261.63)).stringIndex, 1)   // C4
        XCTAssertEqual(high.match(reading(440)).stringIndex, 3)      // A4
        XCTAssertEqual(low.match(reading(196)).stringIndex, 0)       // G3
        XCTAssertEqual(low.match(reading(196)).target.fullName, "G3")
    }

    func testLockedStringMeasuresAgainstThatString() {
        let guitar = InstrumentLibrary.guitar.defaultTuning
        // 弹的是 A2(110)，但锁定了 E2：偏差约 +500 音分
        let r = guitar.match(reading(110), lockedString: 0)
        XCTAssertEqual(r.stringIndex, 0)
        XCTAssertEqual(r.target.fullName, "E2")
        XCTAssertEqual(r.cents, 500, accuracy: 1)
        // 锁定后弹准 E2 → 已准
        XCTAssertTrue(guitar.match(reading(82.41), lockedString: 0).isInTune)
        // 越界的锁定索引被忽略，回到自动
        XCTAssertEqual(guitar.match(reading(110), lockedString: 99).stringIndex, 1)
    }

    func testChromaticMatch() {
        let auto = InstrumentLibrary.auto.defaultTuning
        let r = auto.match(reading(440.8))
        XCTAssertNil(r.stringIndex)
        XCTAssertEqual(r.target.fullName, "A4")
        XCTAssertEqual(r.cents, 3.15, accuracy: 0.05)
        XCTAssertEqual(auto.match(reading(261.63)).target.fullName, "C4")
    }

    func testMatchHonoursA4() {
        let g = InstrumentLibrary.guitar.defaultTuning
        // A4 = 415 时，标准 A2 弦的目标是 103.75 Hz
        let r = g.match(reading(103.75, a4: 415))
        XCTAssertEqual(r.stringIndex, 1)
        XCTAssertTrue(r.isInTune)
        XCTAssertEqual(r.targetFrequency, 103.75, accuracy: 0.01)
    }
}

import XCTest
import TunerKit
@testable import ChordKit

final class BassTests: XCTestCase {
    let bass4 = InstrumentLibrary.bass.defaultTuning
    let bass5 = InstrumentLibrary.bass.tunings[1]

    func testCMajorPositions() throws {
        let p = try XCTUnwrap(BassPositions.make(chord: Chord("C", .major)!, tuning: bass4))
        // 根音：A 弦 3 品（C2）；框从 2 品开始
        let anchor = try XCTUnwrap(p.anchor)
        XCTAssertEqual(anchor.string, 1)
        XCTAssertEqual(anchor.fret, 3)
        XCTAssertEqual(anchor.pitch, Pitch("C2"))
        XCTAssertEqual(p.startFret, 2)
        XCTAssertFalse(p.showsNut)
        XCTAssertEqual(p.fretCount, 5)
        // 三度 E、五度 G 都要在框里出现
        XCTAssertTrue(p.markers(for: .third).contains { $0.pitch.pitchClass == 4 })
        XCTAssertTrue(p.markers(for: .fifth).contains { $0.pitch.pitchClass == 7 })
        // 八度 C3 在 G 弦 5 品
        XCTAssertTrue(p.markers.contains { $0.role == .octave && $0.string == 3 && $0.fret == 5 && $0.pitch == Pitch("C3") })
    }

    func testOpenStringRootShowsNutAndOpenMarkers() throws {
        let p = try XCTUnwrap(BassPositions.make(chord: Chord("E", .minor)!, tuning: bass4))
        XCTAssertTrue(p.showsNut)
        XCTAssertEqual(p.anchor?.fret, 0)
        XCTAssertTrue(p.markers.contains { $0.fret == 0 && $0.role == .root && $0.string == 0 })
        // 五度 B：A 弦 2 品
        XCTAssertTrue(p.markers.contains { $0.role == .fifth && $0.string == 1 && $0.fret == 2 })
    }

    func testEveryMarkerIsAChordToneInsideTheFrame() {
        for tuning in [bass4, bass5] {
            for root in ChordRoot.all {
                for type in ChordType.builtins {
                    let chord = Chord(root: root, type: type)
                    guard let p = BassPositions.make(chord: chord, tuning: tuning) else { return XCTFail("\(chord.name)") }
                    XCTAssertNotNil(p.anchor, chord.name)
                    XCTAssertEqual(p.anchor?.role, .root)
                    XCTAssertEqual(p.stringCount, tuning.stringCount)
                    let lo = p.showsNut ? 0 : p.firstRow
                    let hi = p.firstRow + p.fretCount - 1
                    let tones = Set(chord.pitchClasses)
                    for m in p.markers {
                        XCTAssertTrue((lo...hi).contains(m.fret), "\(chord.name) 标记超出把位框")
                        XCTAssertTrue(tones.contains(m.pitch.pitchClass))
                        XCTAssertEqual(m.pitch, tuning.strings[m.string].pitch.transposed(by: m.fret))
                    }
                    // 根音、三度、五度、八度都至少出现一次（框含 5 品，每种音在 4 弦上总能找到）
                    for role in [BassPositions.Role.root, .third, .fifth] {
                        XCTAssertFalse(p.markers(for: role).isEmpty, "\(chord.name) 框里没有 \(role)")
                    }
                    XCTAssertFalse(p.markers(for: .octave).isEmpty, "\(chord.name) 框里没有八度")
                }
            }
        }
    }

    func testChromaticTuningHasNoPositions() {
        XCTAssertNil(BassPositions.make(chord: Chord("C", .major)!, tuning: InstrumentLibrary.auto.defaultTuning))
    }
}

final class FavoritesTests: XCTestCase {
    func testToggleAndCodable() throws {
        var favs = ChordFavorites()
        let f = ChordFavorite(instrumentID: "guitar", tuningID: "standard", root: 0, typeID: "maj7", voicingIndex: 1)
        let g = ChordFavorite(instrumentID: "ukulele", tuningID: "highG", root: 9, typeID: "minor", voicingIndex: 0)
        XCTAssertTrue(favs.toggle(f))
        favs.add(g); favs.add(g)
        XCTAssertEqual(favs.items, [g, f])
        let data = try JSONEncoder().encode(favs)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("["), "收藏应编码成 JSON 数组")
        let back = try JSONDecoder().decode(ChordFavorites.self, from: data)
        XCTAssertEqual(back, favs)
        XCTAssertEqual(back.items[1].chord?.name, "Cmaj7")
        XCTAssertFalse(favs.toggle(f))
        XCTAssertFalse(favs.contains(f))
    }
}

@MainActor
final class ModelTests: XCTestCase {
    func testInstrumentSwitchAndBass() {
        let m = ChordLibraryModel()
        m.select(root: 9); m.select(type: .minor)
        XCTAssertEqual(m.voicing?.shorthand, "x02210")
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(m.voicing?.shorthand, "2000")
        m.select(instrument: InstrumentLibrary.bass)
        XCTAssertNil(m.voicing)
        XCTAssertNotNil(m.bassPositions)
        XCTAssertEqual(m.voicingCount, 1)
        XCTAssertEqual(m.current.voicingIndex, 0)
    }

    func testFavoritesJumpAndRestore() {
        let m = ChordLibraryModel()
        var saved: ChordFavorites?
        m.onFavoritesChange = { saved = $0 }
        m.select(root: 7); m.select(voicingIndex: 1)
        m.toggleFavorite()
        XCTAssertTrue(m.isFavorite)
        XCTAssertEqual(saved?.items.count, 1)
        m.select(root: 0)
        XCTAssertFalse(m.isFavorite)
        m.go(to: saved!.items[0])
        XCTAssertEqual(m.chord.name, "G")
        XCTAssertEqual(m.voicingIndex, 1)
        // 用 current 恢复
        let restored = ChordLibraryModel(current: m.current)
        XCTAssertEqual(restored.current, m.current)
    }
}

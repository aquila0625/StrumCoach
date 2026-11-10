import AVFoundation
import XCTest
import TunerKit
@testable import ChordKit

final class StrumRhythmTests: XCTestCase {
    func testPresetsMatchTheTrainingPageList() {
        XCTAssertEqual(StrumRhythm.allPresets.map(\.id), ["folk1", "folk2", "eighths", "quarters", "waltz", "chunk", "funk", "island", "ukeBasic",
                                                           "rootStrum", "country", "waltzBass"])
        XCTAssertEqual(StrumRhythm.folk1.code, "D.DU.UDU")
        XCTAssertEqual(StrumRhythm.folk2.code, "D.DUDUDU")
        XCTAssertEqual(StrumRhythm.eighths.code, "DUDUDUDU")
        XCTAssertEqual(StrumRhythm.quarters.code, "D.D.D.D.")
        XCTAssertEqual(StrumRhythm.waltz.code, "D.DUDU")
        XCTAssertEqual(StrumRhythm.chunk.code, "D.XU.UXU")
        XCTAssertEqual(StrumRhythm.funk.code, "DUDUXUDUDUDUXUDU")
        XCTAssertEqual(StrumRhythm.island.code, "D.DU.UDU")
        XCTAssertEqual(StrumRhythm.ukeBasic.code, "D.DUDUDU")
        XCTAssertEqual(StrumRhythm.waltz.beatsPerBar, 3)                      // 3/4
        XCTAssertEqual(StrumRhythm.folk1.beatsPerBar, 4)
        XCTAssertEqual(StrumRhythm.funk.cellsPerBeat, 4)                      // 十六分格
        XCTAssertEqual(StrumRhythm.funk.beatsPerBar, 4)
        XCTAssertEqual(Set(StrumRhythm.allPresets.map(\.id)).count, 12)
    }

    func testDefaultsPerInstrument() {
        XCTAssertEqual(StrumRhythm.presets(for: .guitar).first?.id, "folk1")
        XCTAssertEqual(StrumRhythm.presets(for: .ukulele).first?.id, "island")
        XCTAssertEqual(StrumRhythm.presets(for: .ukulele).map(\.id),
                       ["island", "ukeBasic", "eighths", "quarters", "waltz", "chunk", "funk", "rootStrum", "country", "waltzBass"])
        XCTAssertEqual(StrumRhythm.presets(for: .guitar).map(\.id),
                       ["folk1", "folk2", "eighths", "quarters", "waltz", "chunk", "funk", "rootStrum", "country", "waltzBass"])
        XCTAssertEqual(StrumRhythm.presets(for: .banjoLike).first?.id, "folk1")   // 以后新增的可扫弦乐器用民谣 1 开头
    }

    func testInitValidation() {
        XCTAssertNotNil(StrumRhythm(id: "a", code: "D.DU.UDU"))
        XCTAssertNotNil(StrumRhythm(id: "a", code: "D-DU-UDU"))              // - 当空拍
        XCTAssertEqual(StrumRhythm(id: "a", code: "D-DU-UDU")?.code, "D.DU.UDU")
        XCTAssertEqual(StrumRhythm(id: "a", code: "d.du.udu")?.code, "d.dU.UdU")   // 只有 d 区分大小写：小写 d 是半扫，u 不分大小写
        XCTAssertNil(StrumRhythm(id: "a", code: "D.D"))                       // 格数不是每拍格数的整数倍
        XCTAssertNil(StrumRhythm(id: "a", code: "DUDUDUD", cellsPerBeat: 2))
        XCTAssertNil(StrumRhythm(id: "a", code: "DUQU"))                      // 非法字符
        XCTAssertNil(StrumRhythm(id: "a", code: ""))
        XCTAssertNotNil(StrumRhythm(id: "a", code: "DUDU", cellsPerBeat: 4))   // 一拍十六分
        XCTAssertNil(StrumRhythm(id: "a", code: "DUD", cellsPerBeat: 4))
    }

    func testTimesAndCells() throws {
        let r = StrumRhythm.folk1
        XCTAssertEqual(StrumRhythm.beatDuration(bpm: 120), 0.5, accuracy: 1e-12)
        XCTAssertEqual(r.cellDuration(bpm: 120), 0.25, accuracy: 1e-12)
        XCTAssertEqual(r.barDuration(bpm: 120), 2.0, accuracy: 1e-12)
        XCTAssertEqual(StrumRhythm.waltz.barDuration(bpm: 120), 1.5, accuracy: 1e-12)
        XCTAssertEqual(StrumRhythm.funk.cellDuration(bpm: 120), 0.125, accuracy: 1e-12)
        let strokes = r.strokes(bpm: 120)
        XCTAssertEqual(strokes.map(\.index), [0, 2, 3, 5, 6, 7])              // 空拍不在里面
        XCTAssertEqual(strokes.map(\.time), [0, 0.5, 0.75, 1.25, 1.5, 1.75])
        XCTAssertEqual(strokes.map(\.cell), [.down, .down, .up, .up, .down, .up])
        XCTAssertEqual(StrumRhythm.chunk.strokes(bpm: 120).map(\.cell), [.down, .mute, .up, .up, .mute, .up])
        // 某个时刻在第几格
        XCTAssertEqual(r.cellIndex(at: 0, bpm: 120), 0)
        XCTAssertEqual(r.cellIndex(at: 0.26, bpm: 120), 1)
        XCTAssertEqual(r.cellIndex(at: 1.999, bpm: 120), 7)
        XCTAssertEqual(r.cellIndex(at: 5, bpm: 120), 7)
        XCTAssertEqual(r.cellIndex(at: -1, bpm: 120), 0)
        // 速度夹在 30…300
        XCTAssertEqual(StrumRhythm.beatDuration(bpm: 1), 2.0, accuracy: 1e-12)
        XCTAssertEqual(StrumRhythm.beatDuration(bpm: 9999), 0.2, accuracy: 1e-12)
    }

    func testArrowsAndCountLabels() {
        XCTAssertEqual(StrumRhythm.folk1.arrows, "↓· ↓↑ ·↑ ↓↑")
        XCTAssertEqual(StrumRhythm.chunk.arrows, "↓· ✕↑ ·↑ ✕↑")
        XCTAssertEqual((0..<8).map { StrumRhythm.folk1.countLabel($0) }, ["1", "&", "2", "&", "3", "&", "4", "&"])
        XCTAssertEqual((0..<4).map { StrumRhythm.funk.countLabel($0) }, ["1", "e", "&", "a"])
    }

    func testVelocities() {
        let r = StrumRhythm.folk1
        XCTAssertGreaterThan(r.velocity(ofCell: 0), r.velocity(ofCell: 2))        // 第 1 下最重
        XCTAssertGreaterThan(r.velocity(ofCell: 2), r.velocity(ofCell: 3))        // 拍点下扫 > 上扫
        XCTAssertEqual(r.velocity(ofCell: 1), 0)                                  // 空拍
        XCTAssertGreaterThan(StrumRhythm.eighths.velocity(ofCell: 2), StrumRhythm.eighths.velocity(ofCell: 3))
    }
}


final class StrumCellTests: XCTestCase {
    private let guitar = InstrumentLibrary.guitar
    private let ukulele = InstrumentLibrary.ukulele

    private func voicing(_ root: String, _ type: ChordType = .major, _ inst: Instrument? = nil, index: Int = 0) -> (Chord, ChordVoicing) {
        let c = Chord(root, type)!
        return (c, ChordLibrary.voicings(for: c, instrument: inst ?? guitar)[index])
    }
    private func strings(_ v: ChordVoicing, _ c: Chord, _ cell: StrumCell) -> [Int] {
        RhythmStrum.strings(for: v, cell: cell, rootPitchClass: c.root)
    }

    // MARK: 记号与解析

    func testCellsAndRawValues() {
        XCTAssertEqual(StrumCell.bass.rawValue, "B")
        XCTAssertEqual(StrumCell.down.rawValue, "D")
        XCTAssertEqual(StrumCell.downTreble.rawValue, "d")
        XCTAssertEqual(StrumCell.up.rawValue, "U")
        XCTAssertEqual(StrumCell.mute.rawValue, "X")
        XCTAssertEqual(StrumCell.rest.rawValue, ".")
        XCTAssertEqual(StrumCell.allCases.count, 6)
        XCTAssertTrue([StrumCell.bass, .down, .downTreble, .up, .mute].allSatisfy(\.isStroke))
        XCTAssertFalse(StrumCell.rest.isStroke)
        XCTAssertEqual(Set(StrumCell.allCases.map(\.arrow)).count, 6)           // 文字箭头互不相同
        // 旧成员名仍然可用
        XCTAssertEqual([StrumCell.down, .up, .mute, .rest].map(\.rawValue), ["D", "U", "X", "."])
    }

    func testOnlyDAndLowercaseDAreCaseSensitive() {
        XCTAssertEqual(StrumCell(typed: "D"), .down)
        XCTAssertEqual(StrumCell(typed: "d"), .downTreble)
        for (a, b) in [("B", "b"), ("U", "u"), ("X", "x")] { XCTAssertEqual(StrumCell(typed: Character(a)), StrumCell(typed: Character(b))) }
        XCTAssertEqual(StrumCell(typed: "b"), .bass)
        XCTAssertEqual(StrumCell(typed: "u"), .up)
        XCTAssertEqual(StrumCell(typed: "x"), .mute)
        XCTAssertEqual(StrumCell(typed: "-"), .rest)
        XCTAssertEqual(StrumCell(typed: "."), .rest)
        XCTAssertEqual(StrumCell(typed: "Ｄ"), .down)               // 全角
        XCTAssertEqual(StrumCell(typed: "ｄ"), .downTreble)
        XCTAssertNil(StrumCell(typed: "Z"))
        let p = StrumInput.parse("BbDdUuXx-.", cellsPerBeat: 2)
        XCTAssertEqual(p.cells, [.bass, .bass, .down, .downTreble, .up, .up, .mute, .mute, .rest, .rest])
        XCTAssertEqual(p.normalized, "BBDdUUXX..")
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(StrumInput.parse("B.dUB.dU", cellsPerBeat: 2).normalized, "B.dUB.dU")
        XCTAssertEqual(StrumInput.parse("b.dub.du", cellsPerBeat: 2).normalized, "B.dUB.dU")        // 小写：d 仍是半扫
        XCTAssertEqual(StrumInput.parse("B.DUB.DU", cellsPerBeat: 2).cells[2], .down)               // 大写 D 是全扫
        XCTAssertEqual(StrumInput.parse("B.dUB.dZ", cellsPerBeat: 2).failure, .invalidCharacters)
        XCTAssertEqual(StrumInput.parse("B.dUB.dZ", cellsPerBeat: 2).tokens.map(\.isValid).last, false)
    }

    func testLegacySavedRhythmsKeepTheirMeaning() throws {
        // 旧版本存的 code 一直是大写（规范写法），读出来含义不变；万一有小写 d，迁移成 D，保持原来的效果
        let legacy = Data(#"[{"id":"A","name":"我的","code":"D.DU.UDU","cellsPerBeat":2},{"id":"B","name":"","code":"d.du.udu","cellsPerBeat":2}]"#.utf8)
        let list = try JSONDecoder().decode([CustomStrumRhythm].self, from: legacy)
        XCTAssertEqual(list.map(\.code), ["D.DU.UDU", "D.DU.UDU"])
        XCTAssertEqual(list[0].rhythm?.cells, StrumRhythm.folk1.cells)
        XCTAssertEqual(list[1].rhythm?.cells, StrumRhythm.folk1.cells)
        // 新格式写版本号，再读不会把小写 d（半扫）改成 D
        let fresh = CustomStrumRhythm(name: "乡村", code: "B.dUB.dU")
        let data = try JSONEncoder().encode(fresh)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"v\":2"))
        XCTAssertEqual(try JSONDecoder().decode(CustomStrumRhythm.self, from: data).code, "B.dUB.dU")
        XCTAssertEqual(try JSONDecoder().decode(CustomStrumRhythm.self, from: data).rhythm?.cells[2], .downTreble)
    }

    // MARK: 预设

    func testNewPresets() {
        XCTAssertEqual(StrumRhythm.rootStrum.code, "B.D.B.D.")
        XCTAssertEqual(StrumRhythm.rootStrum.beatsPerBar, 4)
        XCTAssertEqual(StrumRhythm.rootStrum.cells.filter { $0 == .bass }.count, 2)
        XCTAssertEqual(StrumRhythm.country.code, "B.dUB.dU")
        XCTAssertEqual(StrumRhythm.country.cellsPerBeat, 2)
        XCTAssertEqual(StrumRhythm.country.beatsPerBar, 4)
        XCTAssertEqual(StrumRhythm.waltzBass.code, "B.d.d.")
        XCTAssertEqual(StrumRhythm.waltzBass.beatsPerBar, 3)                  // 3/4
        XCTAssertEqual(StrumRhythm.rootStrum.title, "根音扫弦")
        XCTAssertEqual(StrumRhythm.country.title, "乡村")
        XCTAssertEqual(StrumRhythm.waltzBass.title, "华尔兹根音")
        // 原有预设一个字符都没变
        XCTAssertEqual([StrumRhythm.folk1, .folk2, .eighths, .quarters, .waltz, .chunk, .funk, .island, .ukeBasic].map(\.code),
                       ["D.DU.UDU", "D.DUDUDU", "DUDUDUDU", "D.D.D.D.", "D.DUDU", "D.XU.UXU", "DUDUXUDUDUDUXUDU", "D.DU.UDU", "D.DUDUDU"])
        XCTAssertEqual(StrumRhythm.preset(id: "country"), .country)
    }

    func testBassAndTrebleVelocities() {
        let r = StrumRhythm.country                       // B.dUB.dU
        XCTAssertGreaterThan(r.velocity(ofCell: 0), r.velocity(ofCell: 4))     // 第一个根音最重
        XCTAssertGreaterThan(r.velocity(ofCell: 4), 1.0)                       // 根音力度略重
        XCTAssertLessThan(r.velocity(ofCell: 2), 1.0)                          // 半扫轻一些
        XCTAssertGreaterThan(r.velocity(ofCell: 2), r.velocity(ofCell: 3))     // 半扫下扫比上扫重
        XCTAssertEqual(r.velocity(ofCell: 1), 0)
    }

    // MARK: 每种记号拨哪些弦

    func testStringsPerCellOnGuitarC() {
        let (c, v) = voicing("C")                                      // x32010：1…5 弦发声，根音弦是 5 弦（序号 1）
        XCTAssertEqual(RhythmStrum.rootString(of: v, rootPitchClass: c.root), 1)
        XCTAssertEqual(strings(v, c, .bass), [1])
        XCTAssertEqual(strings(v, c, .down), [1, 2, 3, 4, 5])           // 全扫：从根音弦扫到 1 弦
        XCTAssertEqual(strings(v, c, .downTreble), [2, 3, 4, 5])         // 半扫：高音 4 根（1–4 弦），低到高
        XCTAssertEqual(strings(v, c, .up), [5, 4, 3, 2])                 // 上扫：从 1 弦往回
        XCTAssertEqual(strings(v, c, .mute), [1, 2, 3, 4, 5])
        XCTAssertEqual(strings(v, c, .rest), [])
    }

    func testRootStringMovesWithTheChord() {
        let (g, vg) = voicing("G")                                     // 320003：根音在 6 弦（序号 0）
        XCTAssertEqual(strings(vg, g, .bass), [0])
        XCTAssertEqual(strings(vg, g, .down), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(strings(vg, g, .downTreble), [2, 3, 4, 5])
        let (d, vd) = voicing("D")                                     // xx0232：根音在 4 弦（序号 2），只有 4 根弦发声
        XCTAssertEqual(strings(vd, d, .bass), [2])
        XCTAssertEqual(strings(vd, d, .down), [2, 3, 4, 5])
        XCTAssertEqual(strings(vd, d, .downTreble), [3, 4, 5])           // 4 根弦发声时半扫取 3 根（1–3 弦）
        XCTAssertEqual(strings(vd, d, .up), [5, 4, 3])
        let (a, va) = voicing("A")                                     // x02220：根音 5 弦
        XCTAssertEqual(strings(va, a, .bass), [1])
        XCTAssertEqual(strings(va, a, .down), [1, 2, 3, 4, 5])
    }

    func testFullStrumSkipsStringsBelowTheRootString() {
        // C/E 的按法 032010：低 E 弦发声，但根音 C 在 5 弦：全扫从根音弦开始，低 E 不扫
        let c = Chord("C", .major)!
        let tuning = guitar.defaultTuning
        let v = ChordVoicing(frets: [0, 3, 2, 0, 1, 0], fingers: [0, 3, 2, 0, 1, 0], barre: nil, tuning: tuning)
        XCTAssertEqual(RhythmStrum.rootString(of: v, rootPitchClass: c.root), 1)
        XCTAssertEqual(strings(v, c, .down), [1, 2, 3, 4, 5])
        XCTAssertEqual(strings(v, c, .mute), [0, 1, 2, 3, 4, 5])        // 闷音不变：全部发声的弦
        XCTAssertEqual(strings(v, c, .bass), [1])
        // 横按 F：6 弦就是根音弦
        let (f, vf) = voicing("F")
        XCTAssertEqual(strings(vf, f, .bass), [0])
        XCTAssertEqual(strings(vf, f, .down), [0, 1, 2, 3, 4, 5])
    }

    func testStringsPerCellOnUkulele() {
        let (c, v) = voicing("C", .major, ukulele)                      // 0003：G4 C4 E4 C5，根音弦是 C4（序号 1）
        XCTAssertEqual(RhythmStrum.rootString(of: v, rootPitchClass: c.root), 1)
        XCTAssertEqual(strings(v, c, .bass), [1])
        XCTAssertEqual(strings(v, c, .down), [0, 1, 2, 3], "尤克里里的高音 G 比根音弦高，全扫照扫")
        XCTAssertEqual(strings(v, c, .downTreble), [1, 2, 3])            // 尤克里里半扫：1–3 弦
        XCTAssertEqual(strings(v, c, .up), [3, 2, 1])
    }

    // MARK: 发声

    func testBassCellPlaysASingleHeavierNote() {
        let (c, v) = voicing("C")
        let bass = RhythmStrum.playback(voicing: v, cell: .bass, rootPitchClass: c.root, velocity: 1, voice: .guitar)
        XCTAssertEqual(bass.events.count, 1)
        XCTAssertEqual(bass.events[0].string, 1)
        XCTAssertEqual(bass.events[0].pitch.fullName, "C3")
        XCTAssertEqual(bass.events[0].time, 0)
        let down = RhythmStrum.playback(voicing: v, cell: .down, rootPitchClass: c.root, velocity: 1, voice: .guitar)
        XCTAssertGreaterThan(bass.events[0].gain, down.events[0].gain)       // 根音单拨比扫弦里的单根弦响
        XCTAssertNil(bass.events[0].hold)
    }

    func testFullAndHalfStrumsAndTheirTimings() {
        let (c, v) = voicing("C")
        func play(_ cell: StrumCell) -> ChordPlayback { RhythmStrum.playback(voicing: v, cell: cell, rootPitchClass: c.root, voice: .guitar) }
        XCTAssertEqual(play(.down).events.map(\.string), [1, 2, 3, 4, 5])
        XCTAssertEqual(play(.downTreble).events.map(\.string), [2, 3, 4, 5])
        XCTAssertEqual(play(.up).events.map(\.string), [5, 4, 3, 2])
        XCTAssertEqual(play(.rest).events.count, 0)
        // 半扫比全扫轻；弦间隔仍在 8–15 毫秒
        XCTAssertLessThan(play(.downTreble).events[0].gain, play(.down).events[0].gain * 1.5)
        for cell in [StrumCell.down, .downTreble, .up] {
            let t = play(cell).events.map(\.time)
            for (a, b) in zip(t, t.dropFirst()) { XCTAssertTrue((0.008...0.015).contains(b - a), "\(cell)") }
        }
        XCTAssertTrue(play(.mute).events.allSatisfy { $0.hold != nil })
    }

    func testRhythmPlansUseTheRightStrings() throws {
        let (c, v) = voicing("C")
        let plan = PlaybackBuilder.strumRhythmPlan(voicing: v, rhythm: .country, voice: .guitar, a4: 440, rootPitchClass: c.root)
        // B.dUB.dU：格 0 根音、2 半扫下、3 上扫、4 根音、6 半扫下、7 上扫 → 拍位置 0 1 1.5 2 3 3.5
        XCTAssertEqual(plan.items.map(\.beat), [0, 1, 1.5, 2, 3, 3.5])
        XCTAssertEqual(plan.items.map { $0.events.map(\.string) }, [[1], [2, 3, 4, 5], [5, 4, 3, 2], [1], [2, 3, 4, 5], [5, 4, 3, 2]])
        XCTAssertEqual(plan.lengthBeats, 4)
        let waltz = PlaybackBuilder.strumRhythmPlan(voicing: v, rhythm: .waltzBass, voice: .guitar, a4: 440, rootPitchClass: c.root)
        XCTAssertEqual(waltz.lengthBeats, 3)
        XCTAssertEqual(waltz.items.map(\.beat), [0, 1, 2])
        XCTAssertEqual(waltz.items.map { $0.events.count }, [1, 4, 4])
        let rootStrum = PlaybackBuilder.strumRhythmPlan(voicing: v, rhythm: .rootStrum, voice: .guitar, a4: 440, rootPitchClass: c.root)
        XCTAssertEqual(rootStrum.items.map { $0.events.count }, [1, 5, 1, 5])         // 根音、全扫、根音、全扫
        // 不传根音音级：用按法里最低的音（根音在低音的标准按法）
        let inferred = PlaybackBuilder.strumRhythmPlan(voicing: v, rhythm: .rootStrum, voice: .guitar, a4: 440)
        XCTAssertEqual(inferred.items.map { $0.events.map(\.string) }, rootStrum.items.map { $0.events.map(\.string) })
    }

    @MainActor func testChordLibraryPlaysTheSelectedRhythmWithRootNotes() throws {
        let name = "chordkit.cells.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let m = ChordLibraryModel(current: ChordFavorite(instrumentID: "guitar", tuningID: "", root: 7, typeID: "major", voicingIndex: 0),
                                  defaults: d)
        m.audioEnabled = false
        m.select(rhythm: .country)
        let plan = try XCTUnwrap(m.buildPlan(for: m.currentState))               // G：根音弦是 6 弦（序号 0）
        XCTAssertEqual(plan.items.first?.events.map(\.string), [0])
        XCTAssertEqual(plan.items.first?.events.first?.pitch.fullName, "G2")
        XCTAssertEqual(plan.items[1].events.map(\.string), [2, 3, 4, 5])
    }

    @MainActor func testRhythmStrummerCellApi() throws {
        let s = RhythmStrummer()
        s.configuresAudioSession = false
        let c = Chord("C", .major)!
        let v = ChordLibrary.voicings(for: c, instrument: guitar)[0]
        XCTAssertNil(s.strum(v, instrument: guitar, chord: c, cell: .rest, after: 0.1))
        XCTAssertNil(s.strum(v, instrument: InstrumentLibrary.bass, chord: c, cell: .bass, after: 0.1))      // 贝斯不能扫弦
        do { try s.prepare() } catch { throw XCTSkip("这台机器启动不了音频引擎") }
        let hit = try XCTUnwrap(s.strum(v, instrument: guitar, chord: c, cell: .bass, velocity: 1.2, after: 0.2))
        XCTAssertEqual(hit.cell, .bass)
        XCTAssertEqual(hit.events.map(\.string), [1])
        let half = try XCTUnwrap(s.strum(v, instrument: guitar, chord: c, cell: .downTreble, after: 0.5))
        XCTAssertEqual(half.events.count, 4)
        let up = try XCTUnwrap(s.strum(v, instrument: guitar, chord: c, cell: .up, after: 0.7))
        XCTAssertEqual(up.direction, .up)
        XCTAssertEqual(up.events.map(\.string), [5, 4, 3, 2])
        s.stopAll()
        // 旧接口不变
        XCTAssertNotNil(s.strum(v, instrument: guitar, direction: .down, after: 0.1))
        s.stopAll()
    }
}

private extension InstrumentFamily { static var banjoLike: InstrumentFamily { .violin } }

final class StrumInputTests: XCTestCase {
    private func parse(_ s: String, _ cpb: Int = 2) -> StrumParse { StrumInput.parse(s, cellsPerBeat: cpb) }

    func testValidInputs() {
        for text in ["D.DU.UDU", "D . D U . U D U", "D-DU-UDU", "D.du|.udu".replacingOccurrences(of: "du", with: "DU").replacingOccurrences(of: "udu", with: "UDU"), "D.DU|.UDU", "D.DU, .UDU", "Ｄ．ＤＵ．ＵＤＵ"] {
            let p = parse(text)
            XCTAssertTrue(p.isValid, text)
            XCTAssertEqual(p.normalized, "D.DU.UDU", text)
        }
        XCTAssertEqual(parse("D.XU.UXU").cells, StrumRhythm.chunk.cells)
        XCTAssertEqual(parse("DUDUXUDUDUDUXUDU", 4).normalized, "DUDUXUDUDUDUXUDU")
    }

    func testRestCharacters() {
        XCTAssertEqual(parse("D-").cells, [.down, .rest])
        XCTAssertEqual(parse("D.").cells, [.down, .rest])
        XCTAssertEqual(parse("D_").cells, [.down, .rest])
        XCTAssertEqual(parse("DU DU").tokens.count, 4)                  // 空格只用来分组，不占格
    }

    func testRestsCanBeTypedInEveryWay() {
        // 连续的空拍：-、.、全角、以及 iPhone 智能标点合并出来的 – — ‥ …
        XCTAssertEqual(parse("D---").cells, [.down, .rest, .rest, .rest])
        XCTAssertEqual(parse("D...").cells, [.down, .rest, .rest, .rest])
        XCTAssertEqual(parse("D—").cells, [.down, .rest, .rest, .rest])        // --- → —
        XCTAssertEqual(parse("D…").cells, [.down, .rest, .rest, .rest])        // ... → …
        XCTAssertEqual(parse("D–").cells, [.down, .rest, .rest])               // -- → –
        XCTAssertEqual(parse("D‥").cells, [.down, .rest, .rest])               // .. → ‥
        XCTAssertEqual(parse("D...DU.U").normalized, "D...DU.U")
        XCTAssertEqual(parse("D…DU.U").normalized, "D...DU.U")                  // 智能标点之后和原来输入的一样
        XCTAssertEqual(parse("D…DU.U").failure, nil)
        XCTAssertEqual(parse("D…DU.U").tokens.allSatisfy(\.isValid), true)
        XCTAssertEqual(parse("-D.U").cells, [.rest, .down, .rest, .up])         // 开头也行
        XCTAssertEqual(parse("DU DU . . . .").cells.count, 8)
        XCTAssertEqual(parse("D.D.D.D.").cells.filter { $0 == .rest }.count, 4)
    }

    func testInvalidCharactersAreMarked() {
        let p = parse("D.QU.UDZ")
        XCTAssertEqual(p.failure, .invalidCharacters)
        XCTAssertEqual(p.tokens.map(\.isValid), [true, true, false, true, true, true, true, false])
        XCTAssertEqual(p.tokens[2].text, "Q")
        XCTAssertEqual(parse("D1").failure, .invalidCharacters)
        XCTAssertEqual(parse("D↓").failure, .invalidCharacters)
    }

    func testEmpty() {
        for text in ["", "   ", " | , "] { XCTAssertEqual(parse(text).failure, .empty, text) }
    }

    func testWholeBeatsAndLength() {
        XCTAssertEqual(parse("DUD").failure, .notWholeBeats)                // 八分：格数要是 2 的整数倍
        XCTAssertTrue(parse("DU").isValid)                                  // 1 拍
        XCTAssertEqual(parse("DUDUDU", 4).failure, .notWholeBeats)          // 十六分：要是 4 的整数倍
        XCTAssertTrue(parse("DUDU", 4).isValid)
        XCTAssertTrue(parse(String(repeating: "D", count: 16)).isValid)     // 8 拍
        XCTAssertEqual(parse(String(repeating: "D", count: 18)).failure, .tooLong)
        XCTAssertTrue(parse(String(repeating: "D", count: 32), 4).isValid)
        XCTAssertEqual(parse(String(repeating: "D", count: 36), 4).failure, .tooLong)
        XCTAssertEqual(StrumInput.maxBeats, 8)
        XCTAssertEqual(StrumInput.maxSaved, 10)
    }

    func testCustomRhythmConversionAndCodable() throws {
        let c = CustomStrumRhythm(name: "我的", code: "D.DU.UDU")
        let r = try XCTUnwrap(c.rhythm)
        XCTAssertTrue(r.isCustom)
        XCTAssertEqual(r.id, "custom-" + c.id)
        XCTAssertEqual(r.title, "我的")
        XCTAssertEqual(r.beatsPerBar, 4)
        XCTAssertNil(CustomStrumRhythm(code: "DUD").rhythm)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(CustomStrumRhythm.self, from: data), c)
    }
}

final class StrumRhythmPlaybackTests: XCTestCase {
    let guitar = InstrumentLibrary.guitar

    private func voicing(_ root: String = "C") -> ChordVoicing {
        ChordLibrary.voicings(for: Chord(root, .major)!, instrument: guitar)[0]
    }

    func testStrokesBecomeDownUpAndMutedStrums() {
        let v = voicing()                                               // x32010
        let bar = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: StrumRhythm.chunk, voice: .guitar, a4: 440, bpm: 120)
        XCTAssertEqual(bar.length, 2.0, accuracy: 1e-9)
        // D.XU.UXU：下、闷（下）、上、上、闷、上
        let cell = 0.25
        func strum(_ i: Int) -> [PluckEvent] { bar.playback.events.filter { $0.time >= Double(i) * cell && $0.time < Double(i) * cell + 0.1 } }
        XCTAssertEqual(strum(0).map(\.string), [1, 2, 3, 4, 5])
        XCTAssertTrue(strum(1).isEmpty)
        XCTAssertEqual(strum(2).map(\.string), [1, 2, 3, 4, 5])        // 闷音也是下扫的弦序
        XCTAssertEqual(strum(3).map(\.string), [5, 4, 3, 2])
        XCTAssertEqual(strum(7).map(\.string), [5, 4, 3, 2])
        // 闷音的音很快切掉，其余自然衰减
        XCTAssertTrue(strum(2).allSatisfy { $0.hold != nil && $0.hold! < 0.15 })
        XCTAssertTrue(strum(0).allSatisfy { $0.hold == nil })
        XCTAssertTrue(strum(3).allSatisfy { $0.hold == nil })
    }

    func testBarLengthFollowsTheTimeSignatureAndUnit() {
        let v = voicing()
        let waltz = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: .waltz, voice: .guitar, a4: 440, bpm: 100)
        XCTAssertEqual(waltz.length, 3 * 0.6, accuracy: 1e-9)
        let funk = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: .funk, voice: .guitar, a4: 440, bpm: 100)
        XCTAssertEqual(funk.length, 2.4, accuracy: 1e-9)
        XCTAssertEqual(funk.playback.events.map(\.time).max()! , 15 * 0.15, accuracy: 0.06)    // 最后一格 15 × 十六分
        let defaultTempo = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: .folk1, voice: .guitar, a4: 440, bpm: nil)
        XCTAssertEqual(defaultTempo.length, 2.4, accuracy: 1e-9)                            // 没有 BPM 按 100
        for bar in [waltz, funk, defaultTempo] { XCTAssertLessThan(bar.playback.events.map(\.time).max()!, bar.length) }
    }

    func testRenderedBarHasEnergyAtEachStroke() {
        let v = voicing()
        let bar = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: .folk1, voice: .guitar, a4: 440, bpm: 120)
        let rate = 44100.0
        let samples = ChordStrummer.render(bar.playback, sampleRate: rate)
        XCTAssertGreaterThan(samples.count, Int(bar.length * rate))              // 带余音
        func energy(_ a: Double, _ b: Double) -> Float { samples[Int(a * rate)..<Int(b * rate)].map { $0 * $0 }.reduce(0, +) }
        // 第 2 格是空拍：起拍点前后能量不变；第 3 格（0.5 秒）是下扫：能量突然变大
        XCTAssertGreaterThan(energy(0.5, 0.53), energy(0.47, 0.5) * 1.5)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.951 })
    }

    func testMutedStrumsAreShorterThanOpenOnes() {
        let v = voicing()
        let rate = 44100.0
        func tailEnergy(_ rhythm: StrumRhythm) -> Float {
            let bar = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: rhythm, voice: .guitar, a4: 440, bpm: 60)
            let s = ChordStrummer.render(bar.playback, sampleRate: rate)
            // 第一次扫弦之后 0.3~0.9 秒（下一次扫弦在 1 秒）：闷音已经切掉，开放扫弦还在响
            return s[Int(0.3 * rate)..<Int(0.9 * rate)].map { $0 * $0 }.reduce(0, +)
        }
        let open = StrumRhythm(id: "t1", code: "D.D.", cellsPerBeat: 2)!
        let muted = StrumRhythm(id: "t2", code: "X.D.", cellsPerBeat: 2)!
        XCTAssertGreaterThan(tailEnergy(open), tailEnergy(muted) * 20)
    }
}

@MainActor
final class StrumRhythmModelTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "chordkit.rhythm.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultsAndSelectionArePerInstrumentAndRemembered() throws {
        let d = defaults()
        let m = ChordLibraryModel(defaults: d)
        XCTAssertEqual(m.strumRhythm.id, "folk1")
        m.select(rhythm: .waltz)
        XCTAssertEqual(m.strumRhythm.id, "waltz")
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(m.strumRhythm.id, "island")                           // 尤克里里默认岛屿扫弦
        m.select(rhythm: .funk)
        m.select(rhythm: .folk1)                                             // 吉他的预设里没有的…folk1 不在尤克里里列表里
        XCTAssertEqual(m.strumRhythm.id, "funk")
        let again = ChordLibraryModel(defaults: d)
        XCTAssertEqual(again.strumRhythm.id, "waltz")
        again.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(again.strumRhythm.id, "funk")
    }

    func testCycleUsesTheSelectedRhythm() throws {
        let m = ChordLibraryModel(defaults: defaults())
        m.audioEnabled = false
        m.setTempo(120)
        m.select(rhythm: .waltz)                                             // D.DUDU：3 拍
        let c = try XCTUnwrap(m.buildCycle(for: m.currentState))
        XCTAssertEqual(c.length, 1.5, accuracy: 1e-9)
        XCTAssertEqual(c.cells?.count, 6)
        XCTAssertEqual(c.playback.events.count, 3 * 5 + 2 * 4)             // D.DUDU：3 下 × 5 弦 + 2 上 × 4 弦
    }

    func testCustomRhythmsSaveSelectDeleteAndPersist() throws {
        let d = defaults()
        let m = ChordLibraryModel(defaults: d)
        let item = try XCTUnwrap(m.saveCustomRhythm(name: " 我的 ", text: "D - D U - U D U", cellsPerBeat: 2))
        XCTAssertEqual(item.code, "D.DU.UDU")
        XCTAssertEqual(item.name, "我的")
        XCTAssertEqual(m.strumRhythm.id, "custom-" + item.id)
        XCTAssertEqual(m.strumRhythms.count, StrumRhythm.presets(for: .guitar).count + 1)
        XCTAssertEqual(ChordLibraryModel(defaults: d).strumRhythm.id, "custom-" + item.id)
        // 校验
        XCTAssertNil(m.saveCustomRhythm(text: "DUD", cellsPerBeat: 2))
        XCTAssertNil(m.saveCustomRhythm(text: "DUQU", cellsPerBeat: 2))
        XCTAssertNil(m.saveCustomRhythm(text: "", cellsPerBeat: 2))
        XCTAssertNotNil(m.saveCustomRhythm(text: "DUDU", cellsPerBeat: 4))   // 十六分一拍
        // 修改、删除
        let edited = try XCTUnwrap(m.saveCustomRhythm(id: item.id, name: "改", text: "DUDU", cellsPerBeat: 2))
        XCTAssertEqual(edited.id, item.id)
        XCTAssertEqual(m.customRhythms["guitar"]?.first?.code, "DUDU")
        m.deleteCustomRhythm(id: item.id)
        XCTAssertFalse(m.strumRhythms.contains { $0.id == "custom-" + item.id })
        XCTAssertEqual(m.customRhythms["guitar"]?.count, 1)
    }

    func testAtMostTenCustomRhythmsPerInstrument() {
        let m = ChordLibraryModel(defaults: defaults())
        for _ in 0..<10 { XCTAssertNotNil(m.saveCustomRhythm(text: "D.DU", cellsPerBeat: 2)) }
        XCTAssertFalse(m.canAddCustomRhythm)
        XCTAssertNil(m.saveCustomRhythm(text: "D.DU", cellsPerBeat: 2))
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertTrue(m.canAddCustomRhythm)                                  // 按乐器分别保存
        XCTAssertTrue(m.strumRhythms.allSatisfy { !$0.isCustom })
    }

    func testBassHasNoStrumRhythm() {
        let m = ChordLibraryModel(current: ChordFavorite(instrumentID: "bass", tuningID: "", root: 0, typeID: "major", voicingIndex: 0),
                                  defaults: defaults())
        m.audioEnabled = false
        XCTAssertFalse(m.supportsStrum)
        m.previewRhythm(text: "D.DU", cellsPerBeat: 2)                       // 不会崩
        XCTAssertNil(m.playingCell())
    }

    func testPlayingCellIsNilWhenNotPlaying() {
        let m = ChordLibraryModel(defaults: defaults())
        XCTAssertNil(m.playingCell())
    }

    // MARK: 按乐器大类保存（训练页和和弦库共用，各自可以选不同的乐器）

    func testSavingForAnotherFamilyGoesToThatFamilysList() throws {
        let d = defaults()
        let m = ChordLibraryModel(defaults: d)               // 和弦库当前是吉他
        let uke = try XCTUnwrap(m.saveCustomRhythm(name: "岛", text: "D.DU.UDU", cellsPerBeat: 2, family: .ukulele))
        XCTAssertEqual(m.customRhythms(for: .ukulele).map(\.id), [uke.id])
        XCTAssertTrue(m.customRhythms(for: .guitar).isEmpty, "不能进错乐器的列表")
        XCTAssertEqual(m.strumRhythms(for: .ukulele).last?.id, "custom-" + uke.id)
        XCTAssertFalse(m.strumRhythms(for: .guitar).contains { $0.isCustom })
        // 默认选中的是它（对尤克里里）；吉他的选择没变
        XCTAssertEqual(m.strumRhythm.id, "folk1")
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(m.strumRhythm.id, "custom-" + uke.id)
        // 持久化
        XCTAssertEqual(ChordLibraryModel(defaults: d).customRhythms(for: .ukulele).count, 1)
    }

    func testSelectFalseLeavesTheChordLibrarySelectionAlone() throws {
        let m = ChordLibraryModel(defaults: defaults())
        m.select(rhythm: .eighths)
        let saved = try XCTUnwrap(m.saveCustomRhythm(text: "D.DU", cellsPerBeat: 2, family: .guitar, select: false))
        XCTAssertEqual(m.strumRhythm.id, "eighths")
        XCTAssertEqual(m.customRhythms(for: .guitar).count, 1)
        // 默认（不指定乐器、select 默认 true）行为和以前一样：存进当前乐器并选中
        let second = try XCTUnwrap(m.saveCustomRhythm(text: "DUDU", cellsPerBeat: 2))
        XCTAssertEqual(m.strumRhythm.id, "custom-" + second.id)
        XCTAssertNotEqual(saved.id, second.id)
    }

    func testPerFamilyLimitEditAndDelete() throws {
        let m = ChordLibraryModel(defaults: defaults())
        for _ in 0..<10 { XCTAssertNotNil(m.saveCustomRhythm(text: "D.DU", cellsPerBeat: 2, family: .ukulele)) }
        XCTAssertFalse(m.canAddCustomRhythm(for: .ukulele))
        XCTAssertTrue(m.canAddCustomRhythm(for: .guitar))
        XCTAssertTrue(m.canAddCustomRhythm)                                  // 当前乐器（吉他）还没满
        XCTAssertNil(m.saveCustomRhythm(text: "D.DU", cellsPerBeat: 2, family: .ukulele))
        // 修改已有的（指定乐器）
        let first = try XCTUnwrap(m.customRhythms(for: .ukulele).first)
        let edited = try XCTUnwrap(m.saveCustomRhythm(id: first.id, name: "改", text: "DUDU", cellsPerBeat: 2, family: .ukulele))
        XCTAssertEqual(edited.id, first.id)
        XCTAssertEqual(m.customRhythms(for: .ukulele).first?.code, "DUDU")
        // 按乐器删除；选中的被删时回到预设
        m.select(instrument: InstrumentLibrary.ukulele)
        m.select(rhythm: try XCTUnwrap(first.rhythm))
        m.select(instrument: InstrumentLibrary.guitar)
        m.deleteCustomRhythm(id: first.id, family: .ukulele)
        XCTAssertEqual(m.customRhythms(for: .ukulele).count, 9)
        XCTAssertTrue(m.canAddCustomRhythm(for: .ukulele))
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(m.strumRhythm.id, "island")
    }

    func testPreviewForAnotherFamilyDoesNotCrash() {
        let m = ChordLibraryModel(defaults: defaults())
        m.audioEnabled = false
        m.previewRhythm(text: "D.DU", cellsPerBeat: 2, family: .ukulele)
        m.previewRhythm(text: "D.DU", cellsPerBeat: 2, family: .bass)         // 不能扫弦：什么都不做
        m.previewRhythm(text: "D.D", cellsPerBeat: 2, family: .guitar)        // 不合格：什么都不做
    }

    func testEditorIsPublicAndReusable() {
        let m = ChordLibraryModel(defaults: defaults())
        var saved: CustomStrumRhythm?
        _ = CustomRhythmEditor(model: m, family: .ukulele, editing: nil, palette: .light, strings: .zhHans,
                               selectsOnSave: false, onSave: { saved = $0 }, onClose: {})
        _ = CustomRhythmEditor(model: m, onClose: {})                        // 只传必需的参数
        XCTAssertNil(saved)
    }
}

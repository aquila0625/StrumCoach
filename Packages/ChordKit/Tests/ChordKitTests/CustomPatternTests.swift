import XCTest
import TunerKit
@testable import ChordKit

final class ArpeggioInputTests: XCTestCase {
    private func parse(_ s: String, strings: Int = 6) -> ArpeggioParse { ArpeggioInput.parse(s, stringCount: strings) }
    private func nums(_ list: [Int]) -> [ArpeggioStep] { list.map { .string($0) } }

    func testRunTogetherAndSeparated() {
        for text in ["53231323", "5 3 2 3 1 3 2 3", "5,3，2、3.1;3/2|3", "5 3\t2\n3  1 3 2 3"] {
            let p = parse(text)
            XCTAssertTrue(p.isValid, text)
            XCTAssertEqual(p.steps, nums([5, 3, 2, 3, 1, 3, 2, 3]), text)
            XCTAssertEqual(p.normalized, "5 3 2 3 1 3 2 3")
        }
    }

    func testDashAndZeroAreRests() {
        // - 和 0 都是空拍：不弹、占一个音的时值
        XCTAssertEqual(parse("5032").steps, [.string(5), .rest, .string(3), .string(2)])
        XCTAssertEqual(parse("5-3-2-").steps, [.string(5), .rest, .string(3), .rest, .string(2), .rest])
        XCTAssertEqual(parse("5032 1032").steps, [.string(5), .rest, .string(3), .string(2), .string(1), .rest, .string(3), .string(2)])
        XCTAssertEqual(parse("5 - 3 2").steps, [.string(5), .rest, .string(3), .string(2)])       // 空格只分隔，空拍照样算一拍
        XCTAssertEqual(parse("-5 3").steps, [.rest, .string(5), .string(3)])                      // 开头的空拍
        XCTAssertEqual(parse("5 3 2 - -").steps, [.string(5), .string(3), .string(2), .rest, .rest])
        let p = parse("5-3-2-")
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(p.normalized, "5 - 3 - 2 -")                                               // 规范写法：空格隔开，空拍写 -
        XCTAssertEqual(p.tokens.map(\.isValid), [Bool](repeating: true, count: 6))
        XCTAssertEqual(p.tokens.map(\.text), ["5", "-", "3", "-", "2", "-"])                        // 0 和 - 在预览里都显示成 -
        XCTAssertEqual(parse("50").tokens.map(\.text), ["5", "-"])
        // 全角的短横、减号也认
        XCTAssertEqual(parse("5－3−2").steps, [.string(5), .rest, .string(3), .rest, .string(2)])
        XCTAssertEqual(parse("Ｒ０３").steps, [.root, .rest, .string(3)])
    }

    func testSmartPunctuationDoesNotEatConsecutiveRests() {
        // iPhone 的智能标点把 -- 换成 –、--- 换成 —：按原来的个数还原
        XCTAssertEqual(parse("5–3").steps, [.string(5), .rest, .rest, .string(3)])
        XCTAssertEqual(parse("5—3").steps, [.string(5), .rest, .rest, .rest, .string(3)])
        XCTAssertEqual(parse("5--3").steps, parse("5–3").steps)
        XCTAssertEqual(parse("5---3").steps, parse("5—3").steps)
        XCTAssertTrue(parse("5–3").isValid)
    }

    func testRestsCountTowardsTheLengthButAnAllRestPatternIsEmpty() {
        XCTAssertEqual(parse("---").failure, .empty)
        XCTAssertEqual(parse("0 0 0").failure, .empty)
        XCTAssertEqual(parse("- - 5").failure, nil)
        XCTAssertTrue(parse("5" + String(repeating: "-", count: 31)).isValid)             // 32 步（含空拍）
        XCTAssertEqual(parse("5" + String(repeating: "-", count: 32)).failure, .tooLong)  // 33 步
    }

    func testRootLetter() {
        let p = parse("R 3 2 1")
        XCTAssertEqual(p.steps, [.root, .string(3), .string(2), .string(1)])
        XCTAssertEqual(p.normalized, "R 3 2 1")
        XCTAssertEqual(parse("r321").steps, [.root, .string(3), .string(2), .string(1)])
        XCTAssertEqual(parse("R R").steps, [.root, .root])
        XCTAssertEqual(parse("Ｒ３２１").steps, [.root, .string(3), .string(2), .string(1)])        // 全角
        XCTAssertEqual(parse("R - 3 -").normalized, "R - 3 -")
    }

    func testEmptyInputs() {
        for text in ["", "   ", " , ; ", "\n"] {
            let p = parse(text)
            XCTAssertEqual(p.failure, .empty, "「\(text)」")
            XCTAssertFalse(p.isValid)
            XCTAssertTrue(p.steps.isEmpty)
        }
    }

    func testOutOfRangeStringsAreMarked() {
        // 尤克里里只有 4 弦：5、6 无效，其余仍然识别
        let p = parse("4 5 1 6", strings: 4)
        XCTAssertEqual(p.failure, .invalidCharacters)
        XCTAssertEqual(p.tokens.map(\.isValid), [true, false, true, false])
        XCTAssertEqual(p.tokens.map(\.text), ["4", "5", "1", "6"])
        XCTAssertEqual(p.steps, nums([4, 1]))
        XCTAssertEqual(parse("7").failure, .invalidCharacters)           // 吉他最多 6
        XCTAssertEqual(parse("9").failure, .invalidCharacters)
        XCTAssertTrue(parse("123456").isValid)
        XCTAssertTrue(ArpeggioInput.parse("12345", stringCount: 5).isValid)    // 5 弦贝斯
        XCTAssertFalse(ArpeggioInput.parse("5", stringCount: 4).isValid)
        XCTAssertTrue(parse("0").steps == [.rest])                         // 0 不再是越界，而是空拍
    }

    func testOtherCharactersAreMarked() {
        let p = parse("5x3 a")
        XCTAssertEqual(p.failure, .invalidCharacters)
        XCTAssertEqual(p.tokens.map(\.text), ["5", "x", "3", "a"])
        XCTAssertEqual(p.tokens.map(\.isValid), [true, false, true, false])
        XCTAssertEqual(parse("12").tokens.map(\.isValid), [true, true])      // 弦号是单个数字：12 → 1 和 2
        XCTAssertEqual(parse("19").tokens.map(\.isValid), [true, false])
        XCTAssertEqual(parse("5😀").failure, .invalidCharacters)
    }

    func testLengthLimits() {
        XCTAssertTrue(parse(String(repeating: "1", count: 32)).isValid)
        XCTAssertEqual(parse(String(repeating: "1", count: 33)).failure, .tooLong)
        XCTAssertEqual(parse("1").failure, nil)                             // 最短 1 个音
        XCTAssertEqual(ArpeggioInput.maxSteps, 32)
        XCTAssertEqual(ArpeggioInput.maxSaved, 10)
    }

    // MARK: 旧数据兼容

    func testLegacySavedPatternsAreMigrated() throws {
        // 旧版本保存的 JSON：没有 v 字段，text 用短横分隔
        let legacy = Data(#"[{"id":"A","name":"我的","text":"5-3-2-1"},{"id":"B","name":"","text":"R-3-2-R"}]"#.utf8)
        let list = try JSONDecoder().decode([CustomArpeggio].self, from: legacy)
        XCTAssertEqual(list.map(\.text), ["5 3 2 1", "R 3 2 R"])
        XCTAssertEqual(list.map(\.name), ["我的", ""])
        // 含义不变：展开后还是同样的弦
        XCTAssertEqual(ArpeggioInput.parse(list[0].text, stringCount: 6).steps, nums([5, 3, 2, 1]))
        XCTAssertEqual(ArpeggioInput.parse(list[1].text, stringCount: 6).steps, [.root, .string(3), .string(2), .root])
        XCTAssertEqual(list[0].pattern(family: .guitar, stringCount: 6)?.digits, "5 3 2 1")
        // 重新编码写上版本号；再解码不会二次迁移（新格式里 "-" 是空拍，不能被当成分隔符吃掉）
        let data = try JSONEncoder().encode(list)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"v\":2"))
        XCTAssertEqual(try JSONDecoder().decode([CustomArpeggio].self, from: data).map(\.text), ["5 3 2 1", "R 3 2 R"])
        let withRest = CustomArpeggio(text: "5 - 3 -")
        let again = try JSONDecoder().decode(CustomArpeggio.self, from: JSONEncoder().encode(withRest))
        XCTAssertEqual(again.text, "5 - 3 -")
        XCTAssertEqual(ArpeggioInput.migratedFromLegacy("5-3-2-1"), "5 3 2 1")
        XCTAssertEqual(ArpeggioInput.migratedFromLegacy("R-3"), "R 3")
    }

    func testCustomArpeggioConvertsToAPattern() throws {
        let c = CustomArpeggio(name: "我的", text: "R 3 - 1")
        let p = try XCTUnwrap(c.pattern(family: .guitar, stringCount: 6))
        XCTAssertTrue(p.isCustom)
        XCTAssertEqual(p.id, "custom-" + c.id)
        XCTAssertEqual(p.digits, "R 3 - 1")
        XCTAssertEqual(p.kind, .custom([.root, .string(3), .rest, .string(1)]))
        XCTAssertEqual(c.displayName, "我的")
        XCTAssertEqual(CustomArpeggio(text: "5 3").displayName, "5 3")
        XCTAssertNil(CustomArpeggio(text: "5 x").pattern(family: .guitar, stringCount: 6))
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(CustomArpeggio.self, from: data), c)
    }
}

final class CustomArpeggioPlaybackTests: XCTestCase {
    let guitar = InstrumentLibrary.guitar
    let ukulele = InstrumentLibrary.ukulele

    private func pattern(_ text: String, family: InstrumentFamily = .guitar) -> ArpeggioPattern {
        CustomArpeggio(text: ArpeggioInput.parse(text, stringCount: 6).normalized).pattern(family: family, stringCount: 6)!
    }
    private func voicing(_ root: String, _ inst: Instrument? = nil) -> (Chord, ChordVoicing) {
        let c = Chord(root, .major)!
        return (c, ChordLibrary.voicings(for: c, instrument: inst ?? guitar)[0])
    }

    func testRootStringIsReplacedPerChord() {
        let p = pattern("R 3 2 1")
        XCTAssertEqual(p.stringNumbers(rootString: 5), [5, 3, 2, 1])
        XCTAssertEqual(p.stringNumbers(rootString: 4), [4, 3, 2, 1])
        XCTAssertEqual(p.stringNumbers(rootString: 6), [6, 3, 2, 1])
        let (cC, vC) = voicing("C"), (cD, vD) = voicing("D"), (cG, vG) = voicing("G")
        let t = guitar.defaultTuning
        XCTAssertEqual(p.steps(voicing: vC, chord: cC, tuning: t), [1, 3, 4, 5])
        XCTAssertEqual(p.steps(voicing: vD, chord: cD, tuning: t), [2, 3, 4, 5])
        XCTAssertEqual(p.steps(voicing: vG, chord: cG, tuning: t), [0, 3, 4, 5])
    }

    func testStringsNotPlayedInTheVoicingAreSkippedButKeepTheRhythm() throws {
        let (c, v) = voicing("D")                                       // xx0232：6、5 弦不弹
        let t = guitar.defaultTuning
        let p = pattern("6 5 4 3 2 1")
        XCTAssertEqual(p.steps(voicing: v, chord: c, tuning: t), [nil, nil, 2, 3, 4, 5])
        let pb = PlaybackBuilder.arpeggio(pattern: p, voicing: v, chord: c, tuning: t, voice: .guitar, a4: 440, interval: 0.25)
        XCTAssertEqual(pb.events.map(\.time), [0.5, 0.75, 1.0, 1.25])    // 前两拍休止，后面的位置不变
        XCTAssertEqual(pb.cycle ?? 0, 1.5, accuracy: 1e-9)               // 周期仍按 6 拍算
        XCTAssertEqual(pb.events.map(\.pitch.fullName), ["D3", "A3", "D4", "F♯4"])
    }

    func testLiteralStringsOnUkulele() {
        let (c, v) = voicing("C", ukulele)                              // 0003
        let t = ukulele.defaultTuning
        let p = pattern("4 3 2 1 2 3", family: .ukulele)
        let pb = PlaybackBuilder.arpeggio(pattern: p, voicing: v, chord: c, tuning: t, voice: .ukulele, a4: 440, interval: 0.25)
        XCTAssertEqual(pb.events.map(\.pitch.fullName), ["G4", "C4", "E4", "C5", "E4", "C4"])
        // R：尤克里里取最低的带根音的弦（C4，3 弦）
        XCTAssertEqual(pattern("R 1", family: .ukulele).steps(voicing: v, chord: c, tuning: t), [1, 3])
    }

    func testRestsAreSilentButTakeTheirTimeSlot() throws {
        let (c, v) = voicing("C")                                      // x32010
        let t = guitar.defaultTuning
        let p = pattern("5 - 3 -")                                      // 5 弦、空、3 弦、空
        let steps = p.steps(voicing: v, chord: c, tuning: t)
        XCTAssertEqual(steps, [1, nil, 3, nil])
        let pb = PlaybackBuilder.arpeggio(pattern: p, voicing: v, chord: c, tuning: t, voice: .guitar, a4: 440, interval: 0.25)
        XCTAssertEqual(pb.events.map(\.time), [0, 0.5])                 // 空拍不发声，但后面的音位置不变
        XCTAssertEqual(pb.events.map(\.pitch.fullName), ["C3", "G3"])
        XCTAssertEqual(pb.cycle ?? 0, 1.0, accuracy: 1e-9)             // 周期仍按 4 拍算
        // 0 和 - 一样；空拍和“当前把位不弹的弦”一样处理
        XCTAssertEqual(pattern("5032").steps(voicing: v, chord: c, tuning: t), [1, nil, 3, 4])
        XCTAssertEqual(pattern("R 6 3").steps(voicing: v, chord: c, tuning: t), [1, nil, 3])       // 6 弦在 C 里不弹 → 也是空拍
        // 一个周期里的步数 = 输入的步数（含空拍）
        XCTAssertEqual(pattern("5-3-2-").stringNumbers(rootString: 5), [5, 0, 3, 0, 2, 0])
    }

    func testRestsInUkuleleAndBassPatterns() throws {
        let c = Chord("C", .major)!
        let uv = ChordLibrary.voicings(for: c, instrument: ukulele)[0]
        let up = pattern("4 - 2 1", family: .ukulele)
        let upb = PlaybackBuilder.arpeggio(pattern: up, voicing: uv, chord: c, tuning: ukulele.defaultTuning, voice: .ukulele, a4: 440, interval: 0.3)
        XCTAssertEqual(upb.events.count, 3)
        for (got, want) in zip(upb.events.map(\.time), [0, 0.6, 0.9]) { XCTAssertEqual(got, want, accuracy: 1e-9) }
        let bt = InstrumentLibrary.bass.defaultTuning
        let positions = try XCTUnwrap(BassPositions.make(chord: c, tuning: bt))
        let bp = pattern("R - R -", family: .bass)
        let bb = try XCTUnwrap(PlaybackBuilder.bassCustom(pattern: bp, chord: c, tuning: bt, positions: positions, voice: .bass, a4: 440, interval: 0.25))
        XCTAssertEqual(bb.events.map(\.time), [0, 0.5])
        XCTAssertEqual(bb.cycle ?? 0, 1.0, accuracy: 1e-9)
    }

    func testBassCustomPlaysTheChordToneOnThatString() throws {
        let c = Chord("C", .major)!
        let t = InstrumentLibrary.bass.defaultTuning
        let positions = try XCTUnwrap(BassPositions.make(chord: c, tuning: t))
        let p = pattern("R 3 R 2", family: .bass)
        let pb = try XCTUnwrap(PlaybackBuilder.bassCustom(pattern: p, chord: c, tuning: t, positions: positions,
                                                          voice: .bass, a4: 440, interval: 0.3))
        XCTAssertEqual(pb.cycle ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertEqual(pb.events.first?.pitch.fullName, "C2")           // R = 根音
        XCTAssertEqual(pb.events.first?.time, 0)
        for e in pb.events {
            XCTAssertTrue(positions.markers.contains { $0.string == e.string && $0.fret == e.fret && $0.pitch == e.pitch })
            XCTAssertTrue(c.pitchClasses.contains(e.pitch.pitchClass))
        }
        // 贝斯弦号：4 弦最粗（E）… 1 弦最细（G）；3 弦是 A 弦（序号 1），取这根弦上品位最低的和弦音
        let onA = positions.markers.filter { $0.string == 1 }.min { $0.fret < $1.fret }
        XCTAssertEqual(pb.events[1].pitch, onA?.pitch)
        // 2 弦是 D 弦（序号 2）
        let onD = positions.markers.filter { $0.string == 2 }.min { $0.fret < $1.fret }
        XCTAssertEqual(pb.events[3].pitch, onD?.pitch)
    }
}

@MainActor
final class CustomArpeggioModelTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "chordkit.custom.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testSaveNormalizesSelectsAndPersists() throws {
        let d = defaults()
        let m = ChordLibraryModel(defaults: d)
        m.audioEnabled = false
        let saved = try XCTUnwrap(m.saveCustomArpeggio(name: "  我的指法 ", text: "5 3 2 1"))
        XCTAssertEqual(saved.text, "5 3 2 1")
        XCTAssertEqual(saved.name, "我的指法")
        XCTAssertEqual(m.arpeggioPattern?.id, "custom-" + saved.id)
        XCTAssertEqual(m.arpeggioPatterns.count, ArpeggioPattern.patterns(for: .guitar).count + 1)
        XCTAssertEqual(m.arpeggioPatterns.last?.digits, "5 3 2 1")
        // 用起来：循环内容就是它
        m.select(playMode: .arpeggio)
        m.setTempo(120)
        let c = try XCTUnwrap(m.buildCycle(for: m.currentState))
        XCTAssertEqual(c.length, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.playback.events.map(\.pitch.fullName), ["C3", "G3", "C4", "E4"])

        let again = ChordLibraryModel(defaults: d)          // 下次进来还在，选中的也还是它
        XCTAssertEqual(again.customArpeggios["guitar"]?.map(\.id), [saved.id])
        XCTAssertEqual(again.arpeggioPattern?.id, "custom-" + saved.id)
    }

    func testValidationUsesTheCurrentInstrument() throws {
        let m = ChordLibraryModel(defaults: defaults())
        XCTAssertTrue(m.validateArpeggio("6 5 R").isValid)
        XCTAssertNil(m.saveCustomArpeggio(text: "9"))
        XCTAssertNil(m.saveCustomArpeggio(text: ""))
        XCTAssertNil(m.saveCustomArpeggio(text: String(repeating: "1", count: 33)))
        XCTAssertTrue(m.customArpeggios["guitar"]?.isEmpty ?? true)
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertFalse(m.validateArpeggio("6 5 R").isValid)                // 尤克里里只有 4 弦
        XCTAssertTrue(m.validateArpeggio("4 3 2 1 R").isValid)
        XCTAssertNil(m.saveCustomArpeggio(text: "5"))
        let saved = try XCTUnwrap(m.saveCustomArpeggio(text: "4 3 2 1"))
        XCTAssertEqual(saved.displayName, "4 3 2 1")                       // 没起名就用数字串
        // 按乐器分别保存：吉他那边看不到
        m.select(instrument: InstrumentLibrary.guitar)
        XCTAssertTrue(m.arpeggioPatterns.allSatisfy { !$0.isCustom })
        XCTAssertEqual(m.customArpeggios["ukulele"]?.count, 1)
    }

    func testAtMostTenPerInstrument() throws {
        let m = ChordLibraryModel(defaults: defaults())
        for i in 1...10 { XCTAssertNotNil(m.saveCustomArpeggio(text: "5 3 \(min(i, 6))"), "第 \(i) 个") }
        XCTAssertFalse(m.canAddCustomArpeggio)
        XCTAssertNil(m.saveCustomArpeggio(text: "1 2 3"))
        XCTAssertEqual(m.customArpeggios["guitar"]?.count, 10)
        // 修改已有的不受限制
        let first = try XCTUnwrap(m.customArpeggios["guitar"]?.first)
        let edited = try XCTUnwrap(m.saveCustomArpeggio(id: first.id, name: "改名", text: "1 2 3"))
        XCTAssertEqual(edited.id, first.id)
        XCTAssertEqual(m.customArpeggios["guitar"]?.first?.name, "改名")
        XCTAssertEqual(m.customArpeggios["guitar"]?.first?.text, "1 2 3")
        XCTAssertEqual(m.customArpeggios["guitar"]?.count, 10)
        // 删除之后又能加
        m.deleteCustomArpeggio(id: first.id)
        XCTAssertTrue(m.canAddCustomArpeggio)
        XCTAssertNotNil(m.saveCustomArpeggio(text: "6 5 4"))
    }

    func testDeletingTheSelectedOneFallsBackToThePreset() throws {
        let d = defaults()
        let m = ChordLibraryModel(defaults: d)
        let item = try XCTUnwrap(m.saveCustomArpeggio(text: "5 3 2 1 2 3"))
        XCTAssertTrue(m.arpeggioPattern?.isCustom ?? false)
        m.deleteCustomArpeggio(id: item.id)
        XCTAssertEqual(m.arpeggioPattern?.id, "g-5321")
        XCTAssertTrue(m.customArpeggios["guitar"]?.isEmpty ?? false)
        XCTAssertTrue(ChordLibraryModel(defaults: d).customArpeggios["guitar"]?.isEmpty ?? true)
    }

    func testBassCanUseCustomPatterns() throws {
        let m = ChordLibraryModel(current: ChordFavorite(instrumentID: "bass", tuningID: "", root: 0, typeID: "major", voicingIndex: 0),
                                  defaults: defaults())
        XCTAssertFalse(m.supportsStrum)
        XCTAssertEqual(m.arpeggioPattern?.id, "b-rfof")
        XCTAssertNil(m.saveCustomArpeggio(text: "5"))                      // 贝斯默认 4 弦
        XCTAssertNotNil(m.saveCustomArpeggio(text: "R 3 2 R"))
        m.setTempo(120)
        let c = try XCTUnwrap(m.buildCycle(for: m.currentState))
        XCTAssertEqual(c.length, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.playback.events.first?.pitch.fullName, "C2")
    }
}

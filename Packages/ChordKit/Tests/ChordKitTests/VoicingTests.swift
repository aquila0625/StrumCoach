import XCTest
import TunerKit
@testable import ChordKit

final class VoicingTests: XCTestCase {
    let guitar = InstrumentLibrary.guitar
    let ukulele = InstrumentLibrary.ukulele

    private func first(_ root: String, _ type: ChordType, _ inst: Instrument) -> ChordVoicing {
        ChordLibrary.voicings(for: Chord(root, type)!, instrument: inst)[0]
    }

    // MARK: 标准按法

    func testStandardGuitarShapes() {
        let expected: [(String, ChordType, [String])] = [
            ("C", .major, ["x32010"]), ("G", .major, ["320003", "320033"]), ("D", .major, ["xx0232"]),
            ("A", .major, ["x02220"]), ("E", .major, ["022100"]),
            ("A", .minor, ["x02210"]), ("E", .minor, ["022000"]), ("D", .minor, ["xx0231"]),
            ("F", .major, ["133211"]),
            ("C", .major7, ["x32000"]), ("G", .dominant7, ["320001"]),
            ("B", .minor, ["x24432"]), ("F#", .minor, ["244222"]), ("B", .major, ["x24442"]),
            ("D", .dominant7, ["xx0212"]), ("E", .dominant7, ["020100"]), ("A", .dominant7, ["x02020"]),
            ("A", .minor7, ["x02010"]), ("D", .minor7, ["xx0211"]),
        ]
        for (root, type, shapes) in expected {
            let v = first(root, type, guitar)
            XCTAssertTrue(shapes.contains(v.shorthand), "吉他 \(root)\(type.symbol) 第一个把位是 \(v.shorthand)，应为 \(shapes)")
        }
    }

    func testStandardUkuleleShapes() {
        let expected: [(String, ChordType, String)] = [
            ("C", .major, "0003"), ("G", .major, "0232"), ("A", .minor, "2000"), ("F", .major, "2010"),
            ("D", .major, "2220"), ("E", .minor, "0432"), ("D", .minor, "2210"), ("G", .dominant7, "0212"),
            ("C", .dominant7, "0001"), ("A", .dominant7, "0100"),
        ]
        for (root, type, shape) in expected {
            XCTAssertEqual(first(root, type, ukulele).shorthand, shape, "尤克里里 \(root)\(type.symbol)")
        }
    }

    func testStandardFingerings() {
        // C = x32010 → 3 指按 5 弦 3 品，2 指按 4 弦 2 品，1 指按 2 弦 1 品
        XCTAssertEqual(first("C", .major, guitar).fingers, [0, 3, 2, 0, 1, 0])
        // G = 320003 → 2 指按 6 弦 3 品，1 指按 5 弦 2 品，3 指按 1 弦 3 品
        XCTAssertEqual(first("G", .major, guitar).fingers, [2, 1, 0, 0, 0, 3])
        // Am = x02210
        XCTAssertEqual(first("A", .minor, guitar).fingers, [0, 0, 2, 3, 1, 0])
        // E = 022100
        XCTAssertEqual(first("E", .major, guitar).fingers, [0, 2, 3, 1, 0, 0])
        // D = xx0232
        XCTAssertEqual(first("D", .major, guitar).fingers, [0, 0, 0, 1, 3, 2])
        // Cmaj7 = x32000、Em = 022000：只按两个音，指号跟着品位走
        XCTAssertEqual(first("C", .major7, guitar).fingers, [0, 3, 2, 0, 0, 0])
        XCTAssertEqual(first("E", .minor, guitar).fingers, [0, 2, 3, 0, 0, 0])
        // 尤克里里 C = 0003 用 3 指，Am = 2000 用 2 指，F = 2010：1 指按 E 弦，2 指按 G 弦
        XCTAssertEqual(first("C", .major, ukulele).fingers, [0, 0, 0, 3])
        XCTAssertEqual(first("A", .minor, ukulele).fingers, [2, 0, 0, 0])
        XCTAssertEqual(first("F", .major, ukulele).fingers, [2, 0, 1, 0])
    }

    func testFMajorIsABarreChord() throws {
        let f = first("F", .major, guitar)
        XCTAssertEqual(f.shorthand, "133211")
        let b = try XCTUnwrap(f.barre)
        XCTAssertEqual(b.fret, 1)
        XCTAssertEqual(b.fromString, 0)
        XCTAssertEqual(b.toString, 5)
        XCTAssertEqual(f.fingers, [1, 3, 4, 2, 1, 1])
        XCTAssertEqual(f.noteNames, ["F", "C", "F", "A", "C", "F"])
        XCTAssertTrue(f.showsNut)
        XCTAssertEqual(f.fingerCount, 4)
    }

    func testNoteNamesPerString() {
        XCTAssertEqual(first("C", .major7, guitar).noteNames, ["", "C", "E", "G", "B", "E"])
        XCTAssertEqual(first("C", .major, ukulele).noteNames, ["G", "C", "E", "C"])
        XCTAssertEqual(first("A", .minor, guitar).noteNames, ["", "A", "E", "A", "C", "E"])
    }

    func testHighPositionShowsFretNumber() throws {
        let list = ChordLibrary.voicings(for: Chord("F#", .major)!, instrument: guitar)
        let high = try XCTUnwrap(list.first { $0.minFret >= 6 })
        XCTAssertEqual(high.baseFret, high.minFret)
        XCTAssertFalse(high.showsNut)
    }

    // MARK: 规则

    /// 独立于生成器的校验：规则写在这里再核对一遍。
    private func assertValid(_ v: ChordVoicing, chord: Chord, tuning: Tuning, rules: VoicingRules,
                             file: StaticString = #filePath, line: UInt = #line) {
        let label = "\(tuning.id) \(chord.name) \(v.shorthand)"
        XCTAssertEqual(v.frets.count, tuning.stringCount, label, file: file, line: line)

        // 跨度 ≤ 4 品（最高品 − 最低品 ≤ 3）
        XCTAssertLessThanOrEqual(v.span, 3, "\(label) 跨度过大", file: file, line: line)
        // 手指 ≤ 4，横按算 1 根
        XCTAssertLessThanOrEqual(v.fingerCount, 4, "\(label) 手指超过 4 根", file: file, line: line)
        for (fret, finger) in zip(v.frets, v.fingers) {
            if fret > 0 { XCTAssertTrue((1...4).contains(finger), "\(label) 按弦没有手指", file: file, line: line) }
            else { XCTAssertEqual(finger, 0, "\(label) 空弦/不弹的弦不该有手指", file: file, line: line) }
        }
        // 同一根手指只能按同一品；不是横按时只能按一根弦
        for finger in 1...4 {
            let idx = v.fingers.indices.filter { v.fingers[$0] == finger }
            XCTAssertLessThanOrEqual(Set(idx.map { v.frets[$0] }).count, 1, "\(label) 一根手指按了两个品", file: file, line: line)
            if idx.count > 1 {
                let b = v.barre
                XCTAssertEqual(b?.finger, finger, "\(label) 一根手指按多根弦但没有横按", file: file, line: line)
                if let b { XCTAssertTrue(idx.allSatisfy { $0 >= b.fromString && $0 <= b.toString }, label, file: file, line: line) }
            }
        }
        // 横按范围内每根弦都在按（>= 横按品位），且横按品位就是最低按弦品
        if let b = v.barre {
            XCTAssertEqual(b.fret, v.minFret, label, file: file, line: line)
            for s in b.fromString...b.toString { XCTAssertGreaterThanOrEqual(v.frets[s], b.fret, "\(label) 横按下有空弦", file: file, line: line) }
        }
        // 不弹的弦只在两端
        let sounding = v.soundingStrings
        XCTAssertFalse(sounding.isEmpty, label, file: file, line: line)
        if let f = sounding.first, let l = sounding.last {
            XCTAssertEqual(sounding.count, l - f + 1, "\(label) 中间有不弹的弦", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(sounding.count, rules.minSounding, label, file: file, line: line)

        // 发出的音全属于和弦音，且包含根音；除可省的五度外全部出现
        let allowed = Set(chord.pitchClasses)
        var heard = Set<Int>()
        for (i, p) in v.pitches.enumerated() {
            if v.frets[i] < 0 { XCTAssertNil(p, label, file: file, line: line); continue }
            let pitch = tuning.strings[i].pitch.transposed(by: v.frets[i])
            XCTAssertEqual(p, pitch, label, file: file, line: line)
            XCTAssertTrue(allowed.contains(pitch.pitchClass), "\(label) 第 \(i) 弦的 \(pitch.name) 不是和弦音", file: file, line: line)
            heard.insert(pitch.pitchClass)
            XCTAssertEqual(v.noteNames[i], ChordRoot.name(pitch.pitchClass), label, file: file, line: line)
        }
        XCTAssertTrue(heard.contains(chord.root), "\(label) 没有根音", file: file, line: line)
        let optional = Set(chord.type.optionalIntervals.map { (chord.root + $0) % 12 })
        for pc in allowed where !heard.contains(pc) {
            XCTAssertTrue(optional.contains(pc), "\(label) 缺少 \(ChordRoot.name(pc))", file: file, line: line)
        }
    }

    func testEveryVoicingOnEveryInstrumentIsValid() {
        var total = 0
        for inst in [guitar, ukulele] {
            let tuning = inst.defaultTuning
            let rules = VoicingRules.rules(for: inst.family)!
            for root in ChordRoot.all {
                for type in ChordType.builtins {
                    let chord = Chord(root: root, type: type)
                    let list = ChordLibrary.voicings(for: chord, instrument: inst)
                    XCTAssertFalse(list.isEmpty, "\(inst.id) \(chord.name) 没有生成任何按法")
                    for v in list { assertValid(v, chord: chord, tuning: tuning, rules: rules); total += 1 }
                    XCTAssertEqual(Set(list.map(\.frets)).count, list.count, "\(inst.id) \(chord.name) 有重复按法")
                    XCTAssertLessThanOrEqual(list.count, ChordLibrary.maxVoicings)
                }
            }
        }
        XCTAssertGreaterThan(total, 1500)
    }

    func testEveryCombinationAlsoWorksInOtherTunings() {
        // 非默认定弦（Drop D、DADGAD、降半音、低音 G 尤克里里）走同一套生成规则
        for inst in [guitar, ukulele] {
            let rules = VoicingRules.rules(for: inst.family)!
            for tuning in inst.tunings {
                for root in ChordRoot.all {
                    for type in ChordType.builtins {
                        let chord = Chord(root: root, type: type)
                        let list = ChordLibrary.voicings(for: chord, instrument: inst, tuning: tuning)
                        XCTAssertFalse(list.isEmpty, "\(inst.id)/\(tuning.id) \(chord.name)")
                        for v in list { assertValid(v, chord: chord, tuning: tuning, rules: rules) }
                    }
                }
            }
        }
    }

    func testGuitarRootInBassFirst() {
        // 吉他：只要存在最低音是根音的按法，前面的就都是（反转型排在后面）
        for root in ChordRoot.all {
            for type in ChordType.builtins {
                let chord = Chord(root: root, type: type)
                let list = ChordLibrary.voicings(for: chord, instrument: guitar)
                let flags = list.map { VoicingGenerator.rootInBass($0, chord: chord) }
                XCTAssertTrue(flags[0], "吉他 \(chord.name) 第一个把位 \(list[0].shorthand) 的最低音不是根音")
            }
        }
    }

    func testOrderingRules() {
        for inst in [guitar, ukulele] {
            let rules = VoicingRules.rules(for: inst.family)!
            for root in ChordRoot.all {
                for type in ChordType.builtins {
                    let chord = Chord(root: root, type: type)
                    let list = ChordLibrary.voicings(for: chord, instrument: inst)
                    let curatedCount = CuratedShapes.shapes(instrumentID: inst.id, tuningID: inst.defaultTuningID, chord: chord).count
                    // 人工校对的按法之后，生成的按法严格按排序键排列
                    let rest = list.dropFirst(curatedCount)
                    let keys = rest.map { VoicingGenerator.sortKey($0, chord: chord, rules: rules) }
                    for (a, b) in zip(keys, keys.dropFirst()) {
                        XCTAssertFalse(b.lexicographicallyPrecedes(a), "\(inst.id) \(chord.name) 排序不对")
                    }
                    // 开放把位排在非开放把位前面（生成部分，且最低音/五度条件相同）
                    let restList = Array(rest)
                    for (i, v) in restList.enumerated() where !v.isOpenPosition {
                        for w in restList[(i + 1)...] where w.isOpenPosition {
                            let kv = VoicingGenerator.sortKey(v, chord: chord, rules: rules)
                            let kw = VoicingGenerator.sortKey(w, chord: chord, rules: rules)
                            XCTAssertTrue(kv[0] != kw[0] || kv[1] != kw[1], "\(inst.id) \(chord.name) 开放把位没有排在前面")
                        }
                    }
                }
            }
        }
    }

    func testOpenPositionComesBeforeHigherPositions() {
        // 吉他 C、尤克里里 G：开放把位在前，之后位置只会越来越高（同位置的看不弹弦数）
        for (chord, inst) in [(Chord("C", .major)!, guitar), (Chord("G", .major)!, ukulele), (Chord("E", .minor)!, guitar)] {
            let list = ChordLibrary.voicings(for: chord, instrument: inst)
            XCTAssertTrue(list[0].isOpenPosition, "\(chord.name) 第一个应是开放把位")
        }
        let list = ChordLibrary.voicings(for: Chord("A", .major)!, instrument: guitar)
        let positions = list.dropFirst().filter { VoicingGenerator.rootInBass($0, chord: Chord("A", .major)!) }.map(\.minFret)
        XCTAssertEqual(positions, positions.sorted())
    }

    func testCuratedShapesAreAllAccepted() {
        // 人工校对表里每一条都必须通过同样的规则；任何一条被丢弃都说明手写错了
        for (key, table) in CuratedShapes.tables {
            let parts = key.split(separator: "/").map(String.init)
            let inst = InstrumentLibrary.instrument(id: parts[0])!
            let tuning = inst.tuning(id: parts[1])!
            let rules = VoicingRules.rules(for: inst.family)!
            for (typeID, byRoot) in table {
                let type = ChordType.type(id: typeID)!
                for (rootName, shapes) in byRoot {
                    let chord = Chord(rootName, type)!
                    for text in shapes {
                        let frets = CuratedShapes.parse(text)
                        XCTAssertNotNil(frets, "\(key) \(chord.name) \(text) 无法解析")
                        XCTAssertNotNil(frets.flatMap { VoicingGenerator.makeVoicing(frets: $0, chord: chord, tuning: tuning, rules: rules) },
                                        "\(key) \(chord.name) 的人工按法 \(text) 不合格")
                    }
                }
            }
        }
    }

    func testCuratedShapesLeadTheList() {
        for (key, table) in CuratedShapes.tables {
            let parts = key.split(separator: "/").map(String.init)
            let inst = InstrumentLibrary.instrument(id: parts[0])!
            for (typeID, byRoot) in table {
                for (rootName, shapes) in byRoot {
                    let chord = Chord(rootName, ChordType.type(id: typeID)!)!
                    let list = ChordLibrary.voicings(for: chord, instrument: inst, tuning: inst.tuning(id: parts[1]))
                    XCTAssertEqual(Array(list.prefix(shapes.count)).map(\.shorthand), shapes, "\(key) \(chord.name)")
                }
            }
        }
    }

    func testUkuleleMayDropTheFifthButPrefersComplete() {
        for root in ChordRoot.all {
            for type in [ChordType.dominant7, .major7, .minor7] {
                let chord = Chord(root: root, type: type)
                let list = ChordLibrary.voicings(for: chord, instrument: ukulele)
                let flags = list.map { VoicingGenerator.omitsOptional($0, chord: chord) }
                // 完整的按法永远排在省略五度的前面
                if let firstOmit = flags.firstIndex(of: true) {
                    XCTAssertFalse(flags[firstOmit...].contains(false), "\(chord.name) 完整按法排在了省略五度的后面")
                }
            }
        }
    }

    func testUnsupportedInstrumentsReturnNothing() {
        let c = Chord("C", .major)!
        XCTAssertTrue(ChordLibrary.voicings(for: c, instrument: InstrumentLibrary.violin).isEmpty)
        XCTAssertTrue(ChordLibrary.voicings(for: c, instrument: InstrumentLibrary.bass).isEmpty)
        XCTAssertFalse(ChordLibrary.supportsFingering(InstrumentLibrary.bass))
        XCTAssertTrue(ChordLibrary.supportsFingering(guitar))
    }

    func testBarreFingerAssigner() {
        // 只用 4 根手指的不需要横按
        XCTAssertNil(FingerAssigner.assign(frets: [-1, 3, 2, 0, 1, 0])?.barre)
        // 6 个按弦音必须横按
        XCTAssertNotNil(FingerAssigner.assign(frets: [1, 3, 3, 2, 1, 1])?.barre)
        // 横按范围里夹着空弦：弹不了
        XCTAssertNil(FingerAssigner.assign(frets: [1, 0, 3, 2, 1, 1]))
        // 需要 5 根手指又没法横按
        XCTAssertNil(FingerAssigner.assign(frets: [1, 2, 3, 4, 5, 0]))
    }

    func testVoicingCodableRoundTrip() throws {
        let v = first("F", .major, guitar)
        let data = try JSONEncoder().encode(v)
        XCTAssertEqual(try JSONDecoder().decode(ChordVoicing.self, from: data), v)
    }
}

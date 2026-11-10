import XCTest
@testable import ChordKit
import TunerKit

final class TheoryTests: XCTestCase {
    func testTwelveRootsAndTenTypes() {
        XCTAssertEqual(ChordRoot.names, ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])
        XCTAssertEqual(ChordType.builtins.map(\.id),
                       ["major", "minor", "dom7", "maj7", "m7", "sus2", "sus4", "dim", "aug", "add9"])
        XCTAssertEqual(Set(ChordType.builtins.map(\.id)).count, 10)
    }

    func testToneSpelling() {
        func tones(_ root: String, _ type: ChordType) -> [String] { Chord(root, type)!.toneNames }
        XCTAssertEqual(tones("C", .major), ["C", "E", "G"])
        XCTAssertEqual(tones("C", .minor), ["C", "D#", "G"])
        XCTAssertEqual(tones("C", .dominant7), ["C", "E", "G", "A#"])
        XCTAssertEqual(tones("C", .major7), ["C", "E", "G", "B"])
        XCTAssertEqual(tones("A", .minor7), ["A", "C", "E", "G"])
        XCTAssertEqual(tones("D", .sus2), ["D", "E", "A"])
        XCTAssertEqual(tones("D", .sus4), ["D", "G", "A"])
        XCTAssertEqual(tones("B", .diminished), ["B", "D", "F"])
        XCTAssertEqual(tones("C", .augmented), ["C", "E", "G#"])
        XCTAssertEqual(tones("C", .add9), ["C", "E", "G", "D"])
        XCTAssertEqual(tones("A#", .major), ["A#", "D", "F"])
    }

    func testNamesAndParsing() {
        XCTAssertEqual(Chord("F#", .minor7)?.name, "F#m7")
        XCTAssertEqual(Chord("C", .major)?.name, "C")
        XCTAssertEqual(Chord("Db", .major)?.rootName, "C#")
        XCTAssertEqual(Chord("B♭", .minor)?.rootName, "A#")
        XCTAssertNil(Chord("H", .major))
        XCTAssertEqual(Chord(root: -1, type: .major).rootName, "B")
    }

    func testEveryTypeStartsAtRootAndIsConsistent() {
        for t in ChordType.builtins {
            XCTAssertEqual(t.intervals.first, 0)
            XCTAssertEqual(t.intervals.count, t.degrees.count)
            XCTAssertEqual(Set(t.pitchClassIntervals).count, t.intervals.count, "\(t.id) 有重复音")
            XCTAssertTrue(t.optionalIntervals.allSatisfy { t.intervals.contains($0) })
        }
    }

    func testTypeLookupAndCodable() throws {
        XCTAssertEqual(ChordType.type(id: "maj7"), .major7)
        let data = try JSONEncoder().encode(Chord("G", .sus4)!)
        XCTAssertEqual(try JSONDecoder().decode(Chord.self, from: data), Chord("G", .sus4)!)
    }
}

final class ChordNamingTests: XCTestCase {
    func testChordNamesFollowNoteNaming() {
        let it = NoteNaming(style: .solfege, languageCode: "it")
        XCTAssertEqual(it.chordName(Chord("D", .minor)!), "Rem")
        XCTAssertEqual(it.chordName(Chord("G", .dominant7)!), "Sol7")
        XCTAssertEqual(it.chordName(Chord("C", .major)!), "Do")
        XCTAssertEqual(it.toneNames(Chord("C", .major7)!), ["Do", "Mi", "Sol", "Si"])
        XCTAssertEqual(NoteNaming.letters.chordName(Chord("C#", .minor7)!), "C♯m7")
        let de = NoteNaming(style: .letters, languageCode: "de")
        XCTAssertEqual(de.chordName(Chord("B", .minor)!), "Hm")
        XCTAssertEqual(de.toneNames(Chord("G", .major)!), ["G", "H", "D"])
    }

    func testPositionLabelsAreLocalized() {
        let s = ChordStrings.current
        let v = ChordLibrary.voicings(for: Chord("F", .major)!, instrument: InstrumentLibrary.guitar)[0]
        XCTAssertFalse(s.positionLabel(v).isEmpty)
        XCTAssertFalse(s.name(ChordType.major).isEmpty)
    }

    // MARK: 和弦记号与升降拼法

    private let letters = NoteNaming.letters

    func testTypeButtonsUseStandardSymbolsWithTheRoot() {
        let expected = ["C", "Cm", "C7", "Cmaj7", "Cm7", "Csus2", "Csus4", "Cdim", "Caug", "Cadd9"]
        XCTAssertEqual(ChordType.builtins.map { letters.chordName(pitchClass: 0, type: $0) }, expected)
        // 换根音时一起变；大三不加后缀，小三是 m
        XCTAssertEqual(ChordType.builtins.map { letters.chordName(pitchClass: 3, type: $0) },
                       ["E♭", "E♭m", "E♭7", "E♭maj7", "E♭m7", "E♭sus2", "E♭sus4", "E♭dim", "E♭aug", "E♭add9"])
        XCTAssertEqual(letters.chordName(pitchClass: 6, type: .minor), "F♯m")
        // 唱名与德语
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "fr").chordName(pitchClass: 2, type: .minor), "Rém")
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "it").chordName(pitchClass: 1, type: .major7), "Do♯maj7")
        XCTAssertEqual(NoteNaming(style: .letters, languageCode: "de").chordName(pitchClass: 10, type: .major), "B")
        XCTAssertEqual(NoteNaming(style: .letters, languageCode: "de").chordName(pitchClass: 11, type: .minor), "Hm")
    }

    func testRootButtonsUseOneCommonSpelling() {
        // 只用常用的一种写法，不再把升降并列（不会同时出现 C♯/D♭）
        let names = ChordRoot.all.map { letters.rootButtonNames(pitchClass: $0) }
        XCTAssertEqual(names, [["C"], ["C♯"], ["D"], ["E♭"], ["E"], ["F"], ["F♯"], ["G"], ["A♭"], ["A"], ["B♭"], ["B"]])
        for n in names { XCTAssertEqual(n.count, 1); XCTAssertFalse(n[0].contains("/")) }
        // 唱名：Do♯ Mi♭ Fa♯ La♭ Si♭
        let it = NoteNaming(style: .solfege, languageCode: "it")
        XCTAssertEqual(ChordRoot.all.map { it.rootName(pitchClass: $0) },
                       ["Do", "Do♯", "Re", "Mi♭", "Mi", "Fa", "Fa♯", "Sol", "La♭", "La", "Si♭", "Si"])
        let fr = NoteNaming(style: .solfege, languageCode: "fr")
        XCTAssertEqual([1, 3, 6, 8, 10].map { fr.rootName(pitchClass: $0) }, ["Do♯", "Mi♭", "Fa♯", "La♭", "Si♭"])
        // 德语：B♭ 记为 B，白键 B 记为 H
        let de = NoteNaming(style: .letters, languageCode: "de")
        XCTAssertEqual(de.rootButtonNames(pitchClass: 10), ["B"])
        XCTAssertEqual(de.rootButtonNames(pitchClass: 11), ["H"])
        XCTAssertEqual([1, 3, 6, 8].map { de.rootName(pitchClass: $0) }, ["C♯", "E♭", "F♯", "A♭"])
    }

    func testEveryBlackKeyChordUsesTheSameSpellingEverywhere() {
        // 按钮、标题、和弦名、组成音、指法图弦下的音名：同一个和弦里写法一致（E♭ 大三是 E♭ G B♭，A♭ 大三是 A♭ C E♭）
        for (root, type, tones) in [(3, ChordType.major, ["E♭", "G", "B♭"]), (8, .major, ["A♭", "C", "E♭"]),
                                    (10, .major, ["B♭", "D", "F"]), (6, .major, ["F♯", "A♯", "C♯"]),
                                    (1, .minor, ["C♯", "E", "G♯"]), (8, .minor, ["A♭", "B", "E♭"])] {
            let chord = Chord(root: root, type: type)
            XCTAssertEqual(letters.toneNames(chord), tones, chord.name)
            XCTAssertEqual(letters.rootName(chord), tones[0])
            XCTAssertEqual(letters.rootButtonNames(pitchClass: root), [tones[0]])
            XCTAssertEqual(letters.chordName(chord), tones[0] + type.symbol)
            for (pc, name) in zip(chord.pitchClasses, tones) { XCTAssertEqual(letters.toneName(pitchClass: pc, in: chord), name) }
        }
    }

    func testRootsUseTheCommonSpelling() {
        let names = ChordRoot.all.map { letters.rootName(pitchClass: $0) }
        XCTAssertEqual(names, ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"])
    }

    func testToneSpellingMatchesTheRoot() {
        func tones(_ root: String, _ type: ChordType) -> [String] { letters.toneNames(Chord(root, type)!) }
        XCTAssertEqual(tones("Eb", .major), ["E♭", "G", "B♭"])
        XCTAssertEqual(tones("Eb", .dominant7), ["E♭", "G", "B♭", "D♭"])
        XCTAssertEqual(tones("Bb", .major7), ["B♭", "D", "F", "A"])
        XCTAssertEqual(tones("Ab", .minor), ["A♭", "B", "E♭"])           // 不写 C♭
        XCTAssertEqual(tones("F#", .major), ["F♯", "A♯", "C♯"])
        XCTAssertEqual(tones("F#", .minor7), ["F♯", "A", "C♯", "E"])
        XCTAssertEqual(tones("F", .minor), ["F", "A♭", "C"])
        XCTAssertEqual(tones("D", .minor), ["D", "F", "A"])
        XCTAssertEqual(tones("G", .dominant7), ["G", "B", "D", "F"])
        // 少见写法（E♯、F♭）退回统一的升号或降号
        XCTAssertEqual(tones("C#", .major), ["C♯", "F", "G♯"])
        XCTAssertEqual(tones("Bb", .diminished), ["B♭", "D♭", "E"])
    }

    func testSpellingIsConsistentForEveryChord() {
        // 每个和弦：组成音的拼法对应的音级正确；不出现重升重降；同一个和弦里不会既有升号又有降号
        for root in ChordRoot.all {
            for type in ChordType.builtins {
                let chord = Chord(root: root, type: type)
                let flats = ChordSpelling.flats(for: chord)
                XCTAssertEqual(flats.count, type.intervals.count)
                let names = letters.toneNames(chord)
                XCTAssertEqual(names.count, chord.pitchClasses.count)
                for (name, pc) in zip(names, chord.pitchClasses) {
                    XCTAssertEqual(Pitch(name + "4")?.pitchClass, pc, "\(chord.name) 的 \(name) 音级不对")
                    XCTAssertFalse(name.contains("♯♯") || name.contains("♭♭"))
                }
                let marks = Set(names.flatMap { $0.filter { $0 == "♯" || $0 == "♭" } })
                // 增三和弦按乐理本来就是 B♭ D F♯ 这样的写法，其余类型不应同时出现升号和降号
                if type.id != ChordType.augmented.id {
                    XCTAssertLessThanOrEqual(marks.count, 1, "\(chord.name) 同时有升号和降号：\(names)")
                }
                XCTAssertEqual(names[0], letters.rootName(chord))
            }
        }
    }

    func testSolfegeAndGermanToneNames() {
        let fr = NoteNaming(style: .solfege, languageCode: "fr")
        XCTAssertEqual(fr.toneNames(Chord("Eb", .major)!), ["Mi♭", "Sol", "Si♭"])
        let de = NoteNaming(style: .letters, languageCode: "de")
        XCTAssertEqual(de.toneNames(Chord("Bb", .major)!), ["B", "D", "F"])
        XCTAssertEqual(de.toneNames(Chord("G", .minor)!), ["G", "B", "D"])      // B♭ 在德语里写作 B
    }

    func testDiagramNoteNamesFollowTheChordSpelling() {
        let chord = Chord("Eb", .major)!
        XCTAssertEqual(letters.toneName(pitchClass: 3, in: chord), "E♭")
        XCTAssertEqual(letters.toneName(pitchClass: 10, in: chord), "B♭")
        XCTAssertEqual(letters.toneName(pitchClass: 7, in: chord), "G")
        XCTAssertEqual(letters.toneName(pitchClass: 6, in: Chord("F#", .major)!), "F♯")
    }
}

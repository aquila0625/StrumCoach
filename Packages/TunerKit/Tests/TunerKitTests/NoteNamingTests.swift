import XCTest
@testable import TunerKit

final class NoteNamingTests: XCTestCase {
    func testLettersMatchOriginalNames() {
        let n = NoteNaming.letters
        for pc in 0..<12 {
            XCTAssertEqual(n.name(pitchClass: pc), Pitch.sharpNames[pc])
            XCTAssertEqual(n.name(pitchClass: pc, useFlats: true), Pitch.flatNames[pc])
        }
        XCTAssertEqual(n.name(pitchClass: 1, ascii: true), "C#")
        XCTAssertEqual(n.fullName(Pitch("A4")!), "A4")
    }

    func testSolfegeSpellingPerLanguage() {
        XCTAssertEqual((0..<7).map { NoteNaming(style: .solfege, languageCode: "it").name(pitchClass: [0, 2, 4, 5, 7, 9, 11][$0]) },
                       ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"])
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "fr").name(pitchClass: 2), "Ré")
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "pt-BR").name(pitchClass: 9), "Lá")
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "ru").name(pitchClass: 7), "Соль")
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "es").name(pitchClass: 1), "Do♯")
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "es").name(pitchClass: 10, useFlats: true), "Si♭")
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "it").fullName(Pitch("A4")!), "La4")
    }

    func testGermanUsesHAndB() {
        let de = NoteNaming(style: .letters, languageCode: "de")
        XCTAssertEqual(de.name(pitchClass: 11), "H")
        XCTAssertEqual(de.name(pitchClass: 10, useFlats: true), "B")
        XCTAssertEqual(de.name(pitchClass: 10), "A♯")
        XCTAssertEqual(de.name(pitchClass: 9), "A")
        // 德语用唱名时不做 H 替换
        XCTAssertEqual(NoteNaming(style: .solfege, languageCode: "de").name(pitchClass: 11), "Si")
    }

    func testDefaultStylePerLanguage() {
        for code in ["fr", "it", "es", "pt-BR", "ru"] {
            XCTAssertEqual(NoteNaming.defaultStyle(forLanguage: code), .solfege, code)
        }
        for code in ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "tr"] {
            XCTAssertEqual(NoteNaming.defaultStyle(forLanguage: code), .letters, code)
        }
    }

    func testLocalizedStringsCoverEveryField() {
        // .current 在测试进程里是英文；每个字段都应该有值
        let s = TunerStrings.current
        for text in [s.title, s.cents, s.inTune, s.flat, s.sharp, s.listening, s.micDenied, s.referencePitch, s.stringsHeader] {
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertFalse(s.name(InstrumentLibrary.guitar).isEmpty)
    }
}

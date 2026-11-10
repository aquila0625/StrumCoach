import XCTest
import TunerKit
@testable import ChordKit

final class QuickKeyTests: XCTestCase {
    private let s = ChordStrings.zhHans

    private func type(_ keys: [QuickKey], ids: [String]) -> String {
        let all = keys
        return ids.reduce("") { text, id in QuickKeys.apply(all.first { $0.id == id }!, to: text) }
    }

    func testArpeggioKeysFollowTheStringCountAndAlwaysHaveRestAndDelete() {
        for (count, digits) in [(6, "123456"), (4, "1234"), (5, "12345")] {
            let rows = QuickKeys.arpeggio(stringCount: count, strings: s)
            let all = rows.flatMap { $0 }
            XCTAssertEqual(rows[0].map(\.title).joined(), digits + "R")
            XCTAssertTrue(all.contains { $0.isRest && $0.text == "-" && $0.label == "空拍" }, "空拍键一定要有")
            XCTAssertTrue(all.contains { $0.isDelete && $0.text == nil && $0.label == "退格" }, "删除键一定要有")
            // 每个键输入的字符都是解析认得的有效字符
            for key in all where key.text != nil {
                XCTAssertTrue(ArpeggioInput.parse(key.text!, stringCount: count).tokens.allSatisfy(\.isValid), key.id)
            }
        }
    }

    func testRhythmKeysHaveRestAndDelete() {
        let rows = QuickKeys.rhythm(strings: s)
        let all = rows.flatMap { $0 }
        XCTAssertEqual(rows[0].map(\.text), ["B", "D", "d", "U", "X"])
        XCTAssertEqual(rows[0].map(\.glyph), [.bass, .down, .downTreble, .up, .mute])
        XCTAssertEqual(rows[0].map(\.caption), ["根音", "全扫", "半扫", "上扫", "闷音"])      // 每个键下面一个字的说明
        XCTAssertEqual(rows[0].map(\.label), ["根音", "全扫", "半扫", "上扫", "闷音"])         // 读屏用同样的名字
        XCTAssertTrue(all.contains { $0.isRest && $0.label == "空拍" })
        XCTAssertTrue(all.contains { $0.isDelete && $0.label == "退格" })
        for key in all where key.text != nil {
            XCTAssertTrue(StrumInput.parse(key.text!, cellsPerBeat: 2).tokens.allSatisfy(\.isValid), key.id)
        }
        XCTAssertEqual(QuickKeys.rhythm(strings: .en).flatMap { $0 }.first { $0.isRest }?.label, "Rest")
    }

    func testTypingWithKeysProducesWhatTheEditorsParse() {
        let a = QuickKeys.arpeggio(stringCount: 6, strings: s).flatMap { $0 }
        let typed = type(a, ids: ["s5", "rest", "s3", "rest", "s2", "rest"])
        XCTAssertEqual(typed, "5-3-2-")
        XCTAssertEqual(ArpeggioInput.parse(typed, stringCount: 6).steps, [.string(5), .rest, .string(3), .rest, .string(2), .rest])
        XCTAssertEqual(ArpeggioInput.parse(type(a, ids: ["r", "rest", "s1", "rest"]), stringCount: 6).steps, [.root, .rest, .string(1), .rest])
        // 删除：一次删一个字符
        XCTAssertEqual(type(a, ids: ["s5", "s3", "del"]), "5")
        XCTAssertEqual(type(a, ids: ["s5", "rest", "del"]), "5")
        XCTAssertEqual(type(a, ids: ["del"]), "")                           // 空的时候删不会出错
        let r = QuickKeys.rhythm(strings: s).flatMap { $0 }
        let rhythm = type(r, ids: ["D", "rest", "rest", "rest", "D", "u", "rest", "u"])
        XCTAssertEqual(rhythm, "D...DU.U")
        XCTAssertEqual(StrumInput.parse(rhythm, cellsPerBeat: 2).normalized, "D...DU.U")
        XCTAssertEqual(StrumInput.parse(rhythm, cellsPerBeat: 2).failure, nil)
        // 乡村：B . d U B . d U，用快捷键输入，d 是半扫（不会被当成 D）
        let country = type(r, ids: ["b", "rest", "d", "u", "b", "rest", "d", "u"])
        XCTAssertEqual(country, "B.dUB.dU")
        XCTAssertEqual(StrumInput.parse(country, cellsPerBeat: 2).cells, StrumRhythm.country.cells)
    }

    @MainActor func testLegendShowsOnlyTheFirstTime() {
        let name = "chordkit.legend.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let m = ChordLibraryModel(defaults: d)
        XCTAssertTrue(m.shouldShowStrumLegend)
        m.markStrumLegendSeen()
        XCTAssertFalse(m.shouldShowStrumLegend)
        XCTAssertFalse(ChordLibraryModel(defaults: d).shouldShowStrumLegend)       // 下次打开不再显示
    }

    func testDeleteSkipsTrailingSeparators() {
        XCTAssertEqual(deletingLastToken("5 3 "), "5 ")
        XCTAssertEqual(deletingLastToken("5 3, "), "5 ")
        XCTAssertEqual(deletingLastToken("5-"), "5")
        XCTAssertEqual(deletingLastToken("D..."), "D..")
        XCTAssertEqual(deletingLastToken(""), "")
        XCTAssertEqual(deletingLastToken("  "), "")
    }
}

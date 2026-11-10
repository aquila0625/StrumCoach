import XCTest
@testable import ChordKit

final class LocalizationTests: XCTestCase {
    private let languages = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "tr", "zh-Hans", "zh-Hant"]

    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ChordKit/Resources/Localizable.xcstrings")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(obj?["strings"] as? [String: [String: Any]])
    }

    /// String Catalog 里每一条都有 12 种语言，占位符个数和原文一致。
    func testEveryStringHasAllTwelveLanguages() throws {
        let strings = try catalog()
        XCTAssertGreaterThan(strings.count, 30)
        for (key, entry) in strings {
            let locs = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]], key)
            XCTAssertEqual(Set(locs.keys), Set(languages), "\(key) 的语言不全")
            let placeholders = key.components(separatedBy: "%").count - 1
            for (lang, loc) in locs {
                let unit = loc["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.isEmpty, "\(key) 缺 \(lang)")
                XCTAssertEqual(value.components(separatedBy: "%").count - 1, placeholders, "\(key) \(lang) 占位符个数不对")
            }
        }
    }

    func testNewPageLabelIsTranslatedAndUsed() throws {
        let strings = try catalog()
        XCTAssertNotNil(strings["第 %lld 个把位，共 %lld 个"])
        XCTAssertEqual(ChordStrings.zhHans.pageLabel(2, 8), "第 2 个把位，共 8 个")
        XCTAssertEqual(ChordStrings.en.pageLabel(2, 8), "Position 2 of 8")
        XCTAssertFalse(ChordStrings.current.pageLabel(2, 8).isEmpty)
    }

    /// 类型按钮读屏念完整名称，写出来的是和弦记号。
    func testTypeNamesForVoiceOverAreFullNames() {
        let s = ChordStrings.zhHans
        XCTAssertEqual(s.name(ChordType.major), "大三和弦")
        XCTAssertEqual(s.name(ChordType.minor), "小三和弦")
        XCTAssertEqual(s.name(ChordType.major7), "大七和弦")
        let current = ChordStrings.current
        for t in ChordType.builtins { XCTAssertFalse(current.name(t).isEmpty) }
    }

    /// 分解指法的说明和新增的界面文字都在 String Catalog 里。
    func testArpeggioTextsAreInTheCatalog() throws {
        let strings = try catalog()
        for p in ArpeggioPattern.all { XCTAssertNotNil(strings[p.summary], "缺 \(p.summary)") }
        for key in ["扫弦", "分解", "弹奏方式", "分解指法", "数字是弦号，5 代表根音弦（当前和弦是 %lld 弦）"] {
            XCTAssertNotNil(strings[key], "缺 \(key)")
        }
        let s = ChordStrings.zhHans
        XCTAssertEqual(s.rootStringNote(4), "数字是弦号，5 代表根音弦（当前和弦是 4 弦）")
        XCTAssertEqual(s.summary(ArpeggioPattern.pattern(id: "g-5321")!), "四拍上行")
        XCTAssertEqual(ChordStrings.en.summary(ArpeggioPattern.pattern(id: "g-5321")!), "Four-beat rise")
        for p in ArpeggioPattern.all { XCTAssertFalse(ChordStrings.current.summary(p).isEmpty) }
    }

    /// 扫弦节奏型的名称、自定义编辑页的文字都在 String Catalog 里。
    func testRhythmAndCustomTextsAreInTheCatalog() throws {
        let strings = try catalog()
        for r in StrumRhythm.allPresets { XCTAssertNotNil(strings[r.title], "缺节奏型名称 \(r.title)") }
        for key in ["自定义…", "自定义指法", "自定义节奏型", "名称", "保存", "取消", "编辑", "删除", "八分", "十六分", "格子单位", "扫弦节奏型",
                    "只能输入 B、D、d、U、X、- 和 .", "最多 %lld 个音", "最多 %lld 拍", "格数要是 %lld 的整数倍", "每种乐器最多保存 %lld 个",
                    "只能输入 1–%lld 的弦号、0 或 -（空拍）和字母 R", "空拍", "退格"] {
            XCTAssertNotNil(strings[key], "缺 \(key)")
        }
        let s = ChordStrings.zhHans, e = ChordStrings.en
        XCTAssertEqual(s.title(.folk1), "民谣 1")
        XCTAssertEqual(e.title(.chunk), "Chuck strum")
        XCTAssertEqual(s.title(StrumRhythm(id: "custom-x", code: "DU", title: "我的")!), "我的")      // 自定义的名字原样显示
        XCTAssertEqual(s.invalidArpeggio(6), "只能输入 1–6 的弦号、0 或 -（空拍）和字母 R")
        XCTAssertEqual(s.restKey, "空拍"); XCTAssertEqual(e.restKey, "Rest"); XCTAssertEqual(e.backspaceKey, "Backspace")
        XCTAssertTrue(s.arpeggioHelp(6).contains("空拍"))
        XCTAssertEqual(e.notWholeBeats(4), "The number of cells must be a multiple of 4")
        for r in StrumRhythm.allPresets { XCTAssertFalse(ChordStrings.current.title(r).isEmpty) }
        for key in ["全扫", "半扫", "上扫", "闷音", "B 只拨根音弦；D 从根音弦扫到 1 弦；d 和 U 只扫高音的 3–4 根弦。",
                    "每个字符一格：B 根音、D 全扫、d 半扫、U 上扫、X 闷音、- 或 . 空拍（D 和 d 分大小写）。空格只用来分组。"] {
            XCTAssertNotNil(strings[key], "缺 \(key)")
        }
        XCTAssertEqual(s.cellFull, "全扫"); XCTAssertEqual(e.cellHalf, "Half"); XCTAssertEqual(ChordStrings.current.cellMute.isEmpty, false)
        XCTAssertEqual(e.title(.country), "Country"); XCTAssertEqual(e.title(.rootStrum), "Root strum")
    }

    /// 速度控件的文字在 String Catalog 里。
    func testTempoTextsAreInTheCatalog() throws {
        let strings = try catalog()
        for key in ["速度", "跟随节拍器", "用节拍器的速度（%lld BPM）", "减慢", "加快", "速度 %lld BPM"] {
            XCTAssertNotNil(strings[key], "缺 \(key)")
        }
        XCTAssertEqual(ChordStrings.zhHans.tempoLabel(70), "速度 70 BPM")
        XCTAssertEqual(ChordStrings.zhHans.followingNote(112), "用节拍器的速度（112 BPM）")
        XCTAssertEqual(ChordStrings.en.tempoLabel(70), "Tempo 70 BPM")
        XCTAssertFalse(ChordStrings.current.tempoLabel(70).isEmpty)
    }
}

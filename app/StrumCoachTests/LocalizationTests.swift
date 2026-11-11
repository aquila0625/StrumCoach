import XCTest
@testable import StrumCoach

/// 多语言资源：12 种语言都打包进 App，每种都有麦克风权限说明和界面文字。
final class LocalizationTests: XCTestCase {
    static let languages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "pt-BR", "it", "ru", "tr"]
    private var app: Bundle { Bundle(for: MetronomeController.self) }

    func testAppShipsAllLanguages() {
        XCTAssertEqual(Set(app.localizations).intersection(Self.languages), Set(Self.languages))
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String, "en", "找不到对应语言时回退英文")
    }

    func testEveryLanguageHasMicrophoneDescriptionAndName() throws {
        for lang in Self.languages {
            let path = try XCTUnwrap(app.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: lang), lang)
            let dict = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], lang)
            XCTAssertFalse(dict["NSMicrophoneUsageDescription", default: ""].isEmpty, lang)
            XCTAssertFalse(dict["CFBundleDisplayName", default: ""].isEmpty, lang)
        }
    }

    func testInterfaceStringsAreTranslated() throws {
        // 抽几条界面文字，确认每种语言的表里都有译文（不是原文）
        for lang in Self.languages where lang != "zh-Hans" {
            let path = try XCTUnwrap(app.path(forResource: lang, ofType: "lproj"), lang)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["节拍器", "训练", "调音器", "和弦库", "我的", "音名显示"] {
                let value = bundle.localizedString(forKey: key, value: "\u{1}", table: nil)
                XCTAssertNotEqual(value, "\u{1}", "\(lang) 缺少 \(key)")
                if lang != "zh-Hant" { XCTAssertNotEqual(value, key, "\(lang) 的 \(key) 没有翻译") }
            }
        }
    }
}

/// 复数：带数量的文案按各语言规则变化（德语 1 Takt / 2 Takte，俄语 1 такт / 2 такта / 5 тактов）。
final class PluralTests: XCTestCase {
    private func format(_ key: String, _ n: Int, _ lang: String) throws -> String {
        let app = Bundle(for: MetronomeController.self)
        let path = try XCTUnwrap(app.path(forResource: lang, ofType: "lproj"), lang)
        let bundle = try XCTUnwrap(Bundle(path: path))
        let pattern = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: pattern, locale: Locale(identifier: lang), n)
    }

    func testBarsInGermanRussianEnglish() throws {
        let cases: [(String, [Int: String])] = [
            ("de", [1: "1 Takt", 2: "2 Takte", 5: "5 Takte"]),
            ("ru", [1: "1 такт", 2: "2 такта", 5: "5 тактов", 21: "21 такт", 22: "22 такта", 11: "11 тактов"]),
            ("en", [1: "1 bar", 2: "2 bars", 5: "5 bars"]),
            ("fr", [1: "1 mesure", 2: "2 mesures"]),
        ]
        for (lang, expected) in cases {
            for (n, text) in expected {
                XCTAssertEqual(try format("%lld 小节", n, lang), text, "\(lang) \(n)")
            }
        }
    }

    /// 训练页的句子把“N 小节”整体嵌进去，所以德语是 “1 Takt stumm”，不是 “1 Takte stumm”。
    func testMuteSummaryUsesSingularForOneBar() throws {
        let app = Bundle(for: MetronomeController.self)
        for (lang, expected) in [("de", "3 Takte hörbar · 1 Takt stumm"), ("ru", "Звучит 3 такта · тишина 1 такт")] {
            let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(app.path(forResource: lang, ofType: "lproj"))))
            let sentence = bundle.localizedString(forKey: "有声 %@ · 静音 %@", value: nil, table: nil)
            let text = String(format: sentence, try format("%lld 小节", 3, lang), try format("%lld 小节", 1, lang))
            XCTAssertEqual(text, expected)
        }
    }
}

/// App 内切换语言：解析规则、选择的保存与恢复。
final class AppLanguageTests: XCTestCase {
    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    func testEveryOptionHasFlagAndShippedLocalization() {
        XCTAssertEqual(AppLanguage.options.map(\.code), LocalizationTests.languages)
        XCTAssertEqual(AppLanguage.options.first { $0.code == "zh-Hant" }?.flag, "🇭🇰", "繁体中文用香港旗")
        for option in AppLanguage.options {
            XCTAssertFalse(option.flag.isEmpty)
            XCTAssertNotNil(Bundle(for: MetronomeController.self).path(forResource: option.code, ofType: "lproj"), option.code)
        }
    }

    func testOverrideAppliesImmediatelyAndPersists() {
        AppLanguage.override = "de"
        XCTAssertEqual(AppLanguage.resolved, "de")
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "AppleLanguages"), ["de"], "下次启动系统也按它加载")
        XCTAssertEqual(String(localized: "节拍器", bundle: .appLanguage, locale: .appLanguage), "Metronom")
        AppLanguage.override = "ru"
        XCTAssertEqual(String(localized: "节拍器", bundle: .appLanguage, locale: .appLanguage), "Метроном")
        AppLanguage.override = "zh-Hans"
        XCTAssertEqual(String(localized: "节拍器", bundle: .appLanguage, locale: .appLanguage), "节拍器")
    }

    func testSystemPreferenceMatching() {
        let all = AppLanguage.options.map(\.code)
        func pick(_ prefs: [String]) -> String {
            UserDefaults.standard.set(prefs, forKey: "AppleLanguages")
            defer { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            return AppLanguage.resolve(available: all)
        }
        XCTAssertEqual(pick(["zh-Hans-US", "en-US"]), "zh-Hans")
        XCTAssertEqual(pick(["zh-TW"]), "zh-Hant")
        XCTAssertEqual(pick(["zh-HK"]), "zh-Hant")
        XCTAssertEqual(pick(["pt-PT"]), "pt-BR")
        XCTAssertEqual(pick(["de-AT"]), "de")
        XCTAssertEqual(pick(["pl-PL", "fr-CA"]), "fr", "跳过不支持的语言")
        XCTAssertEqual(pick(["pl-PL", "nl-NL"]), "en", "都不支持时回退英文")
    }
}

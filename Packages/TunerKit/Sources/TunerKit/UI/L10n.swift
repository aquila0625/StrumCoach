import Foundation

/// 包内文字的本地化。文案在 `Resources/Localizable.xcstrings`（键是简体中文原文）。
///
/// 语言跟随 App（包括 App 内切换的语言）。App 回退到英文时，包里的文字也是英文，而不是包自己的开发语言（简体中文）。
enum L10n {
    /// 当前语言的 lproj。App 内切换语言时 App 会改写自己的 `AppleLanguages`，这里每次查表都按它重新解析，
    /// 所以包里的文字和 App 一起立即切换；规则和 App 的 `AppLanguage.resolve` 一致（都匹配不上用英文）。
    static var bundle: Bundle {
        let prefs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        if let cache, cache.prefs == prefs { return cache.bundle }
        let code = resolve(prefs: prefs, available: Bundle.module.localizations)
        let b = Bundle.module.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        cache = (prefs, code, b)
        return b
    }

    /// 当前语言（用于复数规则和数字格式）。
    static var locale: Locale {
        _ = bundle
        return Locale(identifier: cache?.code ?? "en")
    }

    nonisolated(unsafe) private static var cache: (prefs: [String], code: String, bundle: Bundle)?

    private static func resolve(prefs: [String], available: [String]) -> String {
        for p in prefs {
            if let exact = available.first(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) { return exact }
            let l = Locale(identifier: p)
            let lang = l.language.languageCode?.identifier ?? ""
            if lang == "zh" {
                let hant = l.language.script?.identifier == "Hant" || ["TW", "HK", "MO"].contains(l.region?.identifier ?? "")
                let want = hant ? "zh-Hant" : "zh-Hans"
                if available.contains(want) { return want }
            }
            if !lang.isEmpty, let match = available.first(where: { $0.split(separator: "-").first.map(String.init) == lang }) {
                return match
            }
        }
        return "en"
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }

    /// 数据里的名字（乐器、定弦）按原文查表。
    static func lookup(_ text: String) -> String {
        bundle.localizedString(forKey: text, value: text, table: nil)
    }
}

import Foundation

/// App 内切换界面语言（不跳系统设置）。
///
/// 选择写进 App 自己的 `AppleLanguages`，下次启动系统也按它加载；当次立即生效靠三处：
/// - `String(localized:…, bundle: .appLanguage, locale: .appLanguage)` 从选中语言的 lproj 取文字；
/// - 根视图注入 `\.locale`，SwiftUI 的 `Text("…")` 和数字格式跟着变；
/// - 三个包的 `L10n` 每次查表时读同一个 `AppleLanguages`，所以包里的文字也一起换。
enum AppLanguage {
    struct Option: Identifiable, Hashable {
        let code: String
        /// 国旗。繁体中文用香港旗，英文用美国旗，巴西葡语用巴西旗。
        let flag: String
        /// 用这种语言自己写的名字。
        let nativeName: String
        var id: String { code }
    }

    static let options: [Option] = [
        Option(code: "zh-Hans", flag: "🇨🇳", nativeName: "简体中文"),
        Option(code: "zh-Hant", flag: "🇭🇰", nativeName: "繁體中文"),
        Option(code: "en", flag: "🇺🇸", nativeName: "English"),
        Option(code: "ja", flag: "🇯🇵", nativeName: "日本語"),
        Option(code: "ko", flag: "🇰🇷", nativeName: "한국어"),
        Option(code: "es", flag: "🇪🇸", nativeName: "Español"),
        Option(code: "fr", flag: "🇫🇷", nativeName: "Français"),
        Option(code: "de", flag: "🇩🇪", nativeName: "Deutsch"),
        Option(code: "pt-BR", flag: "🇧🇷", nativeName: "Português (Brasil)"),
        Option(code: "it", flag: "🇮🇹", nativeName: "Italiano"),
        Option(code: "ru", flag: "🇷🇺", nativeName: "Русский"),
        Option(code: "tr", flag: "🇹🇷", nativeName: "Türkçe"),
    ]

    private static let key = "AppleLanguages"
    private static let overrideKey = "appLanguage.override"

    /// 用户在 App 里选的语言；nil 表示跟随系统。
    static var override: String? {
        get { UserDefaults.standard.string(forKey: overrideKey) }
        set {
            let d = UserDefaults.standard
            if let newValue {
                d.set(newValue, forKey: overrideKey)
                d.set([newValue], forKey: key)
            } else {
                d.removeObject(forKey: overrideKey)
                d.removeObject(forKey: key)   // 回到系统（全局域）的语言列表
            }
            cache = nil
        }
    }

    /// 当前实际使用的语言（选中的，或按系统语言列表匹配到的，都匹配不上用英文）。
    static var resolved: String {
        if let cache { return cache.code }
        let code = resolve(available: options.map(\.code))
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
        cache = (code, path.flatMap(Bundle.init(path:)) ?? .main)
        return code
    }

    static var bundle: Bundle {
        _ = resolved
        return cache?.bundle ?? .main
    }

    /// 界面语言 + 用户所在地区（地区影响货币等）。
    static var locale: Locale {
        var c = Locale.Components(identifier: resolved)   // 例如 zh-Hans、pt-BR
        if c.region == nil { c.region = Locale.current.region }
        return Locale(components: c)
    }

    static var current: Option { options.first { $0.code == resolved } ?? options[2] }

    private static var cache: (code: String, bundle: Bundle)?

    /// 按语言偏好列表挑一个支持的语言：先精确匹配，再按语言匹配（zh-TW/HK → 繁体，pt-PT → 巴西葡语），都没有用英文。
    /// 三个包的 `L10n` 用同一套规则。
    static func resolve(available: [String]) -> String {
        let prefs = UserDefaults.standard.stringArray(forKey: key) ?? Locale.preferredLanguages
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
}

extension Bundle {
    /// 当前界面语言的 lproj。
    static var appLanguage: Bundle { AppLanguage.bundle }
}

extension Locale {
    /// 当前界面语言（含用户地区）。
    static var appLanguage: Locale { AppLanguage.locale }
}

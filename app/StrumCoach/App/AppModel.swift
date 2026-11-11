import ChordKit
import Foundation
import MetronomeCore
import Observation
import SwiftData
import SwiftUI
import TunerKit

/// 主题选择：跟随系统、浅色、深色。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "跟随系统", bundle: .appLanguage, locale: .appLanguage)
        case .light: return String(localized: "浅色", bundle: .appLanguage, locale: .appLanguage)
        case .dark: return String(localized: "深色", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    /// 分段按钮上的短名（“系统”“浅色”“深色”）。
    var shortTitle: String {
        switch self {
        case .system: return String(localized: "系统", bundle: .appLanguage, locale: .appLanguage)
        case .light, .dark: return title
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App 级设置：主题、语言、音名。左手模式和标准音分别以和弦库、调音器的模型为准，这里只负责存取。
@MainActor
@Observable
final class AppSettings {
    var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// 音名显示：nil 表示跟随语言默认（法、意、西、葡、俄用唱名，其他用字母）。
    var noteStyleOverride: NoteNaming.Style? {
        didSet { UserDefaults.standard.set(noteStyleOverride?.rawValue, forKey: Keys.noteStyle) }
    }

    /// App 当前实际使用的语言（单 App 语言设置也算在内）。
    /// 当前界面语言（App 内可切换），改动后整个界面立即刷新。
    var language: String? = AppLanguage.override {
        didSet {
            AppLanguage.override = language
            languageCode = AppLanguage.resolved
        }
    }

    /// App 当前实际使用的语言。
    private(set) var languageCode: String = AppLanguage.resolved

    /// 界面语言的 Locale（观察 languageCode，切换语言时根视图跟着刷新）。
    var locale: Locale {
        _ = languageCode
        return AppLanguage.locale
    }

    var noteStyle: NoteNaming.Style { noteStyleOverride ?? NoteNaming.defaultStyle(forLanguage: languageCode) }

    /// 注入调音器、和弦库的音名写法。
    var noteNaming: NoteNaming { NoteNaming(style: noteStyle, languageCode: languageCode) }

    /// 当前语言的名称（用它自己的语言写，例如 “Deutsch”）。
    var languageName: String {
        AppLanguage.options.first { $0.code == languageCode }?.nativeName ?? languageCode
    }

    private enum Keys {
        // 和启动参数 -appearance 同名，截图时可以直接覆盖
        static let appearance = "appearance"
        static let noteStyle = "noteNames.style"
    }

    init(demo: DemoOptions?) {
        let d = UserDefaults.standard
        appearance = AppearanceMode(rawValue: d.string(forKey: Keys.appearance) ?? "") ?? .system
        noteStyleOverride = d.string(forKey: Keys.noteStyle).flatMap(NoteNaming.Style.init(rawValue:))
    }
}

/// 页面导航状态：当前标签、底部面板、调音器设置、练习历史。
@MainActor
@Observable
final class Router {
    var tab: AppTab = .training
    var sheet: MetronomeSheet?
    /// 调音器右上角的小设置（标准音、音名显示）。
    var showSettings = false
    var showHistory = false
    /// 训练页 → 扫弦节奏型
    var showStrum = false
    /// 打开扫弦页后直接开始跟练（训练页卡片上的“开始练习”）
    var strumAutoStart = false
}

/// 调音器和和弦库的持久化（UserDefaults）。
enum InstrumentStore {
    private static let tunerKey = "tuner.selection"
    private static let a4Key = "tuner.a4"
    private static let chordKey = "chords.current"
    private static let favoritesKey = "chords.favorites"
    private static let leftHandedKey = "chords.leftHanded"

    static var tunerSelection: InstrumentSelection {
        get { load(tunerKey) ?? InstrumentSelection(instrumentID: "guitar", tuningID: "standard") }
        set { store(newValue, tunerKey) }
    }

    static var a4: Double {
        get { UserDefaults.standard.object(forKey: a4Key) as? Double ?? TunerDefaults.a4 }
        set { UserDefaults.standard.set(newValue, forKey: a4Key) }
    }

    static var chordCurrent: ChordFavorite? {
        get { load(chordKey) }
        set { store(newValue, chordKey) }
    }

    static var favorites: ChordFavorites {
        get { load(favoritesKey) ?? ChordFavorites() }
        set { store(newValue, favoritesKey) }
    }

    static var leftHanded: Bool {
        get { UserDefaults.standard.bool(forKey: leftHandedKey) }
        set { UserDefaults.standard.set(newValue, forKey: leftHandedKey) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func store<T: Encodable>(_ value: T?, _ key: String) {
        UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

/// 截图和演示用的启动参数，例如 `-demo YES -demoTab training -appearance light`。
/// 演示模式不读写真实数据：练习记录用内存数据库并填入和设计稿一致的样例。
struct DemoOptions {
    var config: MetronomeConfig
    var training: TrainingOptions
    var playing: Bool
    var beat: Int?
    /// 正在响的是这一拍里的第几个切分点（0 = 主拍）
    var sub: Int = 0
    var elapsed: Int
    var liveBar: Int?
    var liveBPM: Int?
    var todaySeconds: Int?
    var tab: AppTab
    var sheet: String?

    static func fromLaunchArguments() -> DemoOptions? {
        let d = UserDefaults.standard
        guard ProcessInfo.processInfo.arguments.contains("-demo") else { return nil }
        // 和设计稿 01 一致：120 BPM、4/4、八分切分、木鱼，第 2 拍正在响
        // 截图其他切分和拍号：-demoSubdivision sixteenth -demoTime 12/8 -demoSub 2
        var ts = TimeSignature.fourFour
        var accents = AccentPattern([.strong, .weak, .medium, .weak])
        if let t = d.string(forKey: "demoTime"), case let parts = t.split(separator: "/").compactMap({ Int($0) }), parts.count == 2 {
            ts = TimeSignature(beatsPerBar: parts[0], beatUnit: parts[1])
            accents = AccentPreset.grouped.pattern(for: ts)
        }
        let subdivision = d.string(forKey: "demoSubdivision").flatMap(Subdivision.init(rawValue:)) ?? .eighth
        let config = MetronomeConfig(bpm: 120, timeSignature: ts, accents: accents, subdivision: subdivision, sound: .woodblock)
        let tab = AppTab(rawValue: d.string(forKey: "demoTab") ?? "") ?? .metronome
        // 和设计稿 03 一致：三个训练都开着，第 32 小节、96 BPM，今天已练 12:30
        var training = TrainingOptions()
        if tab == .training {
            training.rampEnabled = true
            training.muteEnabled = true
            training.timerEnabled = true
        }
        let beat = d.object(forKey: "demoBeat") != nil ? d.integer(forKey: "demoBeat") - 1 : 1
        return DemoOptions(config: config, training: training, playing: tab != .training, beat: beat,
                           sub: min(max(d.integer(forKey: "demoSub"), 0), config.subdivision.clickCount - 1),
                           elapsed: 12 * 60 + 30,
                           liveBar: tab == .training ? 32 : nil, liveBPM: tab == .training ? 96 : nil,
                           todaySeconds: tab == .training ? 12 * 60 + 30 : nil,
                           tab: tab, sheet: d.string(forKey: "demoSheet"))
    }

    /// 和设计稿 06 一致的一周练习记录（今天是周日）。
    @MainActor
    static func seed(_ context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(daysAgo: Int, hour: Int) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: -daysAgo, to: today)!)!
        }
        let rows: [(Int, Int, Int, Int, PracticeMode)] = [
            (6, 35, 90, 90, .free), (5, 20, 100, 100, .free), (4, 48, 72, 84, .free),
            (2, 30, 120, 120, .mute), (1, 42, 68, 76, .free), (0, 30, 80, 112, .ramp),
        ]
        for (ago, minutes, lo, hi, mode) in rows {
            context.insert(PracticeSession(startedAt: at(daysAgo: ago, hour: 19), duration: Double(minutes * 60),
                                           minBPM: lo, maxBPM: hi, mode: mode))
        }
        try? context.save()
    }
}

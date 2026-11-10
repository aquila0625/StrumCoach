import SwiftUI

/// 底部标签的定义集中在这里。增删、改名、换顺序只改这个文件。
enum AppTab: String, CaseIterable, Identifiable {
    case training, metronome, tuner, chords, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metronome: return String(localized: "节拍器", bundle: .appLanguage, locale: .appLanguage)
        case .training: return String(localized: "训练", bundle: .appLanguage, locale: .appLanguage)
        case .tuner: return String(localized: "调音器", bundle: .appLanguage, locale: .appLanguage)
        case .chords: return String(localized: "和弦库", bundle: .appLanguage, locale: .appLanguage)
        case .profile: return String(localized: "我的", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var icon: IconKind {
        switch self {
        case .metronome: return .metronome
        case .training: return .train
        case .tuner: return .tuner
        case .chords: return .chord
        case .profile: return .me
        }
    }
}

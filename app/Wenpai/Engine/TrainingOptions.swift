import Foundation
import MetronomeCore

/// 训练页的三个开关和参数（设计稿 03）。渐进提速、静音可以同时开，最后合成 PracticeKit 的 TrainingPlan 交给引擎。
struct TrainingOptions: Codable, Equatable {
    var rampEnabled = false
    var ramp = RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .hold)
    var muteEnabled = false
    var mute = MuteSettings.bars(audible: 3, muted: 1)
    var timerEnabled = false
    var timerMinutes = 20
    /// 到达练习目标时自动停止。
    var autoStop = false

    /// 两种训练都没开时返回 nil（普通播放）。
    func plan(baseBPM: Int) -> TrainingPlan? {
        guard rampEnabled || muteEnabled else { return nil }
        return TrainingPlan(baseBPM: baseBPM, ramp: rampEnabled ? ramp : nil, mute: muteEnabled ? mute : nil)
    }

    var rampSummary: String {
        let sign = ramp.isAscending ? "+" : "−"
        return String(localized: "\(ramp.startBPM) → \(ramp.targetBPM) BPM · 每 \(Units.bars(ramp.barsPerStep)) \(sign)\(ramp.step)", bundle: .appLanguage, locale: .appLanguage)
    }

    var muteSummary: String {
        switch mute.pattern {
        case let .bars(audible, muted):
            return String(localized: "有声 \(Units.bars(audible)) · 静音 \(Units.bars(muted))", bundle: .appLanguage, locale: .appLanguage)
        case let .randomBeats(probability, _):
            let percent = probability.formatted(.percent.precision(.fractionLength(0)).locale(.appLanguage))
            return mute.keepsDownbeat ? String(localized: "随机静音 \(percent) 的拍 · 保留首拍", bundle: .appLanguage, locale: .appLanguage)
                                      : String(localized: "随机静音 \(percent) 的拍", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var timerSummary: String {
        autoStop ? String(localized: "目标 \(Units.minutes(timerMinutes))，到时提醒并停止", bundle: .appLanguage, locale: .appLanguage)
                 : String(localized: "目标 \(Units.minutes(timerMinutes))，到时提醒", bundle: .appLanguage, locale: .appLanguage)
    }
}

extension RampSettings.EndBehavior {
    var title: String {
        switch self {
        case .stop: return String(localized: "到目标后停止", bundle: .appLanguage, locale: .appLanguage)
        case .hold: return String(localized: "保持目标速度", bundle: .appLanguage, locale: .appLanguage)
        case .loop: return String(localized: "从头循环", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

extension PracticeMode {
    var title: String {
        switch self {
        case .free: return String(localized: "自由练习", bundle: .appLanguage, locale: .appLanguage)
        case .ramp: return String(localized: "渐进提速", bundle: .appLanguage, locale: .appLanguage)
        case .mute: return String(localized: "静音小节", bundle: .appLanguage, locale: .appLanguage)
        case .rampAndMute: return String(localized: "提速 + 静音", bundle: .appLanguage, locale: .appLanguage)
        case .strum: return String(localized: "扫弦节奏型", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

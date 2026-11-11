import MetronomeCore
import SwiftUI
import TunerKit

/// 调音器右上角的小设置：标准音 A4 和音名显示。其余设置都在“我的”页。
struct TunerSettingsScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(TunerModel.self) private var tuner
    @Environment(\.noteNaming) private var naming

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("调音器设置").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
            }
            .padding(.bottom, 12)

            SectionLabel(title: "标准音", note: "\(Int(TunerDefaults.a4Range.lowerBound))–\(Int(TunerDefaults.a4Range.upperBound)) Hz")
            ValueStepper(title: "标准音 \(naming.fullName(Pitch(midi: 69)))", value: Int(tuner.a4.rounded()), display: Units.hertz,
                         range: Int(TunerDefaults.a4Range.lowerBound)...Int(TunerDefaults.a4Range.upperBound)) {
                tuner.setA4(Double($0))
            }

            SectionLabel(title: "音名显示")
            Segmented(options: NoteNaming.Style.allCases, selected: settings.noteStyle, title: noteStyleTitle) {
                settings.noteStyleOverride = $0
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .environment(\.sheetCard, theme.card)
        .background(ScreenBackground())
    }

    /// “字母 C D E”“唱名 Do Re Mi”，示例按当前语言的写法。
    private func noteStyleTitle(_ style: NoteNaming.Style) -> String {
        let sample = NoteNaming(style: style, languageCode: settings.languageCode)
        let example = [0, 2, 4].map { sample.name(pitchClass: $0) }.joined(separator: " ")
        return style == .letters ? String(localized: "字母 \(example)", bundle: .appLanguage, locale: .appLanguage) : String(localized: "唱名 \(example)", bundle: .appLanguage, locale: .appLanguage)
    }
}

/// App 内的语言列表：跟随系统 + 12 种语言（国旗 + 该语言自己的名字）。选完立即生效，列表自动关闭。
struct LanguagePicker: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("语言").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                    Spacer()
                    Button("完成") { dismiss() }
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
                }
                .padding(20)
                ScrollView {
                    VStack(spacing: 0) {
                        row(flag: "🌐", title: Text("跟随系统"), selected: settings.language == nil) { choose(nil) }
                        ForEach(AppLanguage.options) { option in
                            Rectangle().fill(theme.line).frame(height: 1).padding(.leading, 56)
                            row(flag: option.flag, title: Text(verbatim: option.nativeName),
                                selected: settings.language == option.code) { choose(option.code) }
                        }
                    }
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    /// 先关掉列表，等关闭动画走完再换语言（换语言会整页重建）。
    private func choose(_ code: String?) {
        guard code != settings.language else { dismiss(); return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            settings.language = code
            metronome.languageChanged()
        }
    }

    private func row(flag: String, title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(verbatim: flag).font(.system(size: 26))
                title.font(.system(size: 16)).foregroundStyle(theme.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

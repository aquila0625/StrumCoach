import MetronomeCore
import SwiftUI
import TunerKit

/// 自绘底部面板：直角贴底、顶部圆角 28，和设计稿 02 一致（系统 sheet 在新系统上会变成悬浮玻璃样式）。
struct BottomSheetHost: View {
    @Environment(\.theme) private var theme
    @Binding var sheet: MetronomeSheet?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if let sheet {
                theme.scrim
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                    .accessibilityLabel("关闭面板")
                    .accessibilityAddTraits(.isButton)

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Capsule().fill(theme.weak).frame(width: 40, height: 5)
                            .padding(.bottom, 10)
                        HStack {
                            Text(sheet.title).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            Button("完成") { close() }
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .padding(.bottom, 14)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = max(0, $0.translation.height) }
                            .onEnded { g in
                                if g.translation.height > 100 || g.predictedEndTranslation.height > 240 { close() }
                                withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                            }
                    )
                    content(for: sheet)
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 12, trailing: 20))
                .frame(maxWidth: .infinity)
                .environment(\.sheetCard, theme.sheetCard)
                .background(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                        .fill(theme.sheet)
                        .ignoresSafeArea(edges: .bottom)
                }
                .offset(y: dragOffset)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: sheet)
    }

    private func close() { sheet = nil }

    @ViewBuilder
    private func content(for sheet: MetronomeSheet) -> some View {
        switch sheet {
        case .rhythm: RhythmSheet()
        case .sound: SoundSettings()
        case .voice: CustomVoiceSheet()
        case .bpm: BPMEntry(onDone: close)
        case .ramp: RampEditor()
        case .mute: MuteEditor()
        case .timer: TimerEditor()
        }
    }
}

extension MetronomeSheet {
    var title: String {
        switch self {
        case .rhythm: return String(localized: "节奏设置", bundle: .appLanguage, locale: .appLanguage)
        case .sound: return String(localized: "音色与反馈", bundle: .appLanguage, locale: .appLanguage)
        case .voice: return String(localized: "我的声音", bundle: .appLanguage, locale: .appLanguage)
        case .bpm: return String(localized: "输入速度", bundle: .appLanguage, locale: .appLanguage)
        case .ramp: return String(localized: "渐进提速", bundle: .appLanguage, locale: .appLanguage)
        case .mute: return String(localized: "静音训练", bundle: .appLanguage, locale: .appLanguage)
        case .timer: return String(localized: "练习计时", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

private struct SheetCardKey: EnvironmentKey {
    static let defaultValue = Color.clear
}

extension EnvironmentValues {
    /// 面板里卡片的底色（设计稿 .sheet{--card:var(--sheetcard)}）
    var sheetCard: Color {
        get { self[SheetCardKey.self] }
        set { self[SheetCardKey.self] = newValue }
    }
}

/// 面板里的小标题行：左边标题，右边说明。
struct SectionLabel: View {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey
    var note: LocalizedStringKey = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            Text(note).multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.8)
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.sub)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

/// 分段选择（.seg）。
struct Segmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [T]
    let selected: T?
    let title: (T) -> String
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selected
                Button {
                    onSelect(option)
                } label: {
                    // 德语、俄语等长词：最多两行，再不够就缩小字号
                    Text(title(option))
                        .font(.system(size: 16, weight: on ? .semibold : .regular)).monospacedDigit()
                        .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                        .foregroundStyle(on ? Color.white : theme.sub)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 节奏设置（设计稿 02）

private struct RhythmSheet: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor

    var body: some View {
        let ts = metronome.config.timeSignature
        VStack(spacing: 0) {
            SectionLabel(title: "拍号", note: "每小节拍数 / 以几分音符为一拍").padding(.top, -14)
            HStack(spacing: 14) {
                NumberWheel(value: ts.beatsPerBar, range: TimeSignature.editorBeats) {
                    metronome.setTimeSignature(.init($0, ts.beatUnit))
                }
                Text("/").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(theme.sub)
                Segmented(options: TimeSignature.allowedBeatUnits, selected: ts.beatUnit, title: { "\($0)" }) {
                    metronome.setTimeSignature(.init(ts.beatsPerBar, $0))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                ForEach(TimeSignature.quickPicks, id: \.self) { pick in
                    let on = pick == ts
                    Button {
                        metronome.setTimeSignature(pick)
                    } label: {
                        Text(pick.displayName)
                            .font(.system(size: 14)).monospacedDigit()
                            .foregroundStyle(on ? theme.accent : theme.sub)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(cardColor, in: Capsule())
                            .overlay { if on { Capsule().strokeBorder(theme.accent, lineWidth: 1.5) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("拍号 \(pick.beatsPerBar) \(pick.beatUnit)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 10)

            SectionLabel(title: "切分")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Subdivision.allCases, id: \.self) { sub in
                    SubdivisionOption(subdivision: sub, isOn: sub == metronome.config.subdivision) {
                        metronome.select(sub)
                    }
                }
            }

            SectionLabel(title: "重音预设")
            Segmented(options: AccentPreset.allCases, selected: metronome.matchingPreset, title: \.title) {
                metronome.applyPreset($0)
            }
        }
    }
}

private struct SubdivisionOption: View {
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor
    let subdivision: Subdivision
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                NoteGlyph(subdivision.glyph, color: isOn ? theme.accent : theme.text)
                Text(subdivision.title).font(.system(size: 11.5)).foregroundStyle(isOn ? theme.text : theme.sub)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if isOn { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.accent, lineWidth: 2) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subdivision.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 拍号分子的滚轮：上下拖动或点按上下的数字来改，1–16。
private struct NumberWheel: View {
    @Environment(\.theme) private var theme
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void
    @State private var dragBase: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text(value > range.lowerBound ? "\(value - 1)" : " ")
                .font(.system(size: 16)).foregroundStyle(theme.dim)
                .frame(height: 24)
                .onTapGesture { step(-1) }
            Text("\(value)")
                .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(theme.highlight, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value < range.upperBound ? "\(value + 1)" : " ")
                .font(.system(size: 16)).foregroundStyle(theme.dim)
                .frame(height: 24)
                .onTapGesture { step(1) }
        }
        .monospacedDigit()
        .frame(width: 84, height: 96)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { g in
                    if dragBase == nil { dragBase = value }
                    let target = dragBase! - Int((g.translation.height / 24).rounded())
                    let clamped = min(max(target, range.lowerBound), range.upperBound)
                    if clamped != value { onChange(clamped) }
                }
                .onEnded { _ in dragBase = nil }
        )
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("每小节拍数")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { step($0 == .increment ? 1 : -1) }
    }

    private func step(_ delta: Int) {
        let next = value + delta
        if range.contains(next) { onChange(next) }
    }
}

// MARK: - 音色与反馈

private struct SoundSettings: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        @Bindable var m = metronome
        ScrollView {
            VStack(spacing: 0) {
                ForEach(SoundGroup.allCases, id: \.self) { group in
                    SectionLabel(title: LocalizedStringKey(group.title),
                                 note: group == .classic ? "点一下试听，强 · 次强 · 弱各一个音" : "")
                        .padding(.top, group == .classic ? -14 : 0)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(group.sounds, id: \.self) { sound in tile(sound) }
                    }
                }
                if metronome.config.sound == .voice && metronome.sounds.isRenderingCount {
                    Text("正在生成人声报数…").font(.system(size: 13)).foregroundStyle(theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                customVoiceRow

                SectionLabel(title: "切分音量", note: "相对主拍 \(Double(metronome.config.subdivisionVolume).formatted(.percent.precision(.fractionLength(0)).locale(.appLanguage)))")
                Slider(value: Binding(
                    get: { Double(metronome.config.subdivisionVolume) },
                    set: { metronome.config.subdivisionVolume = Float(($0 * 20).rounded() / 20) }
                ), in: 0...1)
                .tint(theme.accent)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("切分音量")

                SectionLabel(title: "触感反馈")
                Toggle(isOn: $m.hapticsEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("跟拍震动").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.text)
                        Text("强拍重、弱拍轻，和声音同步").font(.system(size: 13)).foregroundStyle(theme.sub)
                    }
                }
                .tint(theme.green)
                .padding(16)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 560)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func tile(_ sound: SoundKind) -> some View {
        let on = sound == metronome.config.sound
        return Button {
            metronome.selectSound(sound)
            if sound == .custom && metronome.sounds.customStrong == nil && metronome.sounds.customWeak == nil {
                router.sheet = .voice
            }
        } label: {
            Text(sound.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                .foregroundStyle(on ? theme.accent : theme.text)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if on { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.accent, lineWidth: 2) }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// “我的声音”的录制入口。
    private var customVoiceRow: some View {
        Button { router.sheet = .voice } label: {
            HStack {
                Image(systemName: "mic.fill").foregroundStyle(theme.accent)
                Text(metronome.sounds.customStrong == nil ? "录制我的声音" : "重新录制我的声音")
                    .font(.system(size: 15)).foregroundStyle(theme.text)
                Spacer()
                Icon(kind: .chevron, color: theme.sub).rotationEffect(.degrees(-90))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

// MARK: - 录我的声音

private struct CustomVoiceSheet: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(TunerModel.self) private var tuner
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor
    @State private var recorder = CustomVoiceRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("对着麦克风发出一下短促的声音，比如拍手、说“嗒”、敲桌子。每段最长 2 秒，开头的静音会自动去掉，音量自动调匀。")
                .font(.system(size: 13)).foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -10)
            slotCard(title: "强拍", note: "每小节第一拍", slot: VoiceBank.customStrongSlot)
            slotCard(title: "弱拍（可选）", note: "不录就和强拍用同一个声音", slot: VoiceBank.customWeakSlot)
            if recorder.state == .denied {
                Text("没有麦克风权限。请到系统设置里允许本 App 使用麦克风。")
                    .font(.system(size: 13)).foregroundStyle(theme.accent)
            } else if let message = recorder.message {
                Text(message).font(.system(size: 13)).foregroundStyle(theme.accent)
            }
        }
        .padding(.bottom, 8)
        .onAppear { recorder.attach(metronome.sounds) }
        .onDisappear { recorder.stop() }
    }

    private func slotCard(title: LocalizedStringKey, note: LocalizedStringKey, slot: Int) -> some View {
        let clip = metronome.sounds.clip(slot: slot)
        let recording = recorder.state == .recording(slot: slot)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.text)
                Group {
                    if recording { Text("正在录音…再点一下结束") }
                    else if let clip { Text(verbatim: clip.seconds.formatted(.number.precision(.fractionLength(2)).locale(.appLanguage)) + " s") }
                    else { Text(note) }
                }
                .font(.system(size: 12)).foregroundStyle(recording ? theme.accent : theme.sub)
            }
            Spacer(minLength: 4)
            if clip != nil && !recording {
                circleButton("play.fill", label: "试听") { recorder.play(slot: slot) }
                circleButton("trash", label: "删除") { metronome.sounds.deleteCustom(slot: slot) }
            }
            Button {
                recorder.record(slot: slot, sounds: metronome.sounds) {
                    metronome.stop(forRecording: true)
                    tuner.stop()
                }
            } label: {
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(theme.accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(recording ? Text("结束录音") : Text("录音"))
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func circleButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                .frame(width: 40, height: 40)
                .background(theme.card2, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(label))
    }
}

// MARK: - 数字键盘输入 BPM

private struct BPMEntry: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor
    let onDone: () -> Void
    @State private var text = ""

    private var value: Int? { Int(text) }
    private var isValid: Bool { value.map { (20...400).contains($0) } ?? false }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(text.isEmpty ? "\(metronome.bpm)" : text)
                    .font(.system(size: 64, weight: .thin)).monospacedDigit()
                    .foregroundStyle(text.isEmpty ? theme.dim : theme.text)
                (text.isEmpty || isValid ? Text("范围 20–400 BPM") : Text("请输入 20–400 之间的数"))
                    .font(.system(size: 13))
                    .foregroundStyle(text.isEmpty || isValid ? theme.sub : theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "清除", "0", "⌫"], id: \.self) { key in
                    Button {
                        press(key)
                    } label: {
                        Text(keyLabel(key))
                            .font(.system(size: key.count > 1 ? 17 : 26, weight: key.count > 1 ? .regular : .light))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(key == "⌫" ? String(localized: "删除", bundle: .appLanguage, locale: .appLanguage) : keyLabel(key))
                }
            }

            Button {
                if let value, isValid {
                    metronome.bpm = value
                    onDone()
                }
            } label: {
                Text("确定")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(theme.accent.opacity(isValid ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(!isValid)
        }
        .padding(.bottom, 4)
    }

    /// “清除”键按语言显示，数字和退格符不变。
    private func keyLabel(_ key: String) -> String {
        key == "清除" ? String(localized: "清除", bundle: .appLanguage, locale: .appLanguage) : key
    }

    private func press(_ key: String) {
        switch key {
        case "清除": text = ""
        case "⌫": if !text.isEmpty { text.removeLast() }
        default: if text.count < 3 { text = text == "0" ? key : text + key }
        }
    }
}

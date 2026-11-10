import AVFoundation
import ChordKit
import SwiftUI
import TunerKit

/// 节拍器页和训练页弹出的底部面板。放在根视图上，这样能盖住标签栏（和设计稿 02 一致）。
enum MetronomeSheet: String, Identifiable {
    case rhythm, sound, voice, bpm, ramp, mute, timer
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(MetronomeController.self) private var metronome
    @Environment(TunerModel.self) private var tuner
    @Environment(ChordLibraryModel.self) private var chords
    @Environment(StrumTrainer.self) private var strum
    let isDemo: Bool

    var body: some View {
        @Bindable var router = router
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                Group {
                    switch router.tab {
                    case .metronome: MetronomeScreen()
                    case .training: TrainingScreen()
                    case .tuner: TunerTab(isDemo: isDemo)
                    case .chords: ChordTab()
                    case .profile: ProfileScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                TabBar(selection: $router.tab)
            }
            // 换语言时整页重建（有些子视图的参数可比较相等，不重建就不会重新取文字）
            .id(settings.languageCode)

            BottomSheetHost(sheet: $router.sheet)

            if let banner = metronome.banner {
                BannerView(text: banner)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: metronome.banner)
        .fullScreenCover(isPresented: $router.showStrum) {
            // iPad 上和其他页面一样按 iPhone 排版再整体放大
            PadScaled { StrumScreen(trainer: strum, chords: chords) }
                .environment(\.noteNaming, settings.noteNaming)
                .modifier(ThemeProvider())
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .sheet(isPresented: $router.showSettings) {
            TunerSettingsScreen()
                .environment(\.noteNaming, settings.noteNaming)
                .modifier(ThemeProvider())
                .preferredColorScheme(settings.appearance.colorScheme)
                .presentationDetents([.medium])
        }
        .onAppear(perform: wire)
        // 和弦库的分解和弦跟随节拍器速度：播放中用实际速度（开了渐进提速时跟着变），停着时用设置的速度
        .onChange(of: metronome.bpm) { _, _ in syncChordTempo() }
        .onChange(of: metronome.liveBPM) { _, _ in syncChordTempo() }
        .onChange(of: router.tab) { old, new in tabChanged(from: old, to: new) }
        // 乐器联动：和弦库换了吉他/贝斯/尤克里里，调音器切到它的标准定弦；反过来调音器选了这三种乐器的定弦，和弦库跟着切
        .onChange(of: chords.instrument.id) { _, _ in
            InstrumentSync.chordsChanged(chords, tuner: tuner)
            saveChords()
        }
        .onChange(of: tuner.selection) { _, selection in
            if !isDemo { InstrumentStore.tunerSelection = selection }
            InstrumentSync.tunerChanged(tuner, chords: chords)
        }
        .onChange(of: tuner.a4) { _, a4 in
            chords.a4 = a4
            if !isDemo { InstrumentStore.a4 = a4 }
        }
        .onChange(of: chords.current) { _, _ in saveChords() }
        .onChange(of: chords.leftHanded) { _, value in
            if !isDemo { InstrumentStore.leftHanded = value }
        }
    }

    private func syncChordTempo() {
        let bpm = Double(metronome.liveBPM ?? metronome.bpm)
        if chords.bpm != bpm { chords.bpm = bpm }
    }

    private func wire() {
        syncChordTempo()
        chords.onFavoritesChange = { favorites in
            if !isDemo { InstrumentStore.favorites = favorites }
        }
        // 调音器在前台时从锁屏/控制中心开始播放：先关麦克风，免得收进节拍声
        metronome.onWillStart = {
            if router.tab == .tuner { tuner.stop() }
        }
        if !isDemo { tabChanged(from: .metronome, to: router.tab) }
    }

    private func saveChords() {
        if !isDemo { InstrumentStore.chordCurrent = chords.current }
    }

    private func tabChanged(from old: AppTab, to new: AppTab) {
        guard !isDemo else { return }
        if new == .tuner, metronome.isPlaying {
            // 进入调音器先暂停节拍器，并且马上把音频会话交给录音
            metronome.stop(forRecording: true)
            metronome.showBanner(String(localized: "已暂停节拍器，避免麦克风收进节拍声", bundle: .appLanguage, locale: .appLanguage))
        }
        if new == .chords, !metronome.isPlaying, !isDemo {
            // 和弦试听走播放会话（从调音器过来时会话还是录音模式，声音会走听筒）
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback {
                try? session.setCategory(.playback, mode: .default, options: [])
            }
        }
    }
}

/// 乐器联动：和弦库换了吉他/贝斯/尤克里里，调音器切到它的标准定弦；
/// 反过来调音器选了这三种乐器的任意定弦，和弦库切到同一乐器和定弦。两边都只在不一致时才改，不会来回触发。
@MainActor
enum InstrumentSync {
    static func chordsChanged(_ chords: ChordLibraryModel, tuner: TunerModel) {
        let inst = chords.instrument
        if tuner.instrument.id != inst.id { tuner.select(instrument: inst, tuning: inst.defaultTuning) }
    }

    static func tunerChanged(_ tuner: TunerModel, chords: ChordLibraryModel) {
        let inst = tuner.instrument
        guard ChordLibrary.instruments.contains(where: { $0.id == inst.id }) else { return }
        if chords.instrument.id != inst.id || chords.tuning.id != tuner.tuning.id {
            chords.select(instrument: inst, tuning: tuner.tuning)
        }
    }
}

/// 自绘标签栏：设计稿的线性图标，浅色主题磨砂半透明。
private struct TabBar: View {
    @Environment(\.theme) private var theme
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let on = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Icon(kind: tab.icon, color: on ? theme.accent : theme.sub)
                        Text(tab.title).font(.system(size: 10.5))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(on ? theme.accent : theme.sub)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 1)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                if theme.isLight {
                    Rectangle().fill(.ultraThinMaterial)
                }
                Rectangle().fill(theme.tabBg)
                Rectangle().fill(theme.tabBorder).frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// 顶部提示条。
private struct BannerView: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(theme.accent, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .padding(.top, 6)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// 调音器标签：TunerKit 的界面，配上 App 的深浅主题。
private struct TunerTab: View {
    @Environment(\.theme) private var theme
    @Environment(TunerModel.self) private var tuner
    @Environment(Router.self) private var router
    let isDemo: Bool

    var body: some View {
        TunerView(model: tuner, palette: theme.tunerPalette, autoStart: !isDemo, onSettings: { router.showSettings = true })
    }
}

/// 和弦库标签：ChordKit 的界面。
private struct ChordTab: View {
    @Environment(\.theme) private var theme
    @Environment(ChordLibraryModel.self) private var chords

    var body: some View {
        let p = theme.tunerPalette
        // 背景透明（透出 App 的渐变），圆点上的数字用页面底色
        ChordLibraryView(model: chords, palette: ChordPalette(
            background: .clear, card: p.card, card2: p.card2, line: p.line, text: p.text, sub: p.sub, dim: p.dim,
            accent: p.accent, weak: p.weak, onText: theme.bg))
    }
}

extension Theme {
    /// 调音器和和弦库用的配色。背景透明，让 App 的背景（浅色的暖白渐变）透出来。
    var tunerPalette: TunerPalette {
        TunerPalette(background: .clear, card: card, card2: card2, line: line, text: text, sub: sub, dim: dim,
                     accent: accent, weak: weak, green: green)
    }
}

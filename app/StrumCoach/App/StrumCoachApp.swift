import ChordKit
import MetronomeCore
import SwiftData
import SwiftUI
import TunerKit

@main
struct StrumCoachApp: App {
    @State private var settings: AppSettings
    @State private var router: Router
    @State private var controller: MetronomeController
    @State private var tuner: TunerModel
    @State private var chords: ChordLibraryModel
    /// 扫弦节奏型跟练：训练页卡片和扫弦页共用一个（选的节奏型、和弦进行、成绩都同步）
    @State private var strum: StrumTrainer
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    private let isDemo: Bool

    init() {
        let demo = DemoOptions.fromLaunchArguments()
        isDemo = demo != nil
        // 练习记录（PracticeKit 的 SwiftData 模型）。演示模式用内存库并填入样例
        let container = (try? PracticeKitSchema.makeContainer(inMemory: demo != nil))
            ?? (try! PracticeKitSchema.makeContainer(inMemory: true))
        if demo != nil { DemoOptions.seed(container.mainContext) }
        self.container = container

        let settings = AppSettings(demo: demo)
        let controller = MetronomeController(demo: demo)
        controller.modelContext = container.mainContext

        let tuner = TunerModel(selection: demo == nil ? InstrumentStore.tunerSelection
                                                      : InstrumentSelection.default,  // 设计稿 04 是自动识别（半音阶）
                               a4: demo == nil ? InstrumentStore.a4 : 440)
        let chords = ChordLibraryModel(
            current: demo == nil ? InstrumentStore.chordCurrent
                                 : ChordFavorite(instrumentID: "guitar", tuningID: "standard", root: 0, typeID: ChordType.major7.id, voicingIndex: 0),
            leftHanded: demo == nil && InstrumentStore.leftHanded,
            favorites: demo == nil ? InstrumentStore.favorites : ChordFavorites())
        chords.a4 = tuner.a4
        // 和弦试听跟节拍器共用 App 管理的 .playback 会话，避免它把会话切成录音模式打断节拍
        chords.configuresAudioSession = false
        if demo != nil {
            // 设计稿 04：A4 偏高 3 音分
            tuner.inject(PitchReading(frequency: 440.8, clarity: 0.97))
        }

        let router = Router()
        if let demo {
            router.tab = demo.tab
            switch demo.sheet {
            case "settings": router.showSettings = true
            case "history": router.showHistory = true
            case "strum", "strum-result", "strum-edit": router.showStrum = true
            case let s?: router.sheet = MetronomeSheet(rawValue: s)
            case nil: break
            }
        }

        _settings = State(initialValue: settings)
        _router = State(initialValue: router)
        _controller = State(initialValue: controller)
        _tuner = State(initialValue: tuner)
        _chords = State(initialValue: chords)
        _strum = State(initialValue: demo != nil ? StrumTrainer.demo(library: chords, sheet: demo?.sheet)
                                                 : StrumTrainer(bpm: controller.bpm, library: chords))
    }

    var body: some Scene {
        WindowGroup {
            // iPad 上整体放大、内容列居中（见 PadLayout）
            PadScaled { RootView(isDemo: isDemo) }
                .environment(settings)
                .environment(router)
                .environment(controller)
                .environment(tuner)
                .environment(chords)
                .environment(strum)
                .environment(\.noteNaming, settings.noteNaming)
                // App 内切换语言：SwiftUI 文字和格式跟着 locale 走，换语言时整棵视图重建
                .environment(\.locale, settings.locale)
                .id(settings.languageCode)
                .modelContainer(container)
                .modifier(ThemeProvider())
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            // 进后台：扫弦的示范、听一听、跟练都立刻停，关掉麦克风（跟练已练完的遍照样记成绩）
            if phase == .background, strum.isBusy { strum.teardown() }
        }
    }
}

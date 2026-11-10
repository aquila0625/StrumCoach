import Foundation
import MetronomeCore
import Observation
import OSLog
import QuartzCore
import SwiftData
import UIKit
import UserNotifications

private let log = Logger(subsystem: "com.example.tunebeatchord", category: "metronome")

/// 节拍器的界面状态和操作。界面只跟它打交道，它再把配置交给音频引擎。
/// 训练方案、练习记录、练习目标提醒也在这里，因为它们都跟“什么时候在播”绑在一起。
@MainActor
@Observable
final class MetronomeController {
    /// 用户设定的节奏和速度。`training` 字段由 `training` 选项自动生成，不要直接改。
    var config: MetronomeConfig {
        didSet {
            guard config != oldValue else { return }
            if config.bpm != oldValue.bpm { refreshTrainingPlan() }
            audio.update(config)
            save()
            nowPlaying.update(config: config, isPlaying: isPlaying)
        }
    }
    var training: TrainingOptions {
        didSet {
            guard training != oldValue else { return }
            refreshTrainingPlan()
            saveTraining()
        }
    }
    private(set) var isPlaying = false
    /// 正在响的那一拍（小节内序号），按音频时钟同步。停止时为 nil。
    private(set) var currentBeat: Int?
    /// 正在响的点是这一拍里的第几个（0 = 主拍），按音频时钟同步。停止时为 nil。
    private(set) var currentSub: Int?
    /// 正在响的那一拍实际用的切分（改切分在下一拍才生效）。停止时为 nil。
    private(set) var playingSubdivision: Subdivision?
    /// 拍子方块里按哪种切分分格：播放中跟着实际发声的拍，停止时用当前设置。
    var displayedSubdivision: Subdivision { playingSubdivision ?? config.subdivision }
    /// 播放中实际的小节序号（0 起）和 BPM（开了渐进提速时会变），按音频时钟同步。
    private(set) var liveBar: Int?
    private(set) var liveBPM: Int?
    /// 本次打开 App 以来累计的播放秒数（主界面的“计时”）。
    private(set) var elapsedSeconds = 0
    /// 今天的练习总秒数：已记录的 + 正在进行的这一次（训练页的练习计时用）。
    private(set) var todaySeconds = 0
    /// 顶部提示条的文字（练习目标到了、训练结束等），几秒后自动消失。
    private(set) var banner: String?
    /// 最近一次选的重音预设；改拍号时按它重新生成重音。
    var lastPreset: AccentPreset = .grouped {
        didSet { UserDefaults.standard.set(lastPreset.rawValue, forKey: Keys.preset) }
    }
    var hapticsEnabled = true {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics)
            if !hapticsEnabled { haptics.stop() }
        }
    }
    private(set) var lastError: String?
    /// 开始播放前回调（调音器在前台时用来先关麦克风）。
    @ObservationIgnored var onWillStart: (() -> Void)?
    /// 练习记录写到这里。
    @ObservationIgnored var modelContext: ModelContext? {
        didSet { refreshTodayBaseline() }
    }

    /// 人声报数和我的声音。
    @ObservationIgnored let sounds: DynamicSounds
    @ObservationIgnored private let audio: AudioEngineHost
    /// 试听音色时自动停止的任务（试听期间用户点了播放就取消，接着播）。
    @ObservationIgnored private var previewWork: DispatchWorkItem?
    @ObservationIgnored private let haptics = HapticClicker()
    @ObservationIgnored private let nowPlaying = NowPlayingBridge()
    @ObservationIgnored private var tapTempo = TapTempo()
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var shownSerial: Int64 = -1
    @ObservationIgnored private var hapticSerial: Int64 = -1
    @ObservationIgnored private var shownClick: Int64 = -1
    @ObservationIgnored private var playStartedAt: Double = 0
    @ObservationIgnored private var elapsedBase: Double = 0
    @ObservationIgnored private var todayBaseline: TimeInterval = 0
    // 这一次练习的记录
    @ObservationIgnored private var sessionStart = Date()
    @ObservationIgnored private var sessionMode: PracticeMode = .free
    @ObservationIgnored private var sessionBPM: ClosedRange<Int> = 120...120
    /// 截图用：固定显示某一拍高亮、显示成播放状态但不出声。
    @ObservationIgnored private let demo: DemoOptions?

    private enum Keys {
        static let config = "metronome.config.v2"
        static let training = "metronome.training"
        static let preset = "metronome.preset"
        static let haptics = "metronome.haptics"
        static let goalDay = "metronome.goalReachedDay"
    }

    init(demo: DemoOptions? = nil) {
        let defaults = UserDefaults.standard
        var loaded = MetronomeConfig.default
        var loadedTraining = TrainingOptions()
        if demo == nil {
            if let data = defaults.data(forKey: Keys.config),
               let saved = try? JSONDecoder().decode(MetronomeConfig.self, from: data) {
                loaded = saved
            }
            if let data = defaults.data(forKey: Keys.training),
               let saved = try? JSONDecoder().decode(TrainingOptions.self, from: data) {
                loadedTraining = saved
            }
        }
        if let demo {
            loaded = demo.config
            loadedTraining = demo.training
        }
        loaded.training = loadedTraining.plan(baseBPM: Int(loaded.bpm))
        config = loaded
        training = loadedTraining
        audio = AudioEngineHost(config: loaded)
        sounds = DynamicSounds(loadFromDisk: demo == nil)
        self.demo = demo
        if let raw = defaults.object(forKey: Keys.preset) as? Int, let p = AccentPreset(rawValue: raw) { lastPreset = p }
        if defaults.object(forKey: Keys.haptics) != nil { hapticsEnabled = defaults.bool(forKey: Keys.haptics) }

        if let demo {
            isPlaying = demo.playing
            currentBeat = demo.beat
            currentSub = demo.beat == nil ? nil : demo.sub
            elapsedSeconds = demo.elapsed
            liveBar = demo.liveBar
            liveBPM = demo.liveBPM
            todaySeconds = demo.todaySeconds ?? 0
        }

        for (slot, clip) in sounds.allSlots {
            audio.setDynamic(slot: slot, samples: clip.samples, rate: clip.rate)
        }
        sounds.onChange = { [weak self] slot, clip in
            self?.audio.setDynamic(slot: slot, samples: clip?.samples, rate: clip?.rate ?? 48_000)
        }
        if demo == nil, loaded.sound == .voice { sounds.prepareCount(language: AppLanguage.resolved) }

        audio.onForcedStop = { [weak self] reason in
            log.info("forced stop: \(reason, privacy: .public)")
            self?.stop()
        }
        nowPlaying.connect(
            play: { [weak self] in self?.start() },
            pause: { [weak self] in self?.stop() },
            toggle: { [weak self] in self?.togglePlay() }
        )
    }

    // MARK: 播放

    func togglePlay() {
        if previewWork != nil {
            // 试听中点了播放：取消自动停止，接着播
            previewWork?.cancel()
            previewWork = nil
            return
        }
        isPlaying ? stop() : start()
    }

    /// 选音色：人声报数先按界面语言生成；没在播放时试听一小节（最长 3 秒）。
    func selectSound(_ sound: SoundKind) {
        config.sound = sound
        if sound == .voice { sounds.prepareCount(language: AppLanguage.resolved) }
        guard demo == nil else { return }
        if isPlaying && previewWork == nil { return }   // 正在练习：下一拍就换成新音色
        previewWork?.cancel()
        if !isPlaying { start() }
        guard isPlaying else { return }
        let bar = Double(config.timeSignature.beatsPerBar) * 60 / max(config.bpm, 40)
        let work = DispatchWorkItem { [weak self] in
            self?.previewWork = nil
            self?.stop()
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(bar, 3) + 0.1, execute: work)
    }

    /// 界面语言变了：用到人声报数时重新生成。
    func languageChanged() {
        if config.sound == .voice { sounds.prepareCount(language: AppLanguage.resolved) }
    }

    func start() {
        guard !isPlaying else { return }
        if demo != nil { isPlaying = true; return }
        onWillStart?()
        do {
            try audio.start(config: config)
        } catch {
            lastError = String(localized: "无法启动音频：\(error.localizedDescription)", bundle: .appLanguage, locale: .appLanguage)
            return
        }
        isPlaying = true
        log.info("start bpm=\(self.bpm) training=\(String(describing: self.config.training?.mode), privacy: .public)")
        shownSerial = -1
        hapticSerial = -1
        shownClick = -1
        currentBeat = nil
        currentSub = nil
        playingSubdivision = nil
        liveBar = nil
        liveBPM = nil
        playStartedAt = CACurrentMediaTime()
        sessionStart = Date()
        sessionMode = config.training?.mode ?? .free
        let startBPM = config.training?.bpm(atBar: 0) ?? bpm
        sessionBPM = startBPM...startBPM
        refreshTodayBaseline()
        if hapticsEnabled { haptics.prepare() }
        startClocks()
        nowPlaying.update(config: config, isPlaying: true)
    }

    /// - forRecording: 马上停引擎、不释放音频会话，把它交给调音器。
    func stop(forRecording: Bool = false) {
        previewWork?.cancel()
        previewWork = nil
        guard isPlaying else { return }
        isPlaying = false
        if demo != nil { return }
        audio.stop(immediately: forRecording)
        haptics.stop()
        stopClocks()
        let played = CACurrentMediaTime() - playStartedAt
        log.info("stop after \(played) s, forRecording=\(forRecording)")
        elapsedBase += played
        elapsedSeconds = Int(elapsedBase)
        currentBeat = nil
        currentSub = nil
        playingSubdivision = nil
        liveBar = nil
        liveBPM = nil
        recordPractice(duration: played)
        nowPlaying.update(config: config, isPlaying: false)
    }

    func resetTimer() {
        elapsedBase = 0
        playStartedAt = CACurrentMediaTime()
        elapsedSeconds = 0
    }

    // MARK: 修改设置（播放中都在下一拍生效）

    var bpm: Int {
        get { Int(config.bpm.rounded()) }
        set { config.bpm = Double(newValue) }
    }

    /// 开了渐进提速时速度由训练方案控制，主界面的圆环只显示不让改。
    var tempoIsControlledByTraining: Bool { training.rampEnabled }

    /// 主界面显示的速度：提速训练中显示实际速度。
    var displayBPM: Int {
        if tempoIsControlledByTraining { return liveBPM ?? training.ramp.startBPM }
        return bpm
    }

    func nudge(_ delta: Int) {
        guard !tempoIsControlledByTraining else { return }
        bpm = min(max(bpm + delta, Tempo.minimum), Tempo.maximum)
    }

    func tap() {
        guard !tempoIsControlledByTraining else { return }
        if let value = tapTempo.tap(at: CACurrentMediaTime()) {
            bpm = Int(value.rounded())
        }
    }

    func cycleAccent(at index: Int) {
        guard index < config.accents.count else { return }
        config.accents[index] = config.accents[index].cycled
    }

    func setTimeSignature(_ ts: TimeSignature) {
        guard ts != config.timeSignature else { return }
        config.setTimeSignature(ts, preset: lastPreset)
    }

    func applyPreset(_ preset: AccentPreset) {
        lastPreset = preset
        config.accents = preset.pattern(for: config.timeSignature)
    }

    /// 当前重音和哪个预设一致（都不一致返回 nil）。
    var matchingPreset: AccentPreset? {
        let matches = AccentPreset.allCases.filter { $0.pattern(for: config.timeSignature) == config.accents }
        return matches.contains(lastPreset) ? lastPreset : matches.first
    }

    func select(_ subdivision: Subdivision) {
        config.subdivision = subdivision
    }

    private func refreshTrainingPlan() {
        let plan = training.plan(baseBPM: bpm)
        if config.training != plan { config.training = plan }
    }

    // MARK: 按音频时钟刷新当前拍、排程触感

    private func startClocks() {
        stopClocks()
        let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.tick() }, selector: #selector(DisplayLinkProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        // 显示刷新在后台会停；计时、练习目标、训练结束这些靠这个 1 秒的钟（后台播放时主线程照常运行）
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private func stopClocks() {
        displayLink?.invalidate()
        displayLink = nil
        clock?.invalidate()
        clock = nil
    }

    private func tick() {
        var snap = audio.snapshot.value
        if snap.playToken != audio.currentPlayToken {
            snap = BeatSnapshot()  // 还是上一次播放留下的数据，先不用
        }
        let now = CACurrentMediaTime()
        // 切分格：已经到点的最新一个点（主拍或切分点）
        if let click = Self.soundingClick(snap.clicks, now: now, after: shownClick) {
            shownClick = click.order
            if currentSub != click.subIndex { currentSub = click.subIndex }
            if playingSubdivision != click.subdivision { playingSubdivision = click.subdivision }
        }
        for mark in snap.marks.sorted(by: { $0.serial < $1.serial }) {
            // 已经到点的最新一拍就是“当前拍”
            if mark.hostTime <= now, mark.serial > shownSerial {
                shownSerial = mark.serial
                if currentBeat != mark.beatInBar { currentBeat = mark.beatInBar }
                if liveBar != mark.bar { liveBar = mark.bar }
                let b = Int(mark.bpm.rounded())
                if liveBPM != b { liveBPM = b }
                sessionBPM = min(sessionBPM.lowerBound, b)...max(sessionBPM.upperBound, b)
            }
            // 还有 70 ms 内就要响的拍，交给触感引擎在同一时刻震动
            if hapticsEnabled, mark.serial > hapticSerial, mark.hostTime - now < 0.07 {
                hapticSerial = mark.serial
                if mark.hostTime - now > -0.015 {
                    haptics.play(mark.accent, atHostTime: mark.hostTime)
                }
            }
        }
        let played = now - playStartedAt
        let total = Int(elapsedBase + played)
        if total != elapsedSeconds { elapsedSeconds = total }
        let today = Int(todayBaseline + played)
        if today != todaySeconds {
            todaySeconds = today
            checkPracticeGoal()
        }
        if snap.finished {
            stop()
            showBanner(String(localized: "渐进提速完成，已停止", bundle: .appLanguage, locale: .appLanguage))
        }
    }

    /// 已经到点（hostTime ≤ now）、比上次显示的更新的最后一个点；没有就是 nil。
    nonisolated static func soundingClick(_ clicks: [ClickMark], now: Double, after shown: Int64) -> ClickMark? {
        clicks.filter { $0.hostTime <= now && $0.order > shown }.max { $0.order < $1.order }
    }

    // MARK: 练习记录与练习目标

    func recordPractice(duration: TimeInterval) {
        guard let modelContext else { return }
        if PracticeRecording.record(startedAt: sessionStart, duration: duration, bpmRange: sessionBPM,
                                    mode: sessionMode, in: modelContext) != nil {
            try? modelContext.save()
        }
        refreshTodayBaseline()
    }

    private func refreshTodayBaseline() {
        guard demo?.todaySeconds == nil else { return }
        guard let modelContext else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.startedAt >= start })
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        todayBaseline = sessions.filter { PracticeRecording.shouldRecord(duration: $0.duration) }.reduce(0) { $0 + $1.duration }
        if !isPlaying { todaySeconds = Int(todayBaseline) }
    }

    /// 练习目标：今天累计到点时提醒一次（每天一次），可选自动停止。
    private func checkPracticeGoal() {
        guard training.timerEnabled, todaySeconds >= training.timerMinutes * 60 else { return }
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        guard UserDefaults.standard.string(forKey: Keys.goalDay) != day else { return }
        UserDefaults.standard.set(day, forKey: Keys.goalDay)
        let goal = Units.minutes(training.timerMinutes)
        let message = training.autoStop ? String(localized: "今天已练够 \(goal)，已自动停止", bundle: .appLanguage, locale: .appLanguage)
                                        : String(localized: "今天已练够 \(goal)", bundle: .appLanguage, locale: .appLanguage)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showBanner(message)
        if UIApplication.shared.applicationState != .active {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "练习目标完成", bundle: .appLanguage, locale: .appLanguage)
            content.body = message
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "practice-goal", content: content, trigger: nil))
        }
        if training.autoStop { stop() }
    }

    /// 打开练习计时时请求通知权限（后台播放时到点也能提醒）。
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func showBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { banner = nil }
        }
    }

    private func save() {
        if demo == nil, let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Keys.config)
        }
    }

    private func saveTraining() {
        if demo == nil, let data = try? JSONEncoder().encode(training) {
            UserDefaults.standard.set(data, forKey: Keys.training)
        }
    }
}

/// CADisplayLink 需要一个 NSObject 目标。
private final class DisplayLinkProxy: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

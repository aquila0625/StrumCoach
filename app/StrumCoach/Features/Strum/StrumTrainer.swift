import AVFoundation
import ChordKit
import MetronomeCore
import Observation
import QuartzCore
import SwiftData
import TunerKit
import UIKit

/// 扫弦节奏型跟练：选和弦和节奏型 → 听示范 → 跟我练（收音）→ 评分。
///
/// 时间都用主机时钟（秒，和 `CACurrentMediaTime` 同一时基）：
/// - 示范的扫弦用 ChordKit 的 `RhythmStrummer` 按主机时间预约，提前 `outputLatency` 发出，耳朵听到的正好在格子上；
/// - 录音的每个缓冲带主机时间，起音时间 = 缓冲时间 + 采样位置 ÷ 采样率 − `inputLatency` − 校准偏差；
/// - 画面高亮每帧按“现在”在时间线上的位置算，不用定时器。
@MainActor
@Observable
final class StrumTrainer {
    enum Phase: Equatable {
        case idle
        case demo
        /// 训练页卡片上的“听一听”：一小节，不倒数
        case preview
        case practice
        case calibrating
        case analyzing
    }

    // MARK: 选择

    /// 选中的节奏型 id（预设或自定义的）
    var patternID = StrumRhythm.folk1.id { didSet { save() } }
    /// 选中的节奏型；自定义的被删了就回到这件乐器的第一个预设。改了自定义的内容，这里也跟着变。
    var pattern: StrumRhythm {
        get { patterns.first { $0.id == patternID } ?? patterns[0] }
        set { patternID = newValue.id }
    }
    /// 当前的和弦进行（数量不限；只有一个和弦时就是单和弦练习）
    var progression = ChordProgression(name: "", chords: [ProgressionChord(root: 0, type: .major)]) {
        didSet { if !loading { progressions.saveCurrent(progression) } }
    }
    /// 用户命名保存的进行
    private(set) var savedProgressions: [ChordProgression] = []
    /// 跟练练几遍（一遍 = 整个和弦进行走一遍）；nil = 一直练，直到点“结束”
    var practiceTarget: Int? { didSet { save() } }
    /// 节奏型的收藏、已掌握（按乐器分）
    private(set) var marks: RhythmMarks
    /// 节奏型列表的筛选：全部 / 收藏 / 未掌握
    var filter: RhythmMarks.Filter = .all { didSet { save() } }
    /// 换乐器时：当前节奏型不在这件乐器的推荐列表里，就换成它的默认节奏型（尤克里里是岛屿扫弦）
    var instrumentID = "guitar" {
        didSet {
            if !loading, !patterns.contains(where: { $0.id == patternID }) { patternID = patterns[0].id }
            save()
        }
    }

    /// 当前乐器能用的节奏型：收藏的在前，然后没掌握的，已掌握的最后；同一组里预设在前、自定义在后
    var patterns: [StrumRhythm] { marks.sorted(StrumRhythm.available(for: instrument.family, library: library), family: instrument.family) }
    /// 按筛选显示的节奏型（可能为空，比如还没有收藏）
    var visiblePatterns: [StrumRhythm] { marks.filtered(patterns, by: filter, family: instrument.family) }
    /// 和弦库：自定义节奏型存在那里（两边共用）
    @ObservationIgnored let library: ChordLibraryModel?
    /// 速度；改用 `setBPM` 才会限制在范围内（@Observable 的属性不能在 didSet 里给自己赋值）
    private(set) var bpm = 80
    static let bpmRange = 40...180

    func setBPM(_ value: Int) { bpm = min(max(value, Self.bpmRange.lowerBound), Self.bpmRange.upperBound) }
    /// 跟练每遍至少几小节（进行太短时循环补足）
    static let minPracticeBars = 4

    var instrument: Instrument { ChordLibrary.strummableInstruments.first { $0.id == instrumentID } ?? ChordLibrary.strummableInstruments[0] }
    /// 进行里第 i 个和弦用和弦库默认的第一个把位
    func voicing(at i: Int) -> ChordVoicing? {
        guard progression.chords.indices.contains(i) else { return nil }
        return ChordLibrary.voicings(for: progression.chords[i].chord, instrument: instrument).first
    }

    /// 和弦名的写法（界面按“音名显示”设置传进来）
    @ObservationIgnored var chordName: (Chord) -> String = { $0.name }

    // MARK: 运行状态（界面读）

    private(set) var phase: Phase = .idle
    /// 当前的时间线（示范、跟练或校准）；画面按它高亮
    private(set) var timeline: StrumTimeline?
    /// 正在第几小节第几格
    private(set) var position: (bar: Int, step: Int)?
    /// 倒数：3、2、1……（还没到第一格时）
    private(set) var countIn: Int?
    private(set) var score: StrumScore?
    /// 这次结果对应的节奏型（结果页按它画格子）
    private(set) var scoredTimeline: StrumTimeline?
    /// 这次结果的分段成绩（按和弦）
    private(set) var report: ProgressionReport?
    /// 本次示范 / 跟练每小节弹哪个和弦
    private(set) var plan: ProgressionPlan?
    /// 正在弹进行里的第几个和弦（倒数时是第一个）
    var currentChordIndex: Int? {
        guard let plan, isBusy, phase != .calibrating else { return nil }
        return plan.chordIndex(atBar: position?.bar ?? 0)
    }
    /// 下一个要换的和弦（后面没有换和弦了就是 nil；循环时接着看下一遍的开头）
    var nextChordIndex: Int? {
        guard let plan, let cur = currentChordIndex else { return nil }
        let bar = position?.bar ?? 0
        let ahead = Array(bar + 1..<plan.bars) + (willLoop ? Array(0..<plan.bars) : [])
        return ahead.first { plan.chordIndex(atBar: $0) != cur }.map { plan.chordIndex(atBar: $0) }
    }
    /// 这一遍之后还有下一遍（示范、听一听一直循环；跟练看遍数）
    private var willLoop: Bool {
        switch phase {
        case .demo, .preview: return true
        case .practice: return run?.needsPass(after: pass) ?? false
        default: return false
        }
    }
    /// 正在第几遍（从 1 起）
    private(set) var pass = 1
    /// 这次跟练（遍数、每遍的成绩）；结果页也用它画逐遍分数
    private(set) var run: PracticeRun?
    /// 刚练完的那一遍的分数（跟练时小字显示，不打断）
    private(set) var lastPass: (pass: Int, score: Int)?
    /// 结果页格子：最后一遍的成绩（总的准 / 偏 / 漏在 `score` 里，是所有遍加起来的）
    private(set) var gridScore: StrumScore?
    /// 连续 3 次 ≥ 90 分：建议把这个节奏型标记为已掌握（用户确认才标）
    private(set) var masterySuggestion: StrumRhythm?
    /// 换和弦前一拍：提示用户提前换把（下一个和弦块闪一下）
    private(set) var changeIsComing = false
    private(set) var message: String?
    /// 戴着耳机：跟练时同时放节拍声
    private(set) var headphones = false
    /// 用户校准出来的额外延迟（秒，正数 = 检测到的起音比实际晚，要减掉）
    private(set) var latencyOffset: Double

    // MARK: 内部

    @ObservationIgnored private var strummer: RhythmStrummer?
    @ObservationIgnored private let clicker = ClickPlayer()
    @ObservationIgnored private var recorder: InputRecorder?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var finishWork: Task<Void, Never>?
    /// 循环：提前排好下一遍的声音，到点（tick 里）换成下一遍的时间线
    @ObservationIgnored private var loopWork: Task<Void, Never>?
    @ObservationIgnored private var upcoming: StrumTimeline?
    /// 跟练里每一遍的时间线（打分时用相邻遍的第一下 / 最后一下当护栏）
    @ObservationIgnored private var passTimelines: [StrumTimeline] = []
    @ObservationIgnored private var hapticBeats: [Double] = []
    @ObservationIgnored private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loading = true
    @ObservationIgnored var modelContext: ModelContext?
    private(set) var history: StrumHistory

    @ObservationIgnored private let progressions: ProgressionStore
    @ObservationIgnored private let marksStore: RhythmMarksStore

    private enum Keys {
        static let pattern = "strum.pattern", root = "strum.root", type = "strum.type", instrument = "strum.instrument"
        static let latency = "strum.latencyOffset", target = "strum.practiceTarget", filter = "strum.rhythmFilter"
    }

    init(bpm: Int, library: ChordLibraryModel? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.library = library
        history = StrumHistory(defaults: defaults)
        latencyOffset = defaults.double(forKey: Keys.latency)
        self.bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        progressions = ProgressionStore(defaults: defaults)
        marksStore = RhythmMarksStore(defaults: defaults)
        marks = marksStore.load()
        if let id = defaults.string(forKey: Keys.pattern) { patternID = id }
        if let saved = progressions.loadCurrent(), !saved.chords.isEmpty {
            progression = saved
        } else {
            // 旧版只存了一个和弦：用它开头
            let type = defaults.string(forKey: Keys.type).flatMap { t in ChordType.builtins.first { $0.id == t } } ?? .major
            progression = ChordProgression(name: "", chords: [ProgressionChord(root: defaults.integer(forKey: Keys.root), type: type)])
        }
        savedProgressions = progressions.loadSaved()
        let target = defaults.integer(forKey: Keys.target)
        practiceTarget = target > 0 ? target : nil
        filter = defaults.string(forKey: Keys.filter).flatMap(RhythmMarks.Filter.init(rawValue:)) ?? .all
        if let i = defaults.string(forKey: Keys.instrument) { instrumentID = i }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        defaults.set(patternID, forKey: Keys.pattern)
        defaults.set(instrumentID, forKey: Keys.instrument)
        defaults.set(practiceTarget ?? 0, forKey: Keys.target)
        defaults.set(filter.rawValue, forKey: Keys.filter)
    }

    // MARK: 收藏、已掌握

    func isFavorite(_ r: StrumRhythm) -> Bool { marks.isFavorite(r.id, family: instrument.family) }
    func isMastered(_ r: StrumRhythm) -> Bool { marks.isMastered(r.id, family: instrument.family) }

    func setFavorite(_ on: Bool, _ r: StrumRhythm) {
        marks.setFavorite(on, r.id, family: instrument.family)
        marksStore.save(marks)
    }

    func setMastered(_ on: Bool, _ r: StrumRhythm) {
        marks.setMastered(on, r.id, family: instrument.family)
        marksStore.save(marks)
    }

    /// 回答“标记为已掌握？”：标或者不标（不标的以后不再问）
    func answerMastery(_ accept: Bool) {
        guard let r = masterySuggestion else { return }
        if accept { marks.setMastered(true, r.id, family: instrument.family) } else { marks.decline(r.id, family: instrument.family) }
        marksStore.save(marks)
        masterySuggestion = nil
    }

    // MARK: 和弦进行：套用、保存

    /// 套用一个常用进行或保存过的进行（复制一份，之后的编辑不影响原来的）
    func apply(_ p: ChordProgression) {
        var copy = p
        copy.id = UUID()
        copy.chords = p.chords.map { var c = $0; c.id = UUID(); return c }
        progression = copy
    }

    /// 把当前进行命名保存（同名的覆盖）
    func saveProgression(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = progression
        copy.id = UUID()
        copy.name = trimmed
        progression.name = trimmed
        savedProgressions.removeAll { $0.name == trimmed }
        savedProgressions.append(copy)
        progressions.storeSaved(savedProgressions)
    }

    func deleteSaved(_ id: UUID) {
        savedProgressions.removeAll { $0.id == id }
        progressions.storeSaved(savedProgressions)
    }

    var isBusy: Bool { phase != .idle }

    // MARK: 听示范（一直循环）

    /// 倒数一小节（放节拍声），然后按节奏型把整个进行一遍接一遍地扫，直到点“停止”。
    func playDemo() { startLoop(.demo) }

    /// 训练页卡片上的“听一听”：不倒数，直接循环，直到点“停止”。只放不录，音频会话用 .playback，停了就交还给节拍器。
    func playPreview() { startLoop(.preview) }

    private func startLoop(_ kind: Phase) {
        guard phase == .idle, voicing(at: 0) != nil else { return }
        reset()
        let countIn = kind == .demo
        guard prepareStrummer(clicks: countIn, recording: kind == .demo) else { return }
        let plan = ProgressionPlan(progression)
        let tl = countIn ? makeTimeline(bars: plan.bars, lead: 0.4)
                         : StrumTimeline(pattern: pattern, bpm: Double(bpm), start: CACurrentMediaTime() + 0.15, bars: plan.bars)
        if countIn {
            let out = AVAudioSession.sharedInstance().outputLatency
            for (i, t) in tl.countInBeats.enumerated() { clicker.click(accent: i == 0, at: t - out) }
        }
        scheduleStrums(tl, plan: plan)
        self.plan = plan
        begin(kind, timeline: tl, haptics: [])
        loopWork = Task { [weak self] in
            var current = tl
            while let self, !Task.isCancelled {
                // 提前半秒排好下一遍的声音，接得上、没有空隙；到点由 tick 换成下一遍的时间线
                await Self.sleep(until: current.end - Self.scheduleAhead)
                guard !Task.isCancelled, self.phase == kind else { return }
                let next = current.following()
                self.scheduleStrums(next, plan: plan)
                self.upcoming = next
                current = next
                await Self.sleep(until: current.start)
            }
        }
    }

    /// 提前多久排下一遍
    static let scheduleAhead = 0.5

    private static func sleep(until time: Double) async {
        let wait = time - CACurrentMediaTime()
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
    }

    private func prepareStrummer(clicks: Bool, recording: Bool) -> Bool {
        do {
            try configureSession(recording: recording)
            let strummer = strummer ?? RhythmStrummer(maxVoices: 12)
            strummer.configuresAudioSession = false
            try strummer.prepare()
            self.strummer = strummer
            if clicks { try clicker.prepare() }
            return true
        } catch {
            message = String(localized: "无法启动音频：\(error.localizedDescription)", bundle: .appLanguage, locale: .appLanguage)
            return false
        }
    }

    /// 按时间线预约每一下扫弦（提前输出延迟发出），力度用节奏型自己的重音
    private func scheduleStrums(_ tl: StrumTimeline, plan: ProgressionPlan) {
        let out = AVAudioSession.sharedInstance().outputLatency
        let voicings = progression.chords.indices.map { voicing(at: $0) }
        for s in tl.strokes {
            let i = plan.chordIndex(atBar: s.bar)
            guard let voicing = voicings[i] else { continue }
            // B 只拨根音弦，D 从根音弦扫到 1 弦，d 和 U 只扫高音弦，X 闷音
            strummer?.strum(voicing, instrument: instrument, chord: progression.chords[i].chord, cell: s.stroke,
                            velocity: tl.pattern.velocity(ofCell: s.step),
                            at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: s.time - out)))
        }
    }

    // MARK: 跟我练

    /// 倒数一小节后收音，一遍接一遍（一遍 = 整个进行，不到 4 小节时循环补足）。
    /// 填了遍数就练够自动结束；没填就一直练，直到点“结束”。每遍练完单独打分，跟练时小字显示。
    /// 外放时不放节拍声（只看屏幕、倒数时震动）；戴耳机才放节拍声。
    func startPractice() async {
        guard phase == .idle else { return }
        reset()
        guard await ensureMicrophone() else { return }
        do {
            try configureSession()
            headphones = Self.headphonesConnected()
            if headphones { try clicker.prepare() }
            let recorder = InputRecorder()
            try recorder.start()
            self.recorder = recorder
        } catch {
            message = String(localized: "无法打开麦克风：\(error.localizedDescription)", bundle: .appLanguage, locale: .appLanguage)
            stopAudio()
            return
        }
        let plan = ProgressionPlan(progression, minBars: Self.minPracticeBars)
        let tl = makeTimeline(bars: plan.bars, lead: 0.6)
        self.plan = plan
        run = PracticeRun(target: practiceTarget, passBars: plan.bars)
        passTimelines = [tl]
        scheduleGuideClicks(tl, countIn: true)
        begin(.practice, timeline: tl, haptics: tl.countInBeats)
        loopWork = Task { [weak self] in await self?.practiceLoop() }
    }

    private func practiceLoop() async {
        var graded = 0
        while !Task.isCancelled, phase == .practice, let run {
            let current = passTimelines[graded]
            // 还要下一遍：提前排好它的节拍声，到点由 tick 换过去
            if graded == passTimelines.count - 1, run.needsPass(after: passTimelines.count) {
                await Self.sleep(until: current.end - Self.scheduleAhead)
                guard !Task.isCancelled, phase == .practice else { return }
                let next = current.following()
                scheduleGuideClicks(next, countIn: false)
                passTimelines.append(next)
                upcoming = next
            }
            // 这一遍结束后再等一下（最后一下可能扫得偏慢）就打分
            await Self.sleep(until: current.end + StrumScore.offWindow + 0.05)
            guard !Task.isCancelled, phase == .practice else { return }
            await gradePass(graded)
            guard !Task.isCancelled, phase == .practice else { return }
            graded += 1
            if self.run?.isComplete == true {
                finishPractice()
                return
            }
        }
    }

    /// 给第 k 遍打分：只取这一遍前后一小段录音做起音检测，用相邻遍挨着的那一下当护栏
    private func gradePass(_ k: Int) async {
        guard let recorder, passTimelines.indices.contains(k) else { return }
        let tl = passTimelines[k]
        let capture = recorder.segment(from: tl.start - StrumScore.offWindow - 0.4, to: tl.end + StrumScore.offWindow + 0.05)
        let inputLatency = AVAudioSession.sharedInstance().inputLatency
        let offset = latencyOffset
        let sensitive = Self.bassWindows(tl, delay: inputLatency + offset)
        let onsets = await Task.detached(priority: .userInitiated) {
            capture.onsetTimes(sensitive: sensitive).map { $0 - inputLatency - offset }
        }.value
        guard !Task.isCancelled, phase == .practice else { return }
        var guards: [Double] = []
        if k > 0, let last = passTimelines[k - 1].strokes.last { guards.append(last.time) }
        if k + 1 < passTimelines.count, let first = passTimelines[k + 1].strokes.first { guards.append(first.time) }
        let result = StrumScore.grade(tl, onsets: onsets, guards: guards)
        run?.add(result)
        lastPass = (k + 1, result.score)
        // 打过分的录音不再需要（一直练时不让内存越积越多）
        recorder.discard(before: tl.end - 1)
    }

    /// 根音单拨（B）附近 ±120 ms 的时间段，换算到录音的时钟（录到的声音比实际晚 `delay` 秒）
    nonisolated static func bassWindows(_ tl: StrumTimeline, delay: Double) -> [ClosedRange<Double>] {
        tl.strokes.filter { $0.stroke == .bass }.map { s in
            (s.time + delay - StrumScore.offWindow)...(s.time + delay + StrumScore.offWindow)
        }
    }

    /// 结束跟练：点“结束”、练够遍数、或离开页面。只算已经练完的遍；一遍都没练完就不出成绩。
    func endPractice() {
        guard phase == .practice else { return }
        finishPractice()
    }

    private func finishPractice() {
        loopWork?.cancel()
        loopWork = nil
        clicker.stopAll()
        stopAudio()
        stopDisplayLink()
        upcoming = nil
        position = nil
        countIn = nil
        changeIsComing = false
        phase = .idle
        guard let run, let combined = run.combined, let plan else { return }
        let last = passTimelines[run.passes.count - 1]
        score = combined
        gridScore = run.passes.last
        scoredTimeline = last
        report = ProgressionReport.make(score: combined, timeline: last, plan: plan.repeated(run.passes.count),
                                        names: progression.chords.map { chordName($0.chord) })
        record(run, timeline: last)
    }

    // MARK: 延迟校准

    /// 跟着节拍（看屏幕或听耳机）在每一拍扫一下或拍一下琴身，8 拍；取平均偏差存起来，以后跟练都减掉。
    func calibrate() async {
        guard phase == .idle else { return }
        reset()
        guard await ensureMicrophone() else { return }
        do {
            try configureSession()
            headphones = Self.headphonesConnected()
            if headphones { try clicker.prepare() }
            let recorder = InputRecorder()
            try recorder.start()
            self.recorder = recorder
        } catch {
            message = String(localized: "无法打开麦克风：\(error.localizedDescription)", bundle: .appLanguage, locale: .appLanguage)
            stopAudio()
            return
        }
        let now = CACurrentMediaTime()
        let beat = 60.0 / 90
        let tl = StrumTimeline(pattern: .quarters, bpm: 90, start: now + 0.6 + beat * 4, bars: 2)
        scheduleGuideClicks(tl, countIn: true)
        begin(.calibrating, timeline: tl, haptics: tl.countInBeats)
        finish(after: tl.end + 0.35) { trainer in
            await trainer.analyzeCalibration(tl)
        }
    }

    /// 演示模式（截图）：直接给一份样例成绩。
    func showSample() {
        let plan = ProgressionPlan(progression, minBars: Self.minPracticeBars)
        let tl = StrumTimeline(pattern: pattern, bpm: Double(bpm), start: 0, bars: plan.bars)
        var run = PracticeRun(target: nil, passBars: plan.bars)
        // 一直练了 4 遍，越练越准
        for k in 0..<4 {
            var onsets = tl.strokes.map(\.time)
            for i in onsets.indices {
                // 确定性的偏差：大多准，上扫略慢，偶尔漏一下、多扫一下
                let s = tl.strokes[i]
                let loose = Double(3 - k) * 0.012
                onsets[i] += (s.stroke == .up ? 0.03 + loose : 0.008) + (0.01 + loose / 2) * sin(Double(i + k) * 1.7) + (i % 9 == 4 ? 0.05 : 0)
            }
            // 换到第 4 个和弦时晚一些（展示“换和弦处偏慢”的建议）
            for (i, s) in tl.strokes.enumerated() where plan.changeBars.contains(s.bar) && s.step == 0 && plan.chordIndex(atBar: s.bar) == min(3, progression.chords.count - 1) {
                onsets[i] += 0.07
            }
            for m in 0..<(3 - k) { onsets.remove(at: 5 + m * 4) }
            if k < 2 { onsets.append(tl.strokes[14].time + 0.16) }
            run.add(StrumScore.grade(tl, onsets: onsets))
        }
        self.run = run
        score = run.combined
        gridScore = run.passes.last
        scoredTimeline = tl
        self.plan = plan
        if let combined = run.combined {
            report = ProgressionReport.make(score: combined, timeline: tl, plan: plan.repeated(run.passes.count),
                                            names: progression.chords.map { chordName($0.chord) })
        }
    }

    /// 演示模式：停在“收音中”某一格（截图用），不发声。
    func showSampleProgress(step: Int) {
        let plan = ProgressionPlan(progression, minBars: Self.minPracticeBars)
        let tl = StrumTimeline(pattern: pattern, bpm: Double(bpm), start: 0, bars: plan.bars)
        self.plan = plan
        timeline = tl
        phase = .practice
        run = PracticeRun(target: nil, passBars: plan.bars)
        pass = 2
        lastPass = (1, 86)
        position = (0, min(step, pattern.cells.count - 1))
        changeIsComing = true
    }

    /// 演示模式（截图）：-demoPattern 选节奏型，-demoProgression 选常用进行（5 是 12 小节布鲁斯），
    /// -demoSheet strum 停在“收音中”，strum-result 显示样例成绩，strum-edit 停在编辑和弦进行。
    static func demo(library: ChordLibraryModel, sheet: String?) -> StrumTrainer {
        let trainer = StrumTrainer(bpm: 80, library: library, defaults: UserDefaults(suiteName: "demo.strum") ?? .standard)
        trainer.patternID = UserDefaults.standard.string(forKey: "demoPattern") ?? "folk1"
        let presets = ChordProgression.presets
        trainer.apply(presets[min(max(UserDefaults.standard.integer(forKey: "demoProgression"), 0), presets.count - 1)])
        switch sheet {
        case "strum": trainer.showSampleProgress(step: 3)
        case "strum-result": trainer.showSample()
        default: break
        }
        // 训练页卡片上的“上次 / 最高”分
        if trainer.history.entries.isEmpty {
            for (days, score) in [(3, 72), (1, 88), (0, 84)] {
                trainer.history.add(StrumHistory.Entry(date: Date().addingTimeInterval(Double(-days) * 86_400), patternID: trainer.patternID,
                                                       chord: "C–G–Am–F", bpm: 80, score: score))
            }
        }
        return trainer
    }

    /// 测试用：不碰音频，假装正在跟练、已经练完了这些遍
    func simulatePractice(passes: [StrumScore], target: Int?) {
        let plan = ProgressionPlan(progression, minBars: Self.minPracticeBars)
        self.plan = plan
        var run = PracticeRun(target: target, passBars: plan.bars)
        passes.forEach { run.add($0) }
        self.run = run
        let first = StrumTimeline(pattern: pattern, bpm: Double(bpm), start: 0, bars: plan.bars)
        passTimelines = [first]
        while passTimelines.count < max(1, passes.count) { passTimelines.append(passTimelines[passTimelines.count - 1].following()) }
        phase = .practice
    }

    func resetCalibration() {
        latencyOffset = 0
        defaults.set(0.0, forKey: Keys.latency)
    }

    // MARK: 停止

    /// 停下示范、听一听或校准；跟练中途停下时，已经练完的遍照样出成绩、记进历史。
    func stop() {
        if phase == .practice {
            finishPractice()
        }
        let wasPreview = phase == .preview
        finishWork?.cancel()
        finishWork = nil
        loopWork?.cancel()
        loopWork = nil
        upcoming = nil
        strummer?.stopAll()
        clicker.stopAll()
        stopAudio()
        stopDisplayLink()
        phase = .idle
        position = nil
        countIn = nil
        changeIsComing = false
        // 听一听只放不录：停了就把音频会话交还给节拍器
        if wasPreview { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    /// 离开页面、切到别的标签、App 进后台：立刻停掉一切、关掉麦克风，把音频会话还给节拍器
    /// （它下次播放时会按 .playback 重建引擎）。跟练中途离开的，已练完的遍仍记成绩。
    func teardown() {
        stop()
        strummer?.stopAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 内部流程

    private func reset() {
        message = nil
        score = nil
        gridScore = nil
        scoredTimeline = nil
        report = nil
        run = nil
        lastPass = nil
        pass = 1
        upcoming = nil
        passTimelines = []
        masterySuggestion = nil
        changeIsComing = false
        position = nil
        countIn = nil
    }

    private func makeTimeline(bars: Int, lead: Double) -> StrumTimeline {
        let beat = 60.0 / Double(bpm)
        let start = CACurrentMediaTime() + lead + beat * Double(pattern.beatsPerBar)
        return StrumTimeline(pattern: pattern, bpm: Double(bpm), start: start, bars: bars)
    }

    /// 戴耳机时：倒数和收音期间每拍一下节拍声（第一拍重音）。外放时不放，免得麦克风收进去。
    private func scheduleGuideClicks(_ tl: StrumTimeline, countIn: Bool) {
        guard headphones else { return }
        let out = AVAudioSession.sharedInstance().outputLatency
        if countIn {
            for (i, t) in tl.countInBeats.enumerated() { clicker.click(accent: i == 0, at: t - out) }
        }
        let beats = tl.bars * tl.pattern.beatsPerBar
        for b in 0..<beats {
            clicker.click(accent: b % tl.pattern.beatsPerBar == 0, at: tl.start + tl.beatDuration * Double(b) - out)
        }
    }

    private func begin(_ phase: Phase, timeline: StrumTimeline, haptics: [Double]) {
        self.phase = phase
        self.timeline = timeline
        hapticBeats = haptics
        haptic.prepare()
        startDisplayLink()
    }

    /// 到点后做收尾（Task.sleep 只决定“什么时候收尾”，节拍和高亮都按音频时钟算）。
    private func finish(after time: Double, _ body: @escaping @MainActor (StrumTrainer) async -> Void) {
        finishWork?.cancel()
        finishWork = Task { [weak self] in
            let wait = max(0, time - CACurrentMediaTime())
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.stopDisplayLink()
            self.position = nil
            self.countIn = nil
            await body(self)
        }
    }

    /// 校准：整段录音做起音检测，和每一拍比
    private func analyzeCalibration(_ tl: StrumTimeline) async {
        phase = .analyzing
        guard let recorder else { phase = .idle; return }
        let capture = recorder.stop()
        self.recorder = nil
        stopAudio()
        let inputLatency = AVAudioSession.sharedInstance().inputLatency
        let onsets = await Task.detached(priority: .userInitiated) {
            capture.onsetTimes().map { $0 - inputLatency }
        }.value
        finishCalibration(tl, onsets: onsets)
        phase = .idle
    }

    private func finishCalibration(_ tl: StrumTimeline, onsets: [Double]) {
        // 每拍找最近的起音（±200 ms 内），至少 5 拍才算数
        let deltas = tl.strokes.compactMap { s -> Double? in
            onsets.map { $0 - s.time }.filter { abs($0) <= 0.2 }.min { abs($0) < abs($1) }
        }
        guard deltas.count >= 5 else {
            message = String(localized: "没收到足够的声音（\(deltas.count)/8），请靠近手机、跟着每一拍扫一下再试一次。", bundle: .appLanguage, locale: .appLanguage)
            return
        }
        let sorted = deltas.sorted()
        let median = sorted[sorted.count / 2]
        latencyOffset = min(0.2, max(-0.2, median))
        defaults.set(latencyOffset, forKey: Keys.latency)
        message = String(localized: "已校准：以后跟练会扣掉 \(Int((latencyOffset * 1000).rounded())) 毫秒的延迟。", bundle: .appLanguage, locale: .appLanguage)
    }

    private func record(_ run: PracticeRun, timeline tl: StrumTimeline) {
        guard let average = run.averageScore else { return }
        // 成绩历史里存这次用的和弦进行（名字和和弦）、乐器和练了几遍；分数是各遍的平均
        let family = instrument.family
        history.add(StrumHistory.Entry(date: Date(), patternID: tl.pattern.id, chord: progression.label(chordName), bpm: Int(tl.bpm.rounded()),
                                       score: average, progressionName: progression.name.isEmpty ? nil : progression.name,
                                       chords: progression.chords.map { chordName($0.chord) },
                                       family: family.rawValue, passes: run.passes.count))
        // 连续 3 次 ≥ 90：问一下要不要标记为已掌握
        if marks.suggestsMastered(tl.pattern.id, family: family, history: history.entries) {
            masterySuggestion = tl.pattern
        }
        // 进练习记录（时长是收音的那几遍）
        if let modelContext {
            let duration = (tl.end - tl.start) * Double(run.passes.count)
            modelContext.insert(PracticeSession(startedAt: Date().addingTimeInterval(-duration), duration: duration,
                                                minBPM: Int(tl.bpm.rounded()), maxBPM: Int(tl.bpm.rounded()), mode: .strum))
            try? modelContext.save()
        }
    }

    // MARK: 画面时钟

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick() }, selector: #selector(DisplayLinkTarget.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // 循环：到了下一遍的开头就换成它的时间线
        if let next = upcoming, now >= next.start {
            timeline = next
            upcoming = nil
            pass += 1
        }
        guard let tl = timeline else { return }
        let pos = tl.position(at: now)
        if pos?.bar != position?.bar || pos?.step != position?.step { position = pos }
        // 倒数：还没到第一格时显示剩几拍
        let remaining = now < tl.start ? Int(ceil((tl.start - now) / tl.beatDuration)) : nil
        let shown = remaining.flatMap { $0 <= tl.pattern.beatsPerBar ? $0 : nil }
        if shown != countIn { countIn = shown }
        // 换和弦前一拍：下一个和弦块闪一下，提醒提前换把
        var coming = false
        if let plan, phase != .calibrating {
            let bar = pos?.bar ?? (now < tl.start ? -1 : plan.bars)
            // 最后一小节：后面还有下一遍时，看下一遍的第一个和弦
            let nextChord = bar + 1 < plan.bars ? plan.chordIndex(atBar: bar + 1) : (willLoop ? plan.chordIndex(atBar: 0) : nil)
            if bar >= 0, bar < plan.bars, let nextChord, nextChord != plan.chordIndex(atBar: bar) {
                let changeAt = tl.start + tl.barDuration * Double(bar + 1)
                coming = now >= changeAt - tl.beatDuration
            }
        }
        if coming != changeIsComing { changeIsComing = coming }
        // 倒数的每一拍震一下（外放跟练时的引导）
        if let first = hapticBeats.first, now >= first {
            hapticBeats.removeFirst()
            haptic.impactOccurred()
        }
    }

    // MARK: 音频会话、权限

    private func configureSession(recording: Bool = true) throws {
        let session = AVAudioSession.sharedInstance()
        // 外放走扬声器；蓝牙耳机用 A2DP 播放（录音仍用手机麦克风）。只放不录时用 .playback
        if recording {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        } else {
            try session.setCategory(.playback, mode: .default)
        }
        try session.setActive(true)
    }

    private func stopAudio() {
        recorder?.cancel()
        recorder = nil
    }

    private func ensureMicrophone() async -> Bool {
        var permission = MicrophonePermission.current()
        if permission == .notDetermined { permission = await MicrophonePermission.request() }
        if permission != .granted {
            message = String(localized: "需要麦克风权限才能听你扫弦：请到系统设置里允许“扫弦教练”使用麦克风。", bundle: .appLanguage, locale: .appLanguage)
            return false
        }
        return true
    }

    static func headphonesConnected() -> Bool {
        let wired: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { wired.contains($0.portType) }
    }
}

private final class DisplayLinkTarget {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}

// MARK: - 节拍声

/// 倒数和耳机里的节拍声：按主机时间预约的木鱼声。
@MainActor
final class ClickPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var strong: AVAudioPCMBuffer?
    private var weak: AVAudioPCMBuffer?
    private var prepared = false

    func prepare() throws {
        if !prepared {
            let sr = engine.outputNode.inputFormat(forBus: 0).sampleRate
            let rate = sr > 0 ? sr : 48_000
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            strong = Self.buffer(ClickSynth.make(.woodblock, .strong, sampleRate: rate), format: format)
            weak = Self.buffer(ClickSynth.make(.woodblock, .weak, sampleRate: rate), format: format)
            prepared = true
        }
        if !engine.isRunning { try engine.start() }
        node.play()
    }

    func click(accent: Bool, at seconds: Double) {
        guard prepared, let buffer = accent ? strong : weak else { return }
        let when = max(seconds, CACurrentMediaTime())
        node.scheduleBuffer(buffer, at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: when)), options: [], completionHandler: nil)
    }

    func stopAll() {
        guard prepared else { return }
        node.stop()
        node.play()
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return b
    }
}

// MARK: - 录音

/// 麦克风录音：每个缓冲连同它的主机时间一起存下，结束后整段做起音检测。
final class InputRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var chunks: [(time: Double, samples: [Float])] = []
    private var sampleRate: Double = 48_000

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain: "Strum", code: 1) }
        sampleRate = format.sampleRate
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let time = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : CACurrentMediaTime()
            self.lock.lock()
            self.chunks.append((time, samples))
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    /// 停止并交出录到的内容
    func stop() -> Capture {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return Capture(chunks: chunks, sampleRate: sampleRate)
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// 不停止录音，取出 [from, to] 这段时间（主机时钟秒）里的缓冲，用来给已经练完的一遍打分
    func segment(from: Double, to: Double) -> Capture {
        lock.lock()
        defer { lock.unlock() }
        let rate = sampleRate
        let picked = chunks.filter { c in
            let end = c.time + Double(c.samples.count) / rate
            return end >= from && c.time <= to
        }
        return Capture(chunks: picked, sampleRate: rate)
    }

    /// 丢掉 `time` 之前的录音（一直练时不让内存越积越多）
    func discard(before time: Double) {
        lock.lock()
        defer { lock.unlock() }
        let rate = sampleRate
        chunks.removeAll { $0.time + Double($0.samples.count) / rate < time }
    }

    struct Capture: Sendable {
        var chunks: [(time: Double, samples: [Float])]
        var sampleRate: Double

        /// 起音的主机时间（秒）：整段拼起来检测，再按所在缓冲的时间换算。
        /// - Parameter sensitive: 根音单拨附近的时间段（主机时钟秒），这些地方放低检测门槛。
        func onsetTimes(sensitive: [ClosedRange<Double>] = []) -> [Double] {
            guard !chunks.isEmpty else { return [] }
            var all: [Float] = []
            var starts: [Int] = []
            for c in chunks { starts.append(all.count); all.append(contentsOf: c.samples) }
            // 时间换成拼接后的采样位置（按所在缓冲的时间戳）
            func index(_ t: Double) -> Int {
                var k = 0
                while k + 1 < chunks.count && chunks[k + 1].time <= t { k += 1 }
                return starts[k] + max(0, Int((t - chunks[k].time) * sampleRate))
            }
            let ranges = sensitive.map { index($0.lowerBound)...max(index($0.lowerBound), index($0.upperBound)) }
            return OnsetDetector(sampleRate: sampleRate).detect(all, sensitive: ranges).map { index in
                // 找到起音所在的缓冲，用它自己的时间戳换算（不累积误差）
                var k = 0
                while k + 1 < starts.count && starts[k + 1] <= index { k += 1 }
                return chunks[k].time + Double(index - starts[k]) / sampleRate
            }
        }
    }
}

// MARK: - 成绩记录

/// 每次跟练的成绩（最近 200 次），存在本机。
struct StrumHistory {
    struct Entry: Codable, Equatable {
        var date: Date
        var patternID: String
        var chord: String
        var bpm: Int
        var score: Int
        /// 这次练的和弦进行（旧记录没有）
        var progressionName: String? = nil
        var chords: [String]? = nil
        /// 乐器类别（旧记录没有）
        var family: String? = nil
        /// 这次练了几遍（旧记录没有，就是 1 遍）
        var passes: Int? = nil
    }

    private let defaults: UserDefaults
    private static let key = "strum.history"
    private(set) var entries: [Entry]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    mutating func add(_ entry: Entry) {
        entries.append(entry)
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }

    var last: Entry? { entries.last }
    func best(for patternID: String) -> Int? { entries.filter { $0.patternID == patternID }.map(\.score).max() }
}

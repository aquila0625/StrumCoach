import Foundation
import Observation
import SwiftUI
import TunerKit

/// 一个和弦加把位：演奏中排队等着切换的就是这个。
public struct ChordState: Equatable, Sendable {
    public var root: Int
    public var typeID: String
    public var voicingIndex: Int

    public init(root: Int, typeID: String, voicingIndex: Int) {
        self.root = root; self.typeID = typeID; self.voicingIndex = voicingIndex
    }
}

/// 和弦库的状态：选了哪件乐器、哪个和弦、第几个把位，以及收藏、左手模式。
///
/// 持久化交给 App：`current`（Codable）、`favorites`（Codable）、`leftHanded` 自己存取即可。
@MainActor @Observable
public final class ChordLibraryModel {
    public private(set) var instrument: Instrument
    public private(set) var tuning: Tuning
    public private(set) var root: Int
    public private(set) var type: ChordType
    public private(set) var voicingIndex: Int

    /// 指法图左右镜像。
    public var leftHanded: Bool
    public var favorites: ChordFavorites
    /// 收藏变化时回调，App 在这里存盘。
    public var onFavoritesChange: ((ChordFavorites) -> Void)?
    public var a4: Double = TunerDefaults.a4
    /// App 统一管理音频会话时设为 false。
    public var configuresAudioSession = true

    /// 试听的方式：扫弦，或分解和弦（循环到再点一次停止）。
    public enum PlayMode: String, Codable, CaseIterable, Sendable { case strum, arpeggio }

    public private(set) var playMode: PlayMode
    /// 各乐器选中的分解指法（乐器大类 → 指法 id），会存进 UserDefaults，下次进来还是它。
    public private(set) var arpeggioChoices: [String: String]
    /// 各乐器选中的扫弦节奏型（乐器大类 → 节奏型 id）。
    public private(set) var rhythmChoices: [String: String]
    /// 用户保存的自定义分解指法 / 扫弦节奏型，按乐器大类分别保存（每类最多 10 个），存在 UserDefaults 里。
    public private(set) var customArpeggios: [String: [CustomArpeggio]]
    public private(set) var customRhythms: [String: [CustomStrumRhythm]]
    /// 节拍器的速度（App 传进来）。只有打开“跟随节拍器”（`followsMetronome`）时才用它；没传就用自己的速度。
    public var bpm: Double?
    /// 和弦库自己的速度范围与默认值（比节拍器慢，适合边看边弹）。
    public static let tempoRange: ClosedRange<Double> = 30...200
    public static let defaultTempo: Double = 70
    /// 和弦库自己的速度（BPM，一拍是一个四分音符）；会存进 UserDefaults。
    public private(set) var tempo: Double
    /// 是否跟随节拍器：打开时用 `bpm`，关闭（默认）时用自己的 `tempo`。会存进 UserDefaults。
    public private(set) var followsMetronome: Bool

    /// 是否正在演奏（循环播放，直到 `stopPlayback()`）。
    public private(set) var isPlaying = false
    /// 演奏中用户点了另一个和弦 / 把位，排队等当前循环结束再切过去；没有排队时为 nil。连续点多次以最后一次为准。
    public private(set) var queued: ChordState?
    /// 点弦发声的动画变化时加一，让界面刷新（见 `isAnimating`）。
    public private(set) var pluckStamp = 0
    @ObservationIgnored private var performer: ChordPerformer?
    @ObservationIgnored private var scheduledState = ChordState(root: 0, typeID: "major", voicingIndex: 0)
    @ObservationIgnored private var stateLog: [Int: ChordState] = [:]
    /// 每个片段（一拍）里第一格是第几格、一格多长、有几格（扫弦模式的小格子高亮用）。
    @ObservationIgnored private var cycleCells: [Int: (first: Int, duration: Double, count: Int)] = [:]
    /// 正在演奏的一小节的计划，和已经排到第几拍。
    @ObservationIgnored var plan: BarPlan?
    @ObservationIgnored var planBeat = 0.0
    @ObservationIgnored private var nextTag = 0
    @ObservationIgnored private var manualPlucks: [Int: Double] = [:]
    /// 测试时关掉真实发声（只走状态机）。
    @ObservationIgnored var audioEnabled = true
    @ObservationIgnored private let defaults: UserDefaults
    static let tempoKey = "chordkit.tempo"
    static let followKey = "chordkit.followMetronome"
    static let playModeKey = "chordkit.playMode"
    static let arpeggioKey = "chordkit.arpeggioPatterns"
    static let rhythmKey = "chordkit.strumRhythms"
    static let customArpeggioKey = "chordkit.customArpeggios"
    static let customRhythmKey = "chordkit.customRhythms"

    public init(current: ChordFavorite? = nil, leftHanded: Bool = false,
                favorites: ChordFavorites = ChordFavorites(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.playMode = defaults.string(forKey: Self.playModeKey).flatMap(PlayMode.init(rawValue:)) ?? .strum
        let savedTempo = defaults.object(forKey: Self.tempoKey) as? Double
        self.tempo = min(max((savedTempo ?? Self.defaultTempo).rounded(), Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
        self.followsMetronome = defaults.bool(forKey: Self.followKey)
        self.arpeggioChoices = defaults.dictionary(forKey: Self.arpeggioKey) as? [String: String] ?? [:]
        self.rhythmChoices = defaults.dictionary(forKey: Self.rhythmKey) as? [String: String] ?? [:]
        self.customArpeggios = defaults.data(forKey: Self.customArpeggioKey)
            .flatMap { try? JSONDecoder().decode([String: [CustomArpeggio]].self, from: $0) } ?? [:]
        self.customRhythms = defaults.data(forKey: Self.customRhythmKey)
            .flatMap { try? JSONDecoder().decode([String: [CustomStrumRhythm]].self, from: $0) } ?? [:]
        let inst = ChordLibrary.instruments.first { $0.id == current?.instrumentID } ?? InstrumentLibrary.guitar
        self.instrument = inst
        self.tuning = inst.tuning(id: current?.tuningID ?? "") ?? inst.defaultTuning
        self.root = ((current?.root ?? 0) % 12 + 12) % 12
        self.type = current.flatMap { ChordType.type(id: $0.typeID) } ?? .major
        self.voicingIndex = 0
        self.leftHanded = leftHanded
        self.favorites = favorites
        let list = ChordLibrary.supportsFingering(inst) ? ChordLibrary.voicings(for: Chord(root: root, type: type), instrument: inst, tuning: tuning) : []
        self.voicingIndex = min(max(0, current?.voicingIndex ?? 0), max(0, list.count - 1))
    }

    // MARK: 派生

    public var chord: Chord { Chord(root: root, type: type) }
    public var isBass: Bool { instrument.family == .bass }
    public var voicings: [ChordVoicing] {
        ChordLibrary.supportsFingering(instrument) ? ChordLibrary.voicings(for: chord, instrument: instrument, tuning: tuning) : []
    }
    public var voicing: ChordVoicing? {
        let list = voicings
        return list.indices.contains(voicingIndex) ? list[voicingIndex] : nil
    }
    public var bassPositions: BassPositions? { isBass ? BassPositions.make(chord: chord, tuning: tuning) : nil }
    /// 当前把位总数（贝斯为 1）。
    public var voicingCount: Int { isBass ? 1 : voicings.count }

    /// 当前所处的位置，可直接存起来下次启动恢复。
    public var current: ChordFavorite {
        ChordFavorite(instrumentID: instrument.id, tuningID: tuning.id, root: root, typeID: type.id,
                      voicingIndex: isBass ? 0 : voicingIndex)
    }
    public var isFavorite: Bool { favorites.contains(current) }

    // MARK: 选择

    /// 此刻的和弦状态（界面显示的，不含排队的）。
    public var currentState: ChordState { ChordState(root: root, typeID: type.id, voicingIndex: voicingIndex) }

    /// 排队中的和弦（根音或类型和现在的不同）；没有则 nil。
    public var queuedChord: Chord? {
        guard let q = queued, q.root != root || q.typeID != type.id, let t = ChordType.type(id: q.typeID) else { return nil }
        return Chord(root: q.root, type: t)
    }
    /// 排队中的根音（用来给根音按钮画“下一个”状态）。
    public var queuedRoot: Int? { queuedChord.map(\.root).flatMap { $0 == root ? nil : $0 } }
    /// 排队中的类型。
    public var queuedType: ChordType? { queuedChord.flatMap { $0.type.id == type.id ? nil : $0.type } }
    /// 只排队了换把位（和弦不变）时的目标序号。
    public var queuedVoicingIndex: Int? {
        guard let q = queued, q.root == root, q.typeID == type.id, q.voicingIndex != voicingIndex else { return nil }
        return q.voicingIndex
    }
    /// 把位卡片和页码点显示的序号：排队了换把位就是它，否则是当前的。
    public var targetVoicingIndex: Int { queuedVoicingIndex ?? voicingIndex }
    /// 是否有任何排队的切换。
    public var hasQueuedChange: Bool { queued != nil && queued != currentState }

    public func select(instrument inst: Instrument, tuning t: Tuning? = nil) {
        guard ChordLibrary.instruments.contains(where: { $0.id == inst.id }) else { return }
        stopPlayback()
        instrument = inst
        tuning = t ?? inst.defaultTuning
        voicingIndex = 0
    }

    public func select(tuning t: Tuning) {
        guard instrument.tunings.contains(where: { $0.id == t.id }) else { return }
        stopPlayback()
        tuning = t; voicingIndex = 0
    }

    /// 排一个切换：和现在一样就取消排队。
    private func request(_ state: ChordState) {
        queued = state == currentState ? nil : state
    }

    /// 选根音。演奏中不立即切换，排到当前循环结束；没在演奏时立即切换。
    public func select(root r: Int) {
        let r = ((r % 12) + 12) % 12
        if isPlaying {
            let base = queued ?? currentState
            request(ChordState(root: r, typeID: base.typeID, voicingIndex: 0))
            return
        }
        root = r
        voicingIndex = 0
    }

    /// 选类型。演奏中排队，否则立即切换。
    public func select(type t: ChordType) {
        if isPlaying {
            let base = queued ?? currentState
            request(ChordState(root: base.root, typeID: t.id, voicingIndex: 0))
            return
        }
        type = t; voicingIndex = 0
    }

    /// 翻到某个把位。演奏中排到下一个循环生效；
    /// 如果已经排队了换和弦，翻把位不生效（返回 false，卡片弹回）。返回是否接受。
    @discardableResult
    public func select(voicingIndex i: Int) -> Bool {
        guard i >= 0, i < voicingCount else { return false }
        if i == targetVoicingIndex { return true }
        if isPlaying {
            if queuedChord != nil { return false }
            request(ChordState(root: root, typeID: type.id, voicingIndex: i))
            return true
        }
        voicingIndex = i
        return true
    }
    public func nextVoicing() { select(voicingIndex: targetVoicingIndex + 1) }
    public func previousVoicing() { select(voicingIndex: targetVoicingIndex - 1) }

    /// 跳到一条收藏。同一件乐器上演奏中就排队，换乐器会停止演奏。
    public func go(to f: ChordFavorite) {
        guard let inst = ChordLibrary.instruments.first(where: { $0.id == f.instrumentID }),
              let t = ChordType.type(id: f.typeID) else { return }
        let newTuning = inst.tuning(id: f.tuningID) ?? inst.defaultTuning
        if isPlaying && inst.id == instrument.id && newTuning.id == tuning.id {
            request(ChordState(root: ((f.root % 12) + 12) % 12, typeID: t.id,
                               voicingIndex: clampedVoicingIndex(f.voicingIndex, root: f.root, type: t)))
            return
        }
        stopPlayback()
        instrument = inst
        tuning = newTuning
        root = ((f.root % 12) + 12) % 12
        type = t
        voicingIndex = clampedVoicingIndex(f.voicingIndex, root: root, type: t)
    }

    private func clampedVoicingIndex(_ i: Int, root: Int, type: ChordType) -> Int {
        let count = isBass ? 1 : ChordLibrary.voicings(for: Chord(root: root, type: type), instrument: instrument, tuning: tuning).count
        return min(max(0, i), max(0, count - 1))
    }

    /// 把一个状态变成当前显示的（演奏中在循环边界、被听到时调用）。
    private func apply(_ s: ChordState) {
        guard let t = ChordType.type(id: s.typeID) else { return }
        root = ((s.root % 12) + 12) % 12
        type = t
        voicingIndex = clampedVoicingIndex(s.voicingIndex, root: root, type: t)
    }

    // MARK: 收藏

    public func toggleFavorite() {
        favorites.toggle(current)
        onFavoritesChange?(favorites)
    }
    public func removeFavorite(_ f: ChordFavorite) {
        favorites.remove(f)
        onFavoritesChange?(favorites)
    }

    // MARK: 试听

    /// 当前乐器能用的分解指法。
    public var arpeggioPatterns: [ArpeggioPattern] {
        let custom = (customArpeggios[instrument.family.rawValue] ?? [])
            .compactMap { $0.pattern(family: instrument.family, stringCount: tuning.strings.count) }
        return ArpeggioPattern.patterns(for: instrument.family) + custom
    }
    /// 当前选中的分解指法（没选过就用第一个）。
    public var arpeggioPattern: ArpeggioPattern? {
        let list = arpeggioPatterns
        return list.first { $0.id == arpeggioChoices[instrument.family.rawValue] } ?? list.first
    }
    /// 不能扫弦的乐器（贝斯）只有分解（贝斯是“根五八五”）；见 `Instrument.supportsStrumming`。
    public var supportsStrum: Bool { instrument.supportsStrumming }
    /// 此刻实际的试听方式。
    public var effectivePlayMode: PlayMode { supportsStrum ? playMode : .arpeggio }
    /// 同 `effectivePlayMode`（界面里用）。
    var effectiveMode: PlayMode { effectivePlayMode }

    /// 吉他里“5”换成的根音弦弦号（当前把位）；不是吉他时为 nil。
    public var rootStringNumber: Int? {
        guard instrument.family == .guitar, let v = voicing else { return nil }
        return ArpeggioPattern.rootStringNumber(voicing: v, chord: chord, tuning: tuning)
    }

    /// 选试听方式并记住；演奏中从下一个循环开始换。
    public func select(playMode mode: PlayMode) {
        guard mode != playMode else { return }
        playMode = mode
        defaults.set(mode.rawValue, forKey: Self.playModeKey)
    }

    /// 选分解指法并记住；演奏中从下一个循环开始换。
    public func select(arpeggio pattern: ArpeggioPattern) {
        guard pattern.family == instrument.family else { return }
        arpeggioChoices[instrument.family.rawValue] = pattern.id
        defaults.set(arpeggioChoices, forKey: Self.arpeggioKey)
    }

    // MARK: 扫弦节奏型

    /// 当前乐器能用的扫弦节奏型：预设在前，自定义在后。
    public var strumRhythms: [StrumRhythm] {
        StrumRhythm.presets(for: instrument.family)
            + (customRhythms[instrument.family.rawValue] ?? []).compactMap(\.rhythm)
    }
    /// 当前选中的扫弦节奏型（没选过就用第一个：吉他民谣 1、尤克里里岛屿扫弦）。
    public var strumRhythm: StrumRhythm {
        let list = strumRhythms
        return list.first { $0.id == rhythmChoices[instrument.family.rawValue] } ?? list[0]
    }

    /// 选扫弦节奏型并记住；演奏中从下一个循环开始换。
    public func select(rhythm: StrumRhythm) {
        guard strumRhythms.contains(where: { $0.id == rhythm.id }) else { return }
        rhythmChoices[instrument.family.rawValue] = rhythm.id
        defaults.set(rhythmChoices, forKey: Self.rhythmKey)
    }

    // MARK: 自定义分解指法

    public var canAddCustomArpeggio: Bool { (customArpeggios[instrument.family.rawValue] ?? []).count < ArpeggioInput.maxSaved }

    /// 校验用户输入的指法（按当前乐器的弦数）。
    public func validateArpeggio(_ text: String) -> ArpeggioParse {
        ArpeggioInput.parse(text, stringCount: tuning.strings.count)
    }

    /// 保存（`id` 为 nil 是新建，否则是修改）并选中。输入不合格、或新建时已满 10 个返回 nil。
    /// `name` 为空表示用数字串当名字。
    @discardableResult
    public func saveCustomArpeggio(id: String? = nil, name: String = "", text: String) -> CustomArpeggio? {
        let parsed = validateArpeggio(text)
        guard parsed.isValid else { return nil }
        let key = instrument.family.rawValue
        var list = customArpeggios[key] ?? []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item: CustomArpeggio
        if let id, let i = list.firstIndex(where: { $0.id == id }) {
            list[i].name = trimmed; list[i].text = parsed.normalized
            item = list[i]
        } else {
            guard list.count < ArpeggioInput.maxSaved else { return nil }
            item = CustomArpeggio(name: trimmed, text: parsed.normalized)
            list.append(item)
        }
        customArpeggios[key] = list
        persistCustom()
        arpeggioChoices[key] = ArpeggioPattern.customPrefix + item.id
        defaults.set(arpeggioChoices, forKey: Self.arpeggioKey)
        return item
    }

    public func deleteCustomArpeggio(id: String) {
        let key = instrument.family.rawValue
        customArpeggios[key]?.removeAll { $0.id == id }
        persistCustom()
        if arpeggioChoices[key] == ArpeggioPattern.customPrefix + id {
            arpeggioChoices[key] = nil
            defaults.set(arpeggioChoices, forKey: Self.arpeggioKey)
        }
    }

    /// 输入过程中试听一遍当前把位上的这个指法（只播一遍，不影响循环演奏）。
    public func previewArpeggio(text: String) {
        let parsed = validateArpeggio(text)
        guard parsed.isValid else { return }
        let pattern = ArpeggioPattern(id: ArpeggioPattern.customPrefix + "preview", family: instrument.family,
                                      kind: .custom(parsed.steps), digits: parsed.normalized, summary: "", englishSummary: "")
        guard let loop = arpeggioLoop(pattern, chord: chord, voicing: voicing) else { return }
        playOnce(PlaybackBuilder.performedCycle(from: loop).playback)
    }

    // MARK: 自定义扫弦节奏型

    public var canAddCustomRhythm: Bool { canAddCustomRhythm(for: instrument.family) }

    /// 某类乐器还能不能再存自定义节奏型（每类最多 10 个）。训练页和和弦库共用同一份存储，各自可以选不同的乐器。
    public func canAddCustomRhythm(for family: InstrumentFamily) -> Bool {
        (customRhythms[family.rawValue] ?? []).count < StrumInput.maxSaved
    }

    /// 某类乐器已保存的自定义节奏型。
    public func customRhythms(for family: InstrumentFamily) -> [CustomStrumRhythm] { customRhythms[family.rawValue] ?? [] }

    /// 某类乐器能用的扫弦节奏型：预设在前，自定义在后。
    public func strumRhythms(for family: InstrumentFamily) -> [StrumRhythm] {
        StrumRhythm.presets(for: family) + customRhythms(for: family).compactMap(\.rhythm)
    }

    public func validateRhythm(_ text: String, cellsPerBeat: Int) -> StrumParse {
        StrumInput.parse(text, cellsPerBeat: cellsPerBeat)
    }

    /// 保存（`id` 为 nil 是新建，否则是修改）。输入不合格、或新建时这类乐器已满 10 个返回 nil。
    /// - Parameters:
    ///   - family: 存进哪类乐器的列表；nil 用和弦库当前的乐器。
    ///   - select: 是否同时把它设为和弦库里这类乐器选中的节奏型（训练页自己管选择时传 false）。
    @discardableResult
    public func saveCustomRhythm(id: String? = nil, name: String = "", text: String, cellsPerBeat: Int,
                                 family: InstrumentFamily? = nil, select: Bool = true) -> CustomStrumRhythm? {
        let parsed = validateRhythm(text, cellsPerBeat: cellsPerBeat)
        guard parsed.isValid else { return nil }
        let key = (family ?? instrument.family).rawValue
        var list = customRhythms[key] ?? []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item: CustomStrumRhythm
        if let id, let i = list.firstIndex(where: { $0.id == id }) {
            list[i].name = trimmed; list[i].code = parsed.normalized; list[i].cellsPerBeat = cellsPerBeat
            item = list[i]
        } else {
            guard list.count < StrumInput.maxSaved else { return nil }
            item = CustomStrumRhythm(name: trimmed, code: parsed.normalized, cellsPerBeat: cellsPerBeat)
            list.append(item)
        }
        customRhythms[key] = list
        persistCustom()
        if select {
            rhythmChoices[key] = StrumRhythm.customPrefix + item.id
            defaults.set(rhythmChoices, forKey: Self.rhythmKey)
        }
        return item
    }

    /// 删除；这类乐器选中的正是它时回到第一个预设。`family` 为 nil 用当前乐器。
    public func deleteCustomRhythm(id: String, family: InstrumentFamily? = nil) {
        let key = (family ?? instrument.family).rawValue
        customRhythms[key]?.removeAll { $0.id == id }
        persistCustom()
        if rhythmChoices[key] == StrumRhythm.customPrefix + id {
            rhythmChoices[key] = nil
            defaults.set(rhythmChoices, forKey: Self.rhythmKey)
        }
    }

    /// 输入过程中试听一小节这个节奏型（当前和弦的第一个把位，只播一遍）。
    /// `family` 为 nil 用和弦库当前的乐器；指定别的乐器时用那件乐器的默认定弦和采样。
    public func previewRhythm(text: String, cellsPerBeat: Int, family: InstrumentFamily? = nil) {
        let fam = family ?? instrument.family
        guard fam.supportsStrumming,
              let inst = ChordLibrary.instruments.first(where: { $0.family == fam }),
              let rhythm = StrumRhythm(id: StrumRhythm.customPrefix + "preview",
                                       code: validateRhythm(text, cellsPerBeat: cellsPerBeat).normalized, cellsPerBeat: cellsPerBeat) else { return }
        let tuning = fam == instrument.family ? self.tuning : inst.defaultTuning
        let list = ChordLibrary.voicings(for: chord, instrument: inst, tuning: tuning)
        guard let v = list[safe: fam == instrument.family ? voicingIndex : 0] ?? list.first else { return }
        let bar = PlaybackBuilder.strumRhythmBar(voicing: v, rhythm: rhythm, voice: InstrumentTone.Voice(family: fam), a4: a4,
                                                 bpm: effectiveBPM, rootPitchClass: chord.root)
        playOnce(bar.playback)
    }

    /// 自定义节奏型编辑页的图例（B / D / d / U 的区别）是否还没显示过：只在第一次打开编辑页时显示一次。
    public var shouldShowStrumLegend: Bool { !defaults.bool(forKey: Self.legendKey) }
    public func markStrumLegendSeen() { defaults.set(true, forKey: Self.legendKey) }
    static let legendKey = "chordkit.strumLegendSeen"

    private func persistCustom() {
        if let d = try? JSONEncoder().encode(customArpeggios) { defaults.set(d, forKey: Self.customArpeggioKey) }
        if let d = try? JSONEncoder().encode(customRhythms) { defaults.set(d, forKey: Self.customRhythmKey) }
    }

    private func playOnce(_ playback: ChordPlayback) {
        guard audioEnabled else { return }
        let p = performer ?? ChordPerformer()
        performer = p
        p.configuresAudioSession = configuresAudioSession
        p.playOnce(playback)
    }

    /// 当前设置下要播放的内容：扫弦（吉他、尤克里里）、分解和弦（含贝斯）。
    public func makePlayback() -> ChordPlayback? {
        let voice = InstrumentTone.Voice(family: instrument.family)
        let interval = PlaybackBuilder.noteInterval(bpm: effectiveBPM)
        if isBass {
            return PlaybackBuilder.bassArpeggio(chord: chord, tuning: tuning, positions: bassPositions, voice: voice,
                                                a4: a4, interval: interval)
        }
        guard let v = voicing else { return nil }
        switch effectivePlayMode {
        case .strum:
            return PlaybackBuilder.strum(voicing: v, voice: voice, a4: a4)
        case .arpeggio:
            guard let pattern = arpeggioPattern else { return nil }
            return PlaybackBuilder.arpeggio(pattern: pattern, voicing: v, chord: chord, tuning: tuning,
                                            voice: voice, a4: a4, interval: interval)
        }
    }

    // MARK: 速度

    /// 此刻实际用的速度（BPM）：跟随节拍器且 App 传了 `bpm` 时是 `bpm`（夹在 30–300），否则是自己的 `tempo`。
    public var effectiveBPM: Double {
        if followsMetronome, let b = bpm { return min(max(b, 30), 300) }
        return tempo
    }

    /// 设自己的速度（取整，夹在 30–200）并记住。演奏中从下一拍开始生效，不打断、不跳拍。
    public func setTempo(_ value: Double) {
        let v = min(max(value.rounded(), Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
        guard v != tempo else { return }
        tempo = v
        defaults.set(v, forKey: Self.tempoKey)
    }

    /// 加减速度（点按 ±1）。
    public func adjustTempo(by delta: Double) { setTempo(tempo + delta) }

    /// 打开 / 关闭“跟随节拍器”并记住；演奏中从下一拍开始生效。
    public func setFollowsMetronome(_ on: Bool) {
        guard on != followsMetronome else { return }
        followsMetronome = on
        defaults.set(on, forKey: Self.followKey)
    }

    // MARK: 演奏（循环）

    /// 开始演奏；再点一次停止。扫弦模式一个循环是一小节 4 拍，每拍下扫一次（第 1 拍重音）；
    /// 分解模式一个循环是选中的指法走完一遍。速度用 `bpm`（没有时 100）。循环之间用音频时钟无缝衔接，
    /// 直到 `stopPlayback()`（切换乐器、离开页面、App 进后台时也应停止）。
    public func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    func startPlayback() {
        scheduledState = currentState
        stateLog = [:]; cycleCells = [:]; nextTag = 0; plan = nil; planBeat = 0
        queued = nil
        guard buildPlan(for: scheduledState) != nil else { return }
        isPlaying = true
        guard audioEnabled else { return }
        let p = performer ?? ChordPerformer()
        performer = p
        p.configuresAudioSession = configuresAudioSession
        p.cycleProvider = { [weak self] in self?.nextCycle() }
        p.onAudibleCycle = { [weak self] tag in self?.audibleCycle(tag) }
        if !p.start() { isPlaying = false }
    }

    /// 演奏器要下一个片段（一拍）：小节开头才把排队的切换（如果有）用上、重新取这一小节的计划；
    /// 每一拍按**当时**的速度换算成秒，所以演奏中改速度，从下一拍开始生效。
    func nextCycle() -> PerformedCycle? {
        if plan == nil || planBeat >= (plan?.lengthBeats ?? 0) - 1e-9 {
            if let q = queued { scheduledState = q }
            guard let p = buildPlan(for: scheduledState) else { return nil }
            plan = p; planBeat = 0
        }
        guard let plan else { return nil }
        let beat = 60 / effectiveBPM
        let seg = plan.segment(from: planBeat, beatDuration: beat)
        guard seg.beats > 0 else { return nil }
        let startBeat = planBeat
        planBeat += seg.beats
        nextTag += 1
        stateLog[nextTag] = scheduledState
        cycleCells[nextTag] = plan.cellsPerBeat.map { (Int(startBeat.rounded(.down)) * $0, beat / Double($0), $0) }
        if stateLog.count > 24 { stateLog[nextTag - 24] = nil; cycleCells[nextTag - 24] = nil }
        let length = seg.beats * beat
        let playback = ChordPlayback(events: seg.events, cycle: nil, voice: InstrumentTone.Voice(family: instrument.family),
                                     a4: a4, tail: min(1.4, 2 * max(length, 0.5)), noteSeconds: 1.8)
        return PerformedCycle(playback: playback, length: length, tag: nextTag)
    }

    /// 新的循环被耳朵听到了：这时才把界面切到它的和弦（带过渡动画），排队的“下一个”状态也在这里清掉。
    func audibleCycle(_ tag: Int) {
        guard let state = stateLog[tag] else { return }
        if state != currentState { withAnimation(.smooth(duration: 0.35)) { apply(state) } }
        if let q = queued, q == currentState { queued = nil }
    }

    /// 分解指法的循环事件表（吉他 / 尤克里里按把位，贝斯按和弦音位置）。`interval` 是每一步的间隔：
    /// 默认是一个八分音符（按此刻的速度）；连续演奏用 0.5（单位是拍）。
    private func arpeggioLoop(_ pattern: ArpeggioPattern, chord: Chord, voicing v: ChordVoicing?, interval: Double? = nil) -> ChordPlayback? {
        let voice = InstrumentTone.Voice(family: instrument.family)
        let interval = interval ?? PlaybackBuilder.noteInterval(bpm: effectiveBPM)
        if isBass {
            let positions = BassPositions.make(chord: chord, tuning: tuning)
            if pattern.isCustom {
                return PlaybackBuilder.bassCustom(pattern: pattern, chord: chord, tuning: tuning, positions: positions,
                                                  voice: voice, a4: a4, interval: interval)
            }
            return PlaybackBuilder.bassArpeggio(chord: chord, tuning: tuning, positions: positions, voice: voice, a4: a4, interval: interval)
        }
        guard let v else { return nil }
        return PlaybackBuilder.arpeggio(pattern: pattern, voicing: v, chord: chord, tuning: tuning, voice: voice, a4: a4, interval: interval)
    }

    /// 某个和弦状态的一小节计划（位置以拍为单位）；演奏器每拍从里面切一个片段。
    func buildPlan(for state: ChordState) -> BarPlan? {
        guard let t = ChordType.type(id: state.typeID) else { return nil }
        let chord = Chord(root: state.root, type: t)
        let voice = InstrumentTone.Voice(family: instrument.family)
        if isBass {
            guard let pattern = arpeggioPattern, let loop = arpeggioLoop(pattern, chord: chord, voicing: nil, interval: 0.5) else { return nil }
            return PlaybackBuilder.loopPlan(fromBeats: loop)
        }
        let list = ChordLibrary.voicings(for: chord, instrument: instrument, tuning: tuning)
        guard !list.isEmpty else { return nil }
        let v = list[min(max(0, state.voicingIndex), list.count - 1)]
        switch effectivePlayMode {
        case .strum:
            return PlaybackBuilder.strumRhythmPlan(voicing: v, rhythm: strumRhythm, voice: voice, a4: a4, rootPitchClass: chord.root)
        case .arpeggio:
            guard let pattern = arpeggioPattern, let loop = arpeggioLoop(pattern, chord: chord, voicing: v, interval: 0.5) else { return nil }
            return PlaybackBuilder.loopPlan(fromBeats: loop)
        }
    }

    /// 某个和弦状态的一整个循环（按此刻的速度换算成秒的单次播放事件表 + 循环长度，扫弦模式还有每格多长、几格）。
    /// 连续演奏不用它（按拍切片段），测试和一次性用途用。
    struct BuiltCycle {
        var playback: ChordPlayback
        var length: Double
        var cells: (duration: Double, count: Int)?
    }

    func buildCycle(for state: ChordState) -> BuiltCycle? {
        guard let plan = buildPlan(for: state) else { return nil }
        let beat = 60 / effectiveBPM
        let length = plan.lengthBeats * beat
        let playback = ChordPlayback(events: plan.wholeBar(beatDuration: beat), cycle: nil,
                                     voice: InstrumentTone.Voice(family: instrument.family), a4: a4,
                                     tail: min(1.4, 2 * length), noteSeconds: 1.8)
        return BuiltCycle(playback: playback, length: length,
                          cells: plan.cellsPerBeat.map { (beat / Double($0), Int(plan.lengthBeats) * $0) })
    }

    /// 此刻听到的是扫弦节奏型的第几格（用来在小格子行里同步高亮）；没在演奏扫弦时为 nil。
    public func playingCell() -> Int? {
        guard isPlaying, let (tag, time) = performer?.audibleCycleTime(), let info = cycleCells[tag], info.duration > 0 else { return nil }
        return info.first + min(info.count - 1, max(0, Int(time / info.duration)))
    }

    /// 停止演奏，清掉排队的切换。
    public func stopPlayback() {
        performer?.stop()
        isPlaying = false
        queued = nil
    }

    // MARK: 点弦发声

    /// 指法图上点了第 `string` 根弦会发的音：按当前按法在这根弦上的音。
    /// **不弹的弦（×）不发声**：和弦里本来就不弹它，点它发空弦音会混进和弦外的音（界面只做一个轻微的“×”抖动表示收到了点击）。
    /// `voicingIndex` 是哪一页的把位（卡片上滑到排队中的那一页时，点的是那一页），默认当前把位。
    public func pluckPitch(forString string: Int, voicingIndex index: Int? = nil) -> Pitch? {
        let list = voicings
        guard let v = list[safe: index ?? voicingIndex], v.pitches.indices.contains(string) else { return nil }
        return v.pitches[string]
    }

    /// 点吉他 / 尤克里里指法图上的一根弦：发声（叠加在伴奏上；演奏中或暂停时都可以），并让这根弦做高亮抖动。
    public func pluckString(_ string: Int, voicingIndex index: Int? = nil) {
        guard let pitch = pluckPitch(forString: string, voicingIndex: index) else {
            markPlucked(key: 1000 + string)                      // × 弦：只有动画，不发声
            return
        }
        sound(pitch)
        markPlucked(key: string)
    }

    /// 点贝斯和弦音位置图上的一个标记。
    public func pluckBass(_ marker: BassPositions.Marker) {
        sound(marker.pitch)
        markPlucked(key: marker.string * 100 + marker.fret)
    }

    private func sound(_ pitch: Pitch) {
        guard audioEnabled else { return }
        let p = performer ?? ChordPerformer()
        performer = p
        p.configuresAudioSession = configuresAudioSession
        p.pluck(pitch, voice: InstrumentTone.Voice(family: instrument.family), a4: a4)
    }

    private func markPlucked(key: Int) {
        manualPlucks[key] = ProcessInfo.processInfo.systemUptime
        pluckStamp &+= 1
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((PluckClock.window + 0.1) * 1_000_000_000))
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.manualPlucks = self.manualPlucks.filter { now - $0.value < PluckClock.window }
            self.pluckStamp &+= 1
        }
    }

    /// 是否需要持续刷新指法图（演奏中，或刚点过弦）。
    public var isAnimating: Bool {
        _ = pluckStamp
        let now = ProcessInfo.processInfo.systemUptime
        return isPlaying || manualPlucks.values.contains { now - $0 < PluckClock.window }
    }

    /// 此刻每个元素距上一次被拨到过了多久（秒），指法图用它高亮并抖动弦：演奏中的伴奏 + 用户点的弦。
    /// 键：吉他、尤克里里是弦序号（× 弦被点是 1000 + 序号）；贝斯是 弦 × 100 + 品。
    public func pluckAges() -> [Int: Double] {
        let shown = currentState
        var ages = performer?.pluckAges(accepting: { [stateLog] tag in stateLog[tag] == shown }) ?? [:]
        let now = ProcessInfo.processInfo.systemUptime
        for (key, t) in manualPlucks {
            let age = now - t
            if age >= 0 && age < PluckClock.window { ages[key] = min(ages[key] ?? .infinity, age) }
        }
        return ages
    }
}

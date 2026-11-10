import Foundation
import Observation

/// 调音器的可观察模型：负责麦克风、检测、乐器与弦匹配、参考音。
///
/// 所有属性都在主线程读写；音频线程的结果会自动切回主线程。
/// 一次“调准”事件。
public struct TunedEvent: Equatable, Sendable {
    /// 单调递增的编号，可作为动画触发值。
    public let id: Int
    /// 调准的是哪根弦；半音阶模式为 nil。
    public let stringIndex: Int?
    public let pitch: Pitch
}

@MainActor
@Observable
public final class TunerModel {
    // MARK: 状态（只读）

    /// 麦克风权限。
    public private(set) var permission: MicrophonePermission = MicrophonePermission.current()
    /// 是否正在监听麦克风。
    public private(set) var isRunning = false
    /// 启动失败时的错误描述。
    public private(set) var errorMessage: String?
    /// 当前的实时读数；没有信号时为 nil。
    public private(set) var reading: PitchReading?
    /// 最近一次有效读数（信号消失后仍保留，界面可用来显示变淡的音名）。
    public private(set) var lastReading: PitchReading?
    /// 当前的匹配结果（目标音、偏差）；没有信号时为 nil。
    public private(set) var result: TuningResult?
    /// 已调准的弦（`InstrumentString.index`）。
    public private(set) var tunedStrings: Set<Int> = []
    /// 每次有一个音调准就加 1，可作为触觉反馈、动画的触发值。
    public private(set) var tunedEventCount = 0
    /// 最近一次“调准”：哪根弦（半音阶模式为 nil）、哪个音。界面用它做一次性的强调动画。
    public private(set) var lastTunedEvent: TunedEvent?
    /// 正在发声的参考音；没有则为 nil。
    public private(set) var playingReference: Pitch?

    // MARK: 设置

    public private(set) var instrument: Instrument
    public private(set) var tuning: Tuning
    /// 标准音 A4（415…466 Hz）。
    public private(set) var a4: Double
    /// 手动锁定的弦；nil 表示自动识别最近的弦。
    public private(set) var lockedString: Int?
    /// 参考音音色。
    public var referenceTimbre: ToneTimbre = .instrument {
        didSet { if let p = playingReference { playReference(p) } }
    }
    /// 参考音播放时是否暂停检测（避免把喇叭声当成琴弦）。默认 true。
    public var pausesDetectionWhileReferencePlays = true

    /// 调准时是否播放“叮咚”提示音（默认开，设置保存在 UserDefaults）。
    public var tuneChimeEnabled: Bool {
        didSet { UserDefaults.standard.set(tuneChimeEnabled, forKey: Self.chimeDefaultsKey) }
    }
    static let chimeDefaultsKey = "TunerKit.tuneChimeEnabled"

    /// 当前乐器 + 定弦，便于持久化，也可交给和弦库。
    public var selection: InstrumentSelection { InstrumentSelection(instrumentID: instrument.id, tuningID: tuning.id) }

    // MARK: 内部

    @ObservationIgnored private let microphone = MicrophoneInput()
    @ObservationIgnored private let tonePlayer = ReferenceTonePlayer()
    @ObservationIgnored private var smoother = PitchSmoother()
    /// “调准”的判定规则：偏差连续 0.5 秒在 ±5 音分内；同一个音只提示一次，偏出 ±10 音分后再回来才会再次提示。
    @ObservationIgnored public var confirmation = TuneConfirmation()
    @ObservationIgnored private let chimePlayer = TuneChimePlayer()
    /// 播放提示音，返回是否开始播放。测试里替换掉，避免真的出声。
    @ObservationIgnored var playChime: (() -> Bool)?
    /// 提示音播放期间和结束后这段时间（秒）内忽略检测结果，免得麦克风把提示音当成琴弦。
    @ObservationIgnored public var chimeGuardSeconds = 0.6
    @ObservationIgnored private var ignoreDetectionUntil: TimeInterval = 0
    /// 时间来源（秒）。默认是系统开机后的时间；测试里换成可控的时钟。
    @ObservationIgnored public var clock: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    public init(selection: InstrumentSelection = .default, a4: Double = TunerDefaults.a4) {
        let resolved = selection.resolve()
        self.instrument = resolved.instrument
        self.tuning = resolved.tuning
        self.a4 = TunerModel.clampA4(a4)
        self.tuneChimeEnabled = UserDefaults.standard.object(forKey: Self.chimeDefaultsKey) as? Bool ?? true
        playChime = { [chimePlayer] in chimePlayer.play() }
        microphone.onDetection = { [weak self] raw in
            Task { @MainActor in self?.ingest(raw) }
        }
        // 拨弦类参考音自然衰减播完后，让界面上的“正在发声”状态跟着结束
        tonePlayer.onEnded = { [weak self] in
            Task { @MainActor in
                guard let self, self.playingReference != nil else { return }
                self.playingReference = nil
                self.smoother.reset()
            }
        }
    }

    /// 应用自己管理 AVAudioSession 时（和节拍器共用等）设为 false。
    public var configuresAudioSession: Bool {
        get { microphone.configuresAudioSession }
        set {
            microphone.configuresAudioSession = newValue
            tonePlayer.configuresAudioSession = newValue
            chimePlayer.configuresAudioSession = newValue
        }
    }

    // MARK: 麦克风

    /// 请求权限（必要时）并开始监听。
    public func start() async {
        guard !isRunning else { return }
        errorMessage = nil
        var p = MicrophonePermission.current()
        if p == .notDetermined { p = await MicrophonePermission.request() }
        permission = p
        guard p == .granted else { return }
        do {
            try microphone.start()
            isRunning = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stop() {
        microphone.stop()
        isRunning = false
        stopReference()
        chimePlayer.stop()
        ignoreDetectionUntil = 0
        smoother.reset()
        confirmation.restartHold()
        reading = nil
        result = nil
    }

    // MARK: 喂入数据（麦克风回调、测试、预览都走这里）

    /// 直接喂入一帧音频采样（不经过麦克风），同步完成检测与平滑。
    @discardableResult
    public func ingest(samples: [Float], sampleRate: Double) -> TuningResult? {
        let raw = PitchDetector().detect(samples, sampleRate: sampleRate)
        ingest(raw)
        return result
    }

    /// 喂入一次原始检测结果（nil 表示这一帧没有音高）。
    public func ingest(_ raw: RawPitch?) {
        if pausesDetectionWhileReferencePlays, playingReference != nil { return }
        if ignoreDetectionUntil > 0 {
            // 提示音正在响（或刚响完）：这段时间的检测结果多半是提示音本身，丢掉；窗口结束后从头平滑
            if clock() < ignoreDetectionUntil { return }
            ignoreDetectionUntil = 0
            smoother.reset()
            confirmation.restartHold()
        }
        apply(smoother.process(raw, a4: a4))
    }

    /// 直接指定一个读数（用于 SwiftUI 预览或演示）。
    public func inject(_ reading: PitchReading?) { apply(reading) }

    private func apply(_ newReading: PitchReading?) {
        reading = newReading
        guard let newReading else {
            result = nil
            handle(confirmation.update(key: nil, cents: nil, now: clock()), result: nil)
            return
        }
        lastReading = newReading
        let r = tuning.match(newReading, lockedString: lockedString)
        result = r
        // 弦的序号；半音阶模式下用音名+八度（MIDI 号）
        let key = r.stringIndex ?? r.target.midi
        handle(confirmation.update(key: key, cents: r.cents, now: clock()), result: r)
    }

    private func handle(_ event: TuneConfirmation.Event?, result r: TuningResult?) {
        guard let event else { return }
        switch event {
        case .drifted(let key):
            if !tuning.isChromatic { tunedStrings.remove(key) }
        case .tuned(let key):
            let index: Int? = tuning.isChromatic ? nil : key
            if let index { tunedStrings.insert(index) }
            tunedEventCount += 1
            lastTunedEvent = TunedEvent(id: tunedEventCount, stringIndex: index,
                                        pitch: r?.target ?? Pitch(midi: key))
            if tuneChimeEnabled, playChime?() == true {
                ignoreDetectionUntil = clock() + TuneChime.duration + chimeGuardSeconds
            }
        }
    }

    // MARK: 乐器与弦

    public func select(instrument: Instrument, tuning: Tuning? = nil) {
        self.instrument = instrument
        self.tuning = tuning ?? instrument.defaultTuning
        resetForNewTuning()
    }

    public func select(_ selection: InstrumentSelection) {
        let r = selection.resolve()
        select(instrument: r.instrument, tuning: r.tuning)
    }

    public func select(tuning: Tuning) {
        guard instrument.tunings.contains(tuning) else { return }
        self.tuning = tuning
        resetForNewTuning()
    }

    private func resetForNewTuning() {
        lockedString = nil
        tunedStrings = []
        lastTunedEvent = nil
        confirmation.reset()
        smoother.reset()
        if let reading { apply(PitchReading(frequency: reading.frequency, clarity: reading.clarity, a4: a4)) }
    }

    /// 手动锁定某根弦；传入已锁定的那根或 nil 则回到自动。
    public func lockString(_ index: Int?) {
        lockedString = (index == lockedString) ? nil : index
        confirmation.restartHold()
        if let reading { apply(reading) }
    }

    public func clearTunedMarks() {
        tunedStrings = []
        confirmation.reset()
    }

    // MARK: 标准音

    public func setA4(_ value: Double) {
        a4 = TunerModel.clampA4(value)
        smoother.reset()
        if let p = playingReference { tonePlayer.update(frequency: p.frequency(a4: a4)) }
        if let reading { apply(PitchReading(frequency: reading.frequency, clarity: reading.clarity, a4: a4)) }
    }

    public func adjustA4(by delta: Double) { setA4(a4 + delta) }

    nonisolated private static func clampA4(_ v: Double) -> Double {
        min(max(v.rounded(), TunerDefaults.a4Range.lowerBound), TunerDefaults.a4Range.upperBound)
    }

    // MARK: 参考音

    /// 播放参考音；再次对同一个音调用则停止。
    public func toggleReference(_ pitch: Pitch) {
        if playingReference == pitch { stopReference() } else { playReference(pitch) }
    }

    public func playReference(_ pitch: Pitch) {
        do {
            try tonePlayer.play(pitch: pitch, a4: a4, timbre: referenceTimbre,
                                voice: InstrumentTone.Voice(family: instrument.family))
            playingReference = pitch
            reading = nil; result = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopReference() {
        guard playingReference != nil else { return }
        tonePlayer.stop()
        playingReference = nil
        smoother.reset()
    }
}

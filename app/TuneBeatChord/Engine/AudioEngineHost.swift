import AVFoundation
import MetronomeCore
import QuartzCore

/// 一拍在设备时钟上的发声时间（秒，和 CACurrentMediaTime 同一时基）。
struct BeatMark: Equatable, Sendable {
    var serial: Int64
    var bar: Int
    var beatInBar: Int
    /// 实际发声的重音；被静音训练静掉的拍记为 `.muted`（不震动）。
    var accent: AccentLevel
    var isTrainingMuted: Bool
    var bpm: Double
    var hostTime: Double

    init(_ event: ClickEvent, hostTime: Double) {
        serial = event.beatSerial
        bar = event.bar
        beatInBar = event.beatInBar
        accent = event.isTrainingMuted ? .muted : event.accent
        isTrainingMuted = event.isTrainingMuted
        bpm = event.bpm
        self.hostTime = hostTime
    }
}

/// 一个点（主拍或切分点）在设备时钟上的发声时间。拍子方块里的切分格按它高亮。
struct ClickMark: Equatable, Sendable {
    var beatSerial: Int64
    var beatInBar: Int
    /// 0 = 主拍，其余是这一拍里的第几个切分点。
    var subIndex: Int
    /// 这一拍实际用的切分（决定方块里怎么分格）。
    var subdivision: Subdivision
    var hostTime: Double

    init(beatSerial: Int64, beatInBar: Int, subIndex: Int, subdivision: Subdivision, hostTime: Double) {
        self.beatSerial = beatSerial
        self.beatInBar = beatInBar
        self.subIndex = subIndex
        self.subdivision = subdivision
        self.hostTime = hostTime
    }

    init(_ event: ClickEvent, hostTime: Double) {
        beatSerial = event.beatSerial
        beatInBar = event.beatInBar
        subIndex = event.subIndex
        subdivision = event.subdivision
        self.hostTime = hostTime
    }

    /// 时间先后的排序键（同一拍里按切分点先后）。
    var order: Int64 { beatSerial * 16 + Int64(subIndex) }
}

/// 音频线程每个渲染周期发布一次：最近渲染的一拍，加上预测的接下来两拍；切分点同样是最近一个加后两个。
/// 都是定长字段，音频线程里赋值不分配内存。
struct BeatSnapshot: Sendable {
    var playToken: UInt64 = 0
    /// 训练方案要求停止（渐进提速“到目标后停止”）。
    var finished = false
    var last: BeatMark?
    var next: BeatMark?
    var afterNext: BeatMark?
    var lastClick: ClickMark?
    var nextClick: ClickMark?
    var afterNextClick: ClickMark?

    var marks: [BeatMark] { [last, next, afterNext].compactMap { $0 } }
    var clicks: [ClickMark] { [lastClick, nextClick, afterNextClick].compactMap { $0 } }
}

/// 界面线程写、音频线程读的控制状态。
private struct ControlState: Sendable {
    var config: MetronomeConfig
    var configVersion: UInt64 = 0
    var playToken: UInt64 = 0
    var playing = false
}

/// 音频线程上真正干活的对象。render 里不分配内存、不阻塞。
private final class AudioCore: @unchecked Sendable {
    let renderer: ClickRenderer
    let control: LockedValue<ControlState>
    let snapshot: LockedValue<BeatSnapshot>
    /// 渲染时间戳到“耳朵听到”的额外延迟（输出延迟）。
    let outputLatency: Double
    private let ticksToSeconds: Double
    private let lookahead: Int

    private var seenVersion: UInt64 = 0
    private var seenToken: UInt64 = 0
    private var lastMark: BeatMark?
    private var lastClick: ClickMark?

    init(sampleRate: Double, config: MetronomeConfig, control: LockedValue<ControlState>,
         snapshot: LockedValue<BeatSnapshot>, outputLatency: Double) {
        renderer = ClickRenderer(voices: VoiceBank(sampleRate: sampleRate), config: config)
        self.control = control
        self.snapshot = snapshot
        self.outputLatency = outputLatency
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        ticksToSeconds = Double(info.numer) / Double(info.denom) / 1_000_000_000
        lookahead = Int(sampleRate * 0.4)
    }

    func render(frames: AVAudioFrameCount, timestamp: UnsafePointer<AudioTimeStamp>, buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        // 1. 取界面线程的最新指令（拿不到锁就沿用上一轮的）
        if let state = control.tryWithLock({ $0 }) {
            if state.playToken != seenToken {
                seenToken = state.playToken
                lastMark = nil
                lastClick = nil
                if state.playing {
                    seenVersion = state.configVersion
                    renderer.start(config: state.config)
                }
            } else if state.configVersion != seenVersion {
                seenVersion = state.configVersion
                renderer.update(state.config)
            }
            if !state.playing && renderer.isRunning { renderer.stop() }
        }

        // 2. 渲染
        let abl = UnsafeMutableAudioBufferListPointer(buffers)
        guard let out = abl.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let n = Int(frames)
        let stamp = timestamp.pointee
        let bufferHostTime = stamp.mFlags.contains(.hostTimeValid)
            ? Double(stamp.mHostTime) * ticksToSeconds
            : CACurrentMediaTime()
        let bufferStart = renderer.cursor
        let sampleRate = renderer.sampleRate
        let latency = outputLatency
        func hostTime(_ sample: Int64) -> Double {
            bufferHostTime + Double(sample - bufferStart) / sampleRate + latency
        }

        renderer.render(into: out, frames: n) { event in
            let time = hostTime(event.sample)
            if event.isMainBeat {
                lastMark = BeatMark(event, hostTime: time)
            }
            lastClick = ClickMark(event, hostTime: time)
        }
        for i in 1..<abl.count {
            if let other = abl[i].mData?.assumingMemoryBound(to: Float.self) { other.update(from: out, count: n) }
        }

        // 3. 发布节拍时间线：最近一拍 + 预测的后两拍（触感、当前拍），最近一个点 + 后两个点（切分格高亮）
        var next: BeatMark?, afterNext: BeatMark?
        var nextClick: ClickMark?, afterNextClick: ClickMark?
        if renderer.isRunning {
            renderer.peekClicks(frames: lookahead) { event in
                let time = hostTime(event.sample)
                if nextClick == nil { nextClick = ClickMark(event, hostTime: time) }
                else if afterNextClick == nil { afterNextClick = ClickMark(event, hostTime: time) }
                guard event.isMainBeat else { return }
                let mark = BeatMark(event, hostTime: time)
                if next == nil { next = mark } else if afterNext == nil { afterNext = mark }
            }
        }
        let token = seenToken
        let last = lastMark
        let click = lastClick
        let finished = renderer.scheduler.isFinished
        _ = snapshot.tryWithLock { s in
            s = BeatSnapshot(playToken: token, finished: finished, last: last, next: next, afterNext: afterNext,
                             lastClick: click, nextClick: nextClick, afterNextClick: afterNextClick)
        }
        return noErr
    }
}

/// AVAudioEngine + AVAudioSourceNode。负责音频会话、打断、路由变化。
final class AudioEngineHost {
    /// 被来电、闹钟等打断，或耳机拔出时回调（主线程）。
    var onForcedStop: ((String) -> Void)?

    let snapshot = LockedValue(BeatSnapshot())
    private let control: LockedValue<ControlState>
    private var engine = AVAudioEngine()
    private var engineObserver: NSObjectProtocol?
    private var sourceNode: AVAudioSourceNode?
    private var core: AudioCore?
    private var stopWork: DispatchWorkItem?
    private var needsRebuild = false
    private var observers: [NSObjectProtocol] = []
    /// 人声报数、我的声音（槽位 → 采样和采样率）。引擎重建后要重新写进新的 VoiceBank。
    private var dynamicSlots: [Int: ([Float], Double)] = [:]

    init(config: MetronomeConfig) {
        control = LockedValue(ControlState(config: config))
        observeSession()
        observeEngine()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        engineObserver.map(NotificationCenter.default.removeObserver)
    }

    var isRunning: Bool { engine.isRunning }

    /// 最近一次开始/停止的序号。时间线快照里的序号和它一致，才是这一次播放的数据。
    var currentPlayToken: UInt64 { control.value.playToken }

    /// 写入一个动态声音槽位（nil 表示清空）。马上写进正在用的引擎，并记下来供重建时再写。
    func setDynamic(slot: Int, samples: [Float]?, rate: Double) {
        if let samples { dynamicSlots[slot] = (samples, rate) } else { dynamicSlots[slot] = nil }
        core?.renderer.voices.setDynamic(slot, samples: samples ?? [], sourceRate: rate)
    }

    func update(_ config: MetronomeConfig) {
        control.withLock {
            $0.config = config
            $0.configVersion &+= 1
        }
    }

    /// 开始播放。第一拍落在下一个渲染周期的开头。
    func start(config: MetronomeConfig) throws {
        stopWork?.cancel()
        stopWork = nil
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || session.mode != .default {
            // 刚从录音（调音器）或别的类别切回来：硬件格式可能变了，整个重建一次最稳。
            needsRebuild = true
        }
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        try buildGraphIfNeeded(config: config)
        control.withLock {
            $0.config = config
            $0.configVersion &+= 1
            $0.playToken &+= 1
            $0.playing = true
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// 停止调度新的点击。
    /// - immediately: false 时等尾音放完再停引擎、释放音频会话；true 时马上停引擎且不动会话
    ///   （要把会话交给调音器录音时用，免得延迟的释放把调音器的会话关掉）。
    func stop(immediately: Bool = false) {
        control.withLock {
            $0.playing = false
            $0.playToken &+= 1
        }
        stopWork?.cancel()
        stopWork = nil
        if immediately {
            engine.stop()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.stop()
            // 这期间会话可能已经被调音器、和弦试听改走了，那就不去动它。
            let session = AVAudioSession.sharedInstance()
            if session.category == .playback {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func buildGraphIfNeeded(config: MetronomeConfig) throws {
        let session = AVAudioSession.sharedInstance()
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate > 0
            ? engine.outputNode.outputFormat(forBus: 0).sampleRate
            : session.sampleRate
        if !needsRebuild, let core, core.renderer.sampleRate == sampleRate, sourceNode != nil { return }
        needsRebuild = false

        if let old = sourceNode {
            engine.stop()
            engine.detach(old)
            engine.reset()
        }
        let newCore = AudioCore(sampleRate: sampleRate, config: config, control: control,
                                snapshot: snapshot, outputLatency: session.outputLatency)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "TuneBeatChord", code: 1)
        }
        let node = AVAudioSourceNode(format: format) { _, timestamp, frames, buffers in
            newCore.render(frames: frames, timestamp: timestamp, buffers: buffers)
        }
        for (slot, clip) in dynamicSlots {
            newCore.renderer.voices.setDynamic(slot, samples: clip.0, sourceRate: clip.1)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        core = newCore
    }

    private func observeEngine() {
        engineObserver.map(NotificationCenter.default.removeObserver)
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // 采样率或输出设备变了：引擎已被系统停掉，按新格式重建，正在播放就接着播。
            guard let self, !self.engine.isRunning else { return }
            let state = self.control.value
            self.sourceNode.map { self.engine.detach($0) }
            self.sourceNode = nil
            self.core = nil
            if state.playing {
                try? self.start(config: state.config)
            }
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            // 打断开始就暂停；打断结束后不自动恢复，等用户自己点播放。
            self?.onForcedStop?("interruption")
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            // 耳机拔出：按系统惯例暂停，避免突然外放。
            self?.onForcedStop?("route: old device unavailable")
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            // 媒体服务重置后旧引擎失效，整个换掉。
            guard let self else { return }
            self.sourceNode = nil
            self.core = nil
            self.engine = AVAudioEngine()
            self.observeEngine()
            self.onForcedStop?("media services reset")
        })
    }
}

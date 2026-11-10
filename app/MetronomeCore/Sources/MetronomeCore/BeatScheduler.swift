import Foundation

/// 调度器发出的一个发声事件（主拍或切分点）。
public struct ClickEvent: Equatable, Sendable {
    /// 绝对采样位置（从开始播放那一刻的渲染计数算起）。
    public var sample: Int64
    /// 从开始播放算起的第几拍，0 起。
    public var beatSerial: Int64
    /// 从开始播放算起的第几小节，0 起（和 PracticeKit 的 bar 一致）。
    public var bar: Int
    /// 小节内第几拍，0 起。
    public var beatInBar: Int
    public var beatsPerBar: Int
    /// 0 = 主拍，其余是切分点。
    public var subIndex: Int
    /// 这一拍实际用的切分（改切分在下一拍才生效，所以和界面上刚选的可能差一拍）。
    public var subdivision: Subdivision
    /// 所属那一拍的重音（用户设置的，不含训练静音）。
    public var accent: AccentLevel
    /// 这一拍被静音训练静掉了。
    public var isTrainingMuted: Bool
    /// 这一拍实际的 BPM（开了渐进提速时由训练方案决定）。
    public var bpm: Double
    public var level: VoiceLevel
    public var gain: Float
    public var sound: SoundKind

    public var isMainBeat: Bool { subIndex == 0 }
}

/// 采样级节拍调度。
///
/// 每拍的位置按 `origin + n * beatLength` 计算后四舍五入到整数采样，不做逐拍累加，所以没有累计漂移。
/// 播放中的任何配置改动都先放进 `pending`，到下一拍的拍头才生效；速度变化（手动改 BPM 或渐进提速换档）
/// 时以那个拍头为新速度段的起点。小节内的拍号位置接着走，不回到第 1 拍。
///
/// 训练方案（PracticeKit 的 TrainingPlan）按小节决定 BPM、按拍决定是否静音，`stop` 型提速到点后停止调度。
///
/// 这是纯值类型，音频线程可以随意复制（例如预测接下来几拍给触感反馈用）。
public struct BeatScheduler: Sendable {
    public let sampleRate: Double
    public private(set) var config: MetronomeConfig
    public private(set) var pending: MetronomeConfig?
    public private(set) var isRunning = false
    /// 训练方案要求的结束点到了（只有渐进提速选“到目标后停止”时会发生）。
    public private(set) var isFinished = false
    /// 当前这一拍在小节里的位置。
    public private(set) var beatInBar = 0
    /// 当前这一拍从开始播放算起的序号。
    public private(set) var beatSerial: Int64 = 0
    /// 当前小节序号，0 起。
    public private(set) var bar = 0
    /// 当前速度段实际使用的 BPM。
    public private(set) var currentBPM: Double

    /// 当前速度段的起点采样位置（第 0 拍）。
    private var origin: Double = 0
    /// 当前这一拍是速度段里的第几拍。
    private var beatInSegment: Int64 = 0
    /// 当前这一拍里下一个要发出的点。
    private var nextSub = 0

    public init(sampleRate: Double, config: MetronomeConfig) {
        self.sampleRate = sampleRate
        self.config = config
        currentBPM = config.bpm
    }

    /// 一拍有多少采样（可以带小数）。
    public var beatLength: Double { sampleRate * 60 / currentBPM }

    /// 当前这一拍拍头的精确位置。
    public var currentBeatPosition: Double { origin + Double(beatInSegment) * beatLength }

    /// 第 `bar` 小节应该用的 BPM：开了渐进提速听训练方案的，否则用配置里的。
    private func targetBPM(atBar bar: Int) -> Double {
        if let plan = config.training, plan.ramp != nil {
            return Double(plan.bpm(atBar: bar))
        }
        return config.bpm
    }

    /// 从 `sample` 开始播放，第一拍就在这个位置。
    public mutating func start(at sample: Int64) {
        if let p = pending {
            config = p
            pending = nil
        }
        origin = Double(sample)
        beatInSegment = 0
        beatInBar = 0
        beatSerial = 0
        bar = 0
        nextSub = 0
        currentBPM = targetBPM(atBar: 0)
        isFinished = false
        isRunning = true
    }

    public mutating func stop() {
        isRunning = false
        if let p = pending {
            config = p
            pending = nil
        }
    }

    /// 更新配置。播放中在下一拍拍头生效，停止时立即生效。连续多次更新以最后一次为准。
    public mutating func update(_ newConfig: MetronomeConfig) {
        if isRunning {
            pending = newConfig
        } else {
            config = newConfig
            currentBPM = targetBPM(atBar: bar)
        }
    }

    /// 生成 `[start, start + count)` 范围内的所有事件，按时间顺序回调。
    /// 必须按顺序、不重叠地调用（每个渲染周期一次）。
    public mutating func generate(from start: Int64, count: Int, _ emit: (ClickEvent) -> Void) {
        guard isRunning, count > 0 else { return }
        let end = start + Int64(count)
        while isRunning {
            if nextSub >= config.subdivision.clickCount {
                // 这一拍的点都发完了。下一拍拍头还不在这段范围内就先不前进，
                // 这样在它发声之前收到的改动都还能赶上“下一拍生效”。
                let boundary = origin + Double(beatInSegment + 1) * beatLength
                if Int64(boundary.rounded()) >= end { return }
                advanceBeat()
                continue
            }
            let length = beatLength
            let position = origin + Double(beatInSegment) * length + config.subdivision.offset(nextSub) * length
            let sample = Int64(position.rounded())
            if sample >= end { return }
            emit(makeEvent(sample: max(sample, start), subIndex: nextSub))
            nextSub += 1
        }
    }

    private func makeEvent(sample: Int64, subIndex: Int) -> ClickEvent {
        let accent = config.accents[beatInBar]
        let silenced = config.training?.isMuted(bar: bar, beat: beatInBar) ?? false
        let isMain = subIndex == 0
        let gain = silenced ? 0 : (isMain ? accent.gain : accent.gain * config.subdivisionVolume)
        return ClickEvent(
            sample: sample,
            beatSerial: beatSerial,
            bar: bar,
            beatInBar: beatInBar,
            beatsPerBar: config.timeSignature.beatsPerBar,
            subIndex: subIndex,
            subdivision: config.subdivision,
            accent: accent,
            isTrainingMuted: silenced,
            bpm: currentBPM,
            level: isMain ? accent.voiceLevel : .weak,
            gain: gain,
            sound: config.sound
        )
    }

    private mutating func advanceBeat() {
        let boundary = origin + Double(beatInSegment + 1) * beatLength
        beatInSegment += 1
        beatSerial += 1
        nextSub = 0
        if let p = pending {
            pending = nil
            config = p
        }
        beatInBar = (beatInBar + 1) % config.timeSignature.beatsPerBar
        if beatInBar == 0 { bar += 1 }
        if config.training?.isFinished(atBar: bar) == true {
            isFinished = true
            isRunning = false
            return
        }
        let bpm = targetBPM(atBar: bar)
        if bpm != currentBPM {
            origin = boundary
            beatInSegment = 0
            currentBPM = bpm
        }
    }
}

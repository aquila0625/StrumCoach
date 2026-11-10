import Foundation

/// 把调度器的事件混成音频。只在一个线程（音频回调或离线测试）里使用。
///
/// 渲染路径上不分配内存、不加锁：发声槽位是预先分配的固定数组，音色在 `VoiceBank` 里。
public final class ClickRenderer: @unchecked Sendable {
    private struct ActiveVoice {
        var data: UnsafeMutableBufferPointer<Float>
        var start: Int64
        var gain: Float
        /// 人声和录音可能比拍间隔长：下一下响起时在这个位置淡出结束（Int64.max 表示不截断）。
        var choke: Int64 = .max
        var chokable = false
    }

    public static let maxVoices = 32

    public let voices: VoiceBank
    public var sampleRate: Double { voices.sampleRate }
    public private(set) var scheduler: BeatScheduler
    /// 已经渲染了多少采样，也就是下一个采样的绝对位置。
    public private(set) var cursor: Int64 = 0
    public var masterGain: Float = 0.9

    private let active: UnsafeMutablePointer<ActiveVoice>
    private var activeCount = 0

    public init(voices: VoiceBank, config: MetronomeConfig) {
        self.voices = voices
        scheduler = BeatScheduler(sampleRate: voices.sampleRate, config: config)
        active = .allocate(capacity: Self.maxVoices)
    }

    deinit { active.deallocate() }

    public var isRunning: Bool { scheduler.isRunning }

    /// 从下一个要渲染的采样开始播放，第一拍就在那里。
    public func start(config: MetronomeConfig) {
        scheduler.update(config)
        scheduler.start(at: cursor)
    }

    /// 停止调度新的点击，已经在响的音自然衰减完。
    public func stop() { scheduler.stop() }

    public func update(_ config: MetronomeConfig) { scheduler.update(config) }

    /// 渲染 `frames` 个采样到 `out`（覆盖写），并对这段里的每个事件回调一次。
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int, onEvent: (ClickEvent) -> Void = { _ in }) {
        out.update(repeating: 0, count: frames)
        let start = cursor
        var sched = scheduler
        sched.generate(from: start, count: frames) { event in
            onEvent(event)
            if event.gain > 0 {
                let chokable = event.sound.isDynamic
                if chokable { chokeDynamicVoices(at: event.sample) }
                addVoice(ActiveVoice(data: buffer(for: event), start: event.sample, gain: event.gain * masterGain, chokable: chokable))
            }
        }
        scheduler = sched

        var kept = 0
        for v in 0..<activeCount {
            let voice = active[v]
            let offset = Int(max(0, voice.start - start))
            let source = Int(start + Int64(offset) - voice.start)
            let n = min(frames - offset, voice.data.count - source)
            if n > 0 {
                let src = voice.data.baseAddress! + source
                let dst = out + offset
                if voice.choke == .max {
                    for i in 0..<n { dst[i] += src[i] * voice.gain }
                } else {
                    let first = start + Int64(offset)
                    for i in 0..<n {
                        let remaining = voice.choke - (first + Int64(i))
                        if remaining <= 0 { break }
                        let fade = remaining < chokeFade ? Float(remaining) / Float(chokeFade) : 1
                        dst[i] += src[i] * voice.gain * fade
                    }
                }
            }
            let ended = voice.choke != .max && voice.choke <= start + Int64(frames)
            if !ended && source + max(n, 0) < voice.data.count {
                active[kept] = voice
                kept += 1
            }
        }
        activeCount = kept

        for i in 0..<frames { out[i] = min(1, max(-1, out[i])) }
        cursor += Int64(frames)
    }

    /// 不改变状态，预测从当前位置起 `frames` 个采样内会出现的主拍。
    /// 接下来 frames 个采样内会响的所有点（主拍和切分点），不改变渲染状态。
    public func peekClicks(frames: Int, _ body: (ClickEvent) -> Void) {
        var copy = scheduler
        copy.generate(from: cursor, count: frames, body)
    }

    public func peekMainBeats(frames: Int, _ body: (ClickEvent) -> Void) {
        var copy = scheduler
        copy.generate(from: cursor, count: frames) { event in
            if event.isMainBeat { body(event) }
        }
    }

    /// 截断时的淡出长度（约 8 ms）。
    private var chokeFade: Int64 { Int64(sampleRate * 0.008) }

    /// 人声报数按小节内第几拍取对应的数字；切分点用咔嗒。我的声音：弱拍用弱拍录音，没录就用强拍的。
    /// 动态声音还没准备好时退回合成的备用音。
    private func buffer(for event: ClickEvent) -> UnsafeMutableBufferPointer<Float> {
        switch event.sound {
        case .voice:
            if event.isMainBeat, let b = voices.dynamicBuffer(VoiceBank.countSlot(event.beatInBar)) { return b }
        case .custom:
            let preferred = event.level == .weak ? VoiceBank.customWeakSlot : VoiceBank.customStrongSlot
            let other = preferred == VoiceBank.customWeakSlot ? VoiceBank.customStrongSlot : VoiceBank.customWeakSlot
            if let b = voices.dynamicBuffer(preferred) ?? voices.dynamicBuffer(other) { return b }
        default:
            break
        }
        return voices.buffer(event.sound, event.level)
    }

    /// 新的一下响起时，还在响的人声/录音在它之前淡出结束，避免高 BPM 时叠在一起。
    private func chokeDynamicVoices(at sample: Int64) {
        for i in 0..<activeCount where active[i].chokable && active[i].choke > sample {
            active[i].choke = sample
        }
    }

    private func addVoice(_ voice: ActiveVoice) {
        if activeCount == Self.maxVoices {
            // 槽位满了就丢掉最老的一个。
            for i in 1..<activeCount { active[i - 1] = active[i] }
            activeCount -= 1
        }
        active[activeCount] = voice
        activeCount += 1
    }
}

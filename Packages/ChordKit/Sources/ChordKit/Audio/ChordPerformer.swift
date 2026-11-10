import Foundation
import AVFoundation
import TunerKit

/// 一个循环要播的内容：事件时间相对循环起点，`length` 是循环的长度（秒）。
public struct PerformedCycle {
    /// 单次播放的事件表（带余音）。
    public var playback: ChordPlayback
    /// 循环长度（秒）：下一个循环从这里开始。
    public var length: Double
    /// 调用方的标记，原样回传。
    public var tag: Int

    public init(playback: ChordPlayback, length: Double, tag: Int) {
        self.playback = playback; self.length = length; self.tag = tag
    }
}

/// 连续演奏：把一个接一个的循环（一小节扫弦、或分解指法走一遍）按**采样时钟**首尾相接地排好，直到 `stop()`；
/// 同时可以随时点一根弦发声，叠加在伴奏上。
///
/// - 循环之间无缝：每个循环的起点是前一个循环终点的整数采样（`LoopTimeline`），用多个播放节点轮流承担，
///   上一个循环的余音自然延续到下一个循环里，换和弦时也不会被切断。
/// - 下一个循环在上一个循环结束前约 `lookahead`（0.15 秒）才向 `cycleProvider` 要内容，
///   所以用户在循环中间点的和弦，会落在下一个循环开头。
/// - 画面同步：`onAudibleCycle` 在“耳朵听到”新循环的那一刻回调；`pluckAges()` 读的是音频渲染时钟（再减去输出延迟）。
@MainActor
public final class ChordPerformer {
    /// 是否由本类设置音频会话（iOS）。App 统一管理会话时设 false。
    public var configuresAudioSession = true
    /// 需要下一个循环时调用；返回 nil 表示结束（演奏停止）。
    public var cycleProvider: (() -> PerformedCycle?)?
    /// 新的循环开始被听到时回调（参数是它的 `tag`）。
    public var onAudibleCycle: ((Int) -> Void)?
    /// 提前多久（秒）去要下一个循环的内容。
    public var lookahead = 0.15
    public private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private var loopNodes: [AVAudioPlayerNode] = []
    private var pluckNodes: [AVAudioPlayerNode] = []
    private var pluckAllocator = VoiceAllocator(count: 4)
    private var loopAllocator = VoiceAllocator(count: 8)
    private var timeline = LoopTimeline(sampleRate: 44100)
    private var sampleRate: Double = 44100
    private var prepared = false
    private var timer: Timer?
    private var lastAudibleTag: Int?
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var cacheOrder: [String] = []

    public init() {}

    // MARK: 启动与停止

    private func prepare() throws {
        guard !prepared else { if !engine.isRunning { try engine.start() }; return }
        #if os(iOS)
        if configuresAudioSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        }
        #endif
        let hw = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = hw.sampleRate > 0 ? hw.sampleRate : 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<8 {        // 每拍一个片段，余音要叠在后面几拍上：快速度（200 BPM）时一个片段最多和后面 5 个片段重叠
            let node = AVAudioPlayerNode()
            engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
            loopNodes.append(node)
        }
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
            pluckNodes.append(node)
        }
        try engine.start()
        for node in pluckNodes { node.play() }
        prepared = true
    }

    /// 开始演奏：先排第一个循环，之后在定时器里一路往后排。
    /// 返回 false 表示没能启动（引擎起不来，或 `cycleProvider` 一开始就没有内容）。
    @discardableResult
    public func start() -> Bool {
        stop()
        do { try prepare() } catch { return false }
        timeline = LoopTimeline(sampleRate: sampleRate)
        loopAllocator.reset()
        lastAudibleTag = nil
        let startHost = AVAudioTime.hostTime(forSeconds: 0.08) &+ mach_absolute_time()
        for node in loopNodes { node.play(at: AVAudioTime(hostTime: startHost)) }
        guard scheduleNext() else { stopNodes(); return false }
        isPlaying = true
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        return true
    }

    /// 停止演奏（点弦发声的余音也一起停）。
    public func stop() {
        timer?.invalidate(); timer = nil
        isPlaying = false
        guard prepared else { return }
        stopNodes()
        for node in pluckNodes { node.stop(); node.play() }
        pluckAllocator.reset()
        timeline.reset()
        lastAudibleTag = nil
    }

    private func stopNodes() {
        for node in loopNodes { node.stop() }
        loopAllocator.reset()
    }

    // MARK: 时钟

    /// 渲染时钟（采样，自开始起）。
    private func renderSample() -> Int64? {
        guard let node = loopNodes.first, node.isPlaying, let nt = node.lastRenderTime,
              let pt = node.playerTime(forNodeTime: nt) else { return nil }
        return pt.sampleTime
    }

    /// 耳朵此刻听到的位置（采样）：渲染时钟减去输出延迟。
    private func audibleSample() -> Int64? {
        renderSample().map { $0 - Int64(engine.outputNode.presentationLatency * sampleRate) }
    }

    private func tick() {
        guard isPlaying, let render = renderSample() else { return }
        // 离当前循环结束不到 lookahead 就去要下一个
        var guardCount = 0
        while Double(timeline.scheduledEnd - render) / sampleRate < lookahead, guardCount < 8 {
            guard scheduleNext() else { stop(); return }
            guardCount += 1
        }
        if let audible = audibleSample(), let cycle = timeline.cycle(at: audible), cycle.tag != lastAudibleTag {
            lastAudibleTag = cycle.tag
            onAudibleCycle?(cycle.tag)
        }
        if let audible = audibleSample() { timeline.prune(before: audible) }
    }

    /// 向 `cycleProvider` 要一个循环，渲染并排到时间线末尾。
    private func scheduleNext() -> Bool {
        guard let provider = cycleProvider, let content = provider() else { return false }
        // 没有事件的片段（休止的一拍）：只占时间线，不发声
        if content.playback.events.isEmpty {
            timeline.append(tag: content.tag, length: content.length, events: [])
            return true
        }
        guard let buffer = buffer(for: content.playback) else { return false }
        let cycle = timeline.append(tag: content.tag, length: content.length, events: content.playback.events)
        let startSeconds = Double(cycle.startSample) / sampleRate
        let index = loopAllocator.reserve(start: startSeconds, duration: Double(buffer.frameLength) / sampleRate)
        loopNodes[index].scheduleBuffer(buffer, at: AVAudioTime(sampleTime: cycle.startSample, atRate: sampleRate),
                                        options: [], completionHandler: nil)
        return true
    }

    /// 此刻听到的循环（`tag`）和在它里面的位置（秒）。
    public func audibleCycleTime() -> (tag: Int, time: Double)? {
        guard isPlaying, let audible = audibleSample(), let c = timeline.cycle(at: audible) else { return nil }
        return (c.tag, Double(audible - c.startSample) / sampleRate)
    }

    /// 此刻每个元素距上一次被拨到过了多久（秒）；`accepting` 决定认可哪些循环（按 `tag`）。
    public func pluckAges(accepting: (Int) -> Bool = { _ in true }) -> [Int: Double] {
        guard isPlaying, let audible = audibleSample() else { return [:] }
        return timeline.ages(at: audible, accepting: accepting)
    }

    // MARK: 点弦发声

    /// 立即发一个音，叠加在伴奏上；没在演奏时也可以用。
    @discardableResult
    public func pluck(_ pitch: Pitch, voice: InstrumentTone.Voice, a4: Double = TunerDefaults.a4, gain: Float = 0.6) -> Bool {
        do { try prepare() } catch { return false }
        let playback = ChordPlayback(events: [PluckEvent(time: 0, string: 0, pitch: pitch, gain: gain)], cycle: nil,
                                     voice: voice, a4: a4, tail: 2.2, noteSeconds: 2.2)
        guard let buffer = buffer(for: playback) else { return false }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let index = pluckAllocator.reserve(start: now, duration: Double(buffer.frameLength) / sampleRate)
        pluckNodes[index].scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    /// 立即播一遍一段事件表（单次，不循环），叠加在伴奏上；输入自定义指法时的试听用。
    @discardableResult
    public func playOnce(_ playback: ChordPlayback) -> Bool {
        guard !playback.events.isEmpty, !playback.isLooping else { return false }
        do { try prepare() } catch { return false }
        guard let buffer = buffer(for: playback) else { return false }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let index = pluckAllocator.reserve(start: now, duration: Double(buffer.frameLength) / sampleRate)
        pluckNodes[index].scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    // MARK: 缓冲

    private func buffer(for playback: ChordPlayback) -> AVAudioPCMBuffer? {
        let key = RhythmStrummer.cacheKey(playback, sampleRate: sampleRate)
        if let hit = cache[key] { return hit }
        let samples = ChordStrummer.render(playback, sampleRate: sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        cache[key] = buffer
        cacheOrder.append(key)
        if cacheOrder.count > 160 { cache[cacheOrder.removeFirst()] = nil }
        return buffer
    }
}

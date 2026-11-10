import Foundation
import AVFoundation
import TunerKit

/// 一次已预约的扫弦：App 可以用它来对齐画面（`hostTime` 是开始发声的主机时间）。
public struct ScheduledStrum: Sendable {
    /// 第一根弦开始发声的主机时间（`mach_absolute_time` 的刻度）。
    public let hostTime: UInt64
    public let events: [PluckEvent]
    public let direction: StrumDirection
    /// 按记号（B / D / d / U / X）预约时是哪一格；按方向预约时为 nil。
    public let cell: StrumCell?

    public init(hostTime: UInt64, events: [PluckEvent], direction: StrumDirection, cell: StrumCell? = nil) {
        self.hostTime = hostTime; self.events = events; self.direction = direction; self.cell = cell
    }

    /// 开始发声的时间（秒，主机时钟）。
    public var seconds: Double { AVAudioTime.seconds(forHostTime: hostTime) }
}

/// 扫弦的预约播放器：把一个和弦的一次扫弦排在**音频时钟上的指定时间点**发声，
/// App 可以把整个节奏型提前排好，和节拍精确对齐。声音来自 TunerKit 内置的真实乐器采样。
///
/// 用法：
/// ```swift
/// let strummer = RhythmStrummer()
/// try strummer.prepare()                                    // 提前启动，第一下就不会有延迟
/// let t0 = RhythmStrummer.hostTime(afterSeconds: 0.1)       // 或用节拍器引擎的某个 AVAudioTime
/// strummer.strum(voicing, instrument: guitar, direction: .down, velocity: 1.25, at: t0)
/// strummer.strum(voicing, instrument: guitar, direction: .up, velocity: 0.7, after: 0.1 + 0.3)
/// strummer.stopAll()                                        // 立即停止全部预约
/// ```
/// 内部有一组播放节点轮流使用（重叠的余音互不打断）；每种扫弦的缓冲只渲染一次并缓存，预约时不占用 CPU。
@MainActor
public final class RhythmStrummer {
    /// 是否由本类设置音频会话（iOS）。App 统一管理会话时设 false。
    public var configuresAudioSession = true
    public var a4: Double = TunerDefaults.a4
    /// 最多同时叠几个播放节点（余音重叠的扫弦数）。
    public let maxVoices: Int

    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var allocator: VoiceAllocator
    private var sampleRate: Double = 44100
    private var prepared = false
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var cacheOrder: [String] = []

    public init(maxVoices: Int = 8) {
        self.maxVoices = max(2, maxVoices)
        allocator = VoiceAllocator(count: max(2, maxVoices))
    }

    // MARK: 时钟

    /// 现在的主机时间。
    public static var nowHostTime: UInt64 { mach_absolute_time() }

    /// 从现在起 `seconds` 秒之后的主机时间（负数按 0）。
    public static func hostTime(afterSeconds seconds: Double) -> AVAudioTime {
        AVAudioTime(hostTime: nowHostTime &+ AVAudioTime.hostTime(forSeconds: max(0, seconds)))
    }

    // MARK: 启动

    /// 建好引擎并启动。不调用也行（第一次 `strum` 会自动调用），但提前调用可以避免第一下有启动延迟。
    public func prepare() throws {
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
        for _ in 0..<maxVoices {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
        }
        try engine.start()
        for node in nodes { node.play() }
        prepared = true
    }

    // MARK: 预约

    /// 在指定的音频时间点扫一下当前和弦。
    ///
    /// - Parameters:
    ///   - instrument: 哪件乐器（决定用哪套采样）；也可以用 `voice:` 的版本。
    ///   - velocity: 力度，1 是普通，重音给 1.25，弱拍 0.7。
    ///   - muted: 闷音（切音）。
    ///   - time: 主机时间的 `AVAudioTime`（见 `hostTime(afterSeconds:)`，或取节拍器引擎的渲染时间）；nil 表示立即。
    /// - Returns: 实际预约的时间和每根弦的发声时刻（动画用）；乐器不能扫弦（`instrument.supportsStrumming` 为 false，
    ///   如贝斯）、没有可弹的弦或引擎启动失败时是 nil。
    @discardableResult
    public func strum(_ voicing: ChordVoicing, instrument: Instrument, direction: StrumDirection = .down,
                      velocity: Float = 1, muted: Bool = false, at time: AVAudioTime? = nil) -> ScheduledStrum? {
        guard instrument.supportsStrumming else { return nil }
        return strum(voicing, voice: InstrumentTone.Voice(family: instrument.family), direction: direction,
              velocity: velocity, muted: muted, at: time)
    }

    @discardableResult
    public func strum(_ voicing: ChordVoicing, voice: InstrumentTone.Voice, direction: StrumDirection = .down,
                      velocity: Float = 1, muted: Bool = false, at time: AVAudioTime? = nil) -> ScheduledStrum? {
        let playback = RhythmStrum.playback(voicing: voicing, direction: direction, velocity: velocity, muted: muted,
                                            voice: voice, a4: a4)
        return schedule(playback, direction: direction, at: time)
    }

    /// 相对现在 `seconds` 秒后扫一下。
    @discardableResult
    public func strum(_ voicing: ChordVoicing, instrument: Instrument, direction: StrumDirection = .down,
                      velocity: Float = 1, muted: Bool = false, after seconds: Double) -> ScheduledStrum? {
        guard instrument.supportsStrumming else { return nil }
        return strum(voicing, instrument: instrument, direction: direction, velocity: velocity, muted: muted,
              at: Self.hostTime(afterSeconds: seconds))
    }

    /// 按节奏型里的记号扫一格：`B` 根音（只拨根音弦）、`D` 全扫（从根音弦扫到 1 弦）、`d` 半扫（高音 3–4 根弦）、
    /// `U` 上扫、`X` 闷音；空拍和不能扫弦的乐器返回 nil。`chord` 用来确定根音弦。
    @discardableResult
    public func strum(_ voicing: ChordVoicing, instrument: Instrument, chord: Chord, cell: StrumCell,
                      velocity: Float = 1, at time: AVAudioTime? = nil) -> ScheduledStrum? {
        guard instrument.supportsStrumming else { return nil }
        return strum(voicing, voice: InstrumentTone.Voice(family: instrument.family), rootPitchClass: chord.root, cell: cell,
                     velocity: velocity, at: time)
    }

    /// 同上，相对现在 `seconds` 秒后。
    @discardableResult
    public func strum(_ voicing: ChordVoicing, instrument: Instrument, chord: Chord, cell: StrumCell,
                      velocity: Float = 1, after seconds: Double) -> ScheduledStrum? {
        strum(voicing, instrument: instrument, chord: chord, cell: cell, velocity: velocity,
              at: Self.hostTime(afterSeconds: seconds))
    }

    /// 同上，直接指定采样和根音音级（不检查乐器）。
    @discardableResult
    public func strum(_ voicing: ChordVoicing, voice: InstrumentTone.Voice, rootPitchClass: Int, cell: StrumCell,
                      velocity: Float = 1, at time: AVAudioTime? = nil) -> ScheduledStrum? {
        guard cell.isStroke else { return nil }
        let playback = RhythmStrum.playback(voicing: voicing, cell: cell, rootPitchClass: rootPitchClass, velocity: velocity,
                                            voice: voice, a4: a4)
        return schedule(playback, direction: cell == .up ? .up : .down, cell: cell, at: time)
    }

    /// 预约任意一段事件表（单次，不循环）。
    @discardableResult
    public func schedule(_ playback: ChordPlayback, direction: StrumDirection = .down, cell: StrumCell? = nil,
                         at time: AVAudioTime? = nil) -> ScheduledStrum? {
        guard !playback.events.isEmpty, !playback.isLooping else { return nil }
        do { try prepare() } catch { return nil }
        guard let buffer = buffer(for: playback) else { return nil }
        let now = Self.nowHostTime
        let start = max(time?.isHostTimeValid == true ? time!.hostTime : now, now)
        let startSeconds = AVAudioTime.seconds(forHostTime: start)
        let duration = Double(buffer.frameLength) / sampleRate
        let index = allocator.reserve(start: startSeconds, duration: duration)
        let node = nodes[index]
        node.scheduleBuffer(buffer, at: AVAudioTime(hostTime: start), options: [], completionHandler: nil)
        return ScheduledStrum(hostTime: start, events: playback.events, direction: direction, cell: cell)
    }

    /// 立即停止全部已预约的和正在发声的扫弦。
    public func stopAll() {
        allocator.reset()
        guard prepared else { return }
        for node in nodes { node.stop(); node.play() }
    }

    // MARK: 缓冲

    private func buffer(for playback: ChordPlayback) -> AVAudioPCMBuffer? {
        let key = Self.cacheKey(playback, sampleRate: sampleRate)
        if let hit = cache[key] { return hit }
        let samples = ChordStrummer.render(playback, sampleRate: sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        cache[key] = buffer
        cacheOrder.append(key)
        if cacheOrder.count > 96 { cache[cacheOrder.removeFirst()] = nil }
        return buffer
    }

    static func cacheKey(_ p: ChordPlayback, sampleRate: Double) -> String {
        let events = p.events.map { "\($0.string):\($0.pitch.midi):\(Int($0.time * 100_000)):\(Int($0.gain * 1000))" }.joined(separator: ",")
        return "\(p.voice.rawValue)|\(Int(p.a4 * 10))|\(Int(sampleRate))|\(Int(p.tail * 1000))|\(Int((p.noteSeconds ?? 0) * 1000))|\(p.cycle.map { Int($0 * 1000) } ?? 0)|\(events)"
    }
}

/// 给每次预约挑一个空闲的播放节点：节点还在播上一次扫弦的余音时不能再排，否则会排到它后面。
/// 纯计算，可测试。时间都是主机时钟的秒数。
struct VoiceAllocator {
    private var busyUntil: [Double]

    init(count: Int) { busyUntil = [Double](repeating: 0, count: count) }

    mutating func reset() { for i in busyUntil.indices { busyUntil[i] = 0 } }

    /// 选一个在 `start` 之前已经空闲的节点；都忙时选最早空闲的（会排在它后面）。返回节点序号。
    mutating func reserve(start: Double, duration: Double) -> Int {
        let free = busyUntil.indices.filter { busyUntil[$0] <= start }
        // 优先用空闲了最久的，让每个节点轮流用
        let pick = free.min { busyUntil[$0] < busyUntil[$1] } ?? busyUntil.indices.min { busyUntil[$0] < busyUntil[$1] }!
        busyUntil[pick] = max(start, busyUntil[pick]) + duration
        return pick
    }
}

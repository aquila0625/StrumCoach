import Foundation
import AVFoundation

/// 一段解码好的乐器采样（单声道）。
public struct SampleBuffer: Sendable {
    public let voice: InstrumentTone.Voice
    public let midi: Int
    /// 这段采样里弹的音实际的基频（真人演奏不是标准平均律，所以不等于 `midi` 对应的频率）。
    public let rootFrequency: Double
    public let sampleRate: Double
    public let data: [Float]
    /// 拉弦采样的循环区间 `[start, end)`；拨弦采样为 nil（只播一遍，自然衰减）。
    /// 循环是无缝的：`data[end]` 在逻辑上等于 `data[start]`。
    public let loop: Range<Int>?

    public var duration: Double { Double(data.count) / sampleRate }
}

/// 内置的真实乐器采样库（见 `Sounds/LICENSES.md`）：每种乐器每隔 1–3 个半音一个音，
/// 播放时用重采样把它精确调到目标频率。
public final class SampleBank: @unchecked Sendable {
    public static let shared = SampleBank()

    struct Entry: Decodable {
        let file: String
        let midi: Int
        let f0: Double
        let frames: Int
        let loopStart: Int?
        let loopEnd: Int?
    }
    private struct VoiceManifest: Decodable { let sampleRate: Double; let samples: [Entry] }
    private struct Manifest: Decodable { let voices: [String: VoiceManifest] }

    private let root: URL?
    private let voices: [String: VoiceManifest]
    private let lock = NSLock()
    private var cache: [String: SampleBuffer] = [:]
    private let cacheLimit = 40

    /// - Parameter directory: 采样目录（含 `manifest.json`）；默认用包里自带的。
    public init(directory: URL? = nil) {
        let dir = directory ?? Bundle.module.url(forResource: "Samples", withExtension: nil)
        var loaded: [String: VoiceManifest] = [:]
        if let dir, let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            loaded = m.voices
        }
        self.root = dir
        self.voices = loaded
    }

    public func hasSamples(for voice: InstrumentTone.Voice) -> Bool { !(voices[voice.rawValue]?.samples.isEmpty ?? true) }

    /// 该乐器所有采样的 (midi, 实测基频)。
    public func roots(for voice: InstrumentTone.Voice) -> [(midi: Int, frequency: Double)] {
        (voices[voice.rawValue]?.samples ?? []).map { ($0.midi, $0.f0) }
    }

    /// 离 `frequency` 最近（按音分）的那段采样，已解码。找不到或解码失败返回 nil。
    public func sample(for voice: InstrumentTone.Voice, nearestTo frequency: Double) -> SampleBuffer? {
        guard frequency > 0, let manifest = voices[voice.rawValue], !manifest.samples.isEmpty else { return nil }
        let entry = manifest.samples.min { abs(log2(frequency / $0.f0)) < abs(log2(frequency / $1.f0)) }!
        return load(entry, voice: voice)
    }

    private func load(_ entry: Entry, voice: InstrumentTone.Voice) -> SampleBuffer? {
        lock.lock()
        if let hit = cache[entry.file] { lock.unlock(); return hit }
        lock.unlock()
        guard let root, let decoded = Self.decode(root.appendingPathComponent(entry.file), frames: entry.frames) else { return nil }
        var loop: Range<Int>?
        if let s = entry.loopStart, let e = entry.loopEnd, s < e, e <= decoded.count { loop = s..<e }
        let buffer = SampleBuffer(voice: voice, midi: entry.midi, rootFrequency: entry.f0,
                                  sampleRate: voices[voice.rawValue]?.sampleRate ?? 44_100, data: decoded, loop: loop)
        lock.lock()
        if cache.count >= cacheLimit { cache.removeValue(forKey: cache.keys.first!) }
        cache[entry.file] = buffer
        lock.unlock()
        return buffer
    }

    /// 解码到单声道 Float；长度对齐到 manifest 里的帧数（AAC 解码器可能多出或少几帧）。
    static func decode(_ url: URL, frames: Int) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let capacity = AVAudioFrameCount(file.length)
        guard capacity > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        var out = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        if out.count > frames { out.removeLast(out.count - frames) }
        if out.count < frames { out.append(contentsOf: [Float](repeating: 0, count: frames - out.count)) }
        return out
    }
}

import AVFoundation
import MetronomeCore
import Observation
import OSLog

private let log = Logger(subsystem: "com.example.tunebeatchord", category: "sounds")

/// 运行时生成或录制的节拍声音：人声报数（按界面语言用系统语音合成）和“我的声音”（用户录音）。
/// 处理好的声音交给音频引擎的动态槽位（`VoiceBank.setDynamic`）；引擎重建时由 `AudioEngineHost` 重新写入。
@MainActor
@Observable
final class DynamicSounds {
    struct Clip: Sendable {
        var samples: [Float]
        var rate: Double
        var seconds: Double { Double(samples.count) / rate }
    }

    /// “我的声音”的强拍、弱拍录音。
    private(set) var customStrong: Clip?
    private(set) var customWeak: Clip?
    /// 人声报数已经按哪种语言生成好了；正在生成时 `isRenderingCount` 为 true。
    private(set) var countLanguage: String?
    private(set) var isRenderingCount = false

    /// 槽位有变化时回调（AudioEngineHost 写进引擎）。
    @ObservationIgnored var onChange: ((Int, Clip?) -> Void)?
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var countClips: [Int: Clip] = [:]

    /// 引擎重建后需要重新写入的全部槽位。
    var allSlots: [(Int, Clip)] {
        var slots: [(Int, Clip)] = countClips.map { ($0.key, $0.value) }
        if let customStrong { slots.append((VoiceBank.customStrongSlot, customStrong)) }
        if let customWeak { slots.append((VoiceBank.customWeakSlot, customWeak)) }
        return slots
    }

    init(loadFromDisk: Bool = true) {
        guard loadFromDisk else { return }
        customStrong = Self.load(VoiceBank.customStrongSlot)
        customWeak = Self.load(VoiceBank.customWeakSlot)
    }

    // MARK: 我的声音

    func clip(slot: Int) -> Clip? { slot == VoiceBank.customWeakSlot ? customWeak : customStrong }

    /// 处理并保存一段录音。返回处理后的长度（秒）；录到的全是静音时返回 nil。
    @discardableResult
    func setCustom(slot: Int, raw: [Float], rate: Double) -> Double? {
        guard let samples = SoundClipProcessor.process(raw, rate: rate, maxSeconds: VoiceBank.dynamicMaxSeconds) else { return nil }
        let clip = Clip(samples: samples, rate: rate)
        if slot == VoiceBank.customWeakSlot { customWeak = clip } else { customStrong = clip }
        Self.save(clip, slot: slot)
        onChange?(slot, clip)
        return clip.seconds
    }

    func deleteCustom(slot: Int) {
        if slot == VoiceBank.customWeakSlot { customWeak = nil } else { customStrong = nil }
        try? FileManager.default.removeItem(at: Self.url(slot))
        onChange?(slot, nil)
    }

    private static func url(_ slot: Int) -> URL {
        let dir = URL.documentsDirectory.appending(path: "CustomVoice", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: slot == VoiceBank.customWeakSlot ? "weak.caf" : "strong.caf")
    }

    private static func save(_ clip: Clip, slot: Int) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: clip.rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(clip.samples.count)
        clip.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: clip.samples.count) }
        do {
            let file = try AVAudioFile(forWriting: url(slot), settings: format.settings)
            try file.write(from: buffer)
        } catch {
            log.error("save custom voice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(_ slot: Int) -> Clip? {
        let u = url(slot)
        guard FileManager.default.fileExists(atPath: u.path), let (samples, rate) = AudioFileReader.read(u) else { return nil }
        return Clip(samples: samples, rate: rate)
    }

    // MARK: 人声报数

    /// 按界面语言生成 1…16 的报数声音（已经是这种语言就跳过）。
    func prepareCount(language: String) {
        guard countLanguage != language, !isRenderingCount else { return }
        isRenderingCount = true
        Task {
            let synth = AVSpeechSynthesizer()
            synthesizer = synth
            let voice = AVSpeechSynthesisVoice(language: Self.speechLanguage(language))
            var clips: [Int: Clip] = [:]
            for n in 1...VoiceBank.countSlots {
                let utterance = AVSpeechUtterance(string: "\(n)")
                utterance.voice = voice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.15
                guard let (raw, rate) = await Self.synthesize(utterance, with: synth),
                      let samples = SoundClipProcessor.process(raw, rate: rate, maxSeconds: 0.8) else { continue }
                let clip = Clip(samples: samples, rate: rate)
                let slot = VoiceBank.countSlot(n - 1)
                clips[slot] = clip
                onChange?(slot, clip)
            }
            countClips = clips
            countLanguage = clips.isEmpty ? nil : language
            isRenderingCount = false
            synthesizer = nil
            log.info("voice count ready: \(language, privacy: .public), \(clips.count) clips")
        }
    }

    /// 系统语音合成到内存（不出声）。
    private static func synthesize(_ utterance: AVSpeechUtterance, with synth: AVSpeechSynthesizer) async -> ([Float], Double)? {
        await withCheckedContinuation { continuation in
            var samples: [Float] = []
            var rate = 0.0
            var finished = false
            synth.write(utterance) { buffer in
                guard !finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    finished = true
                    continuation.resume(returning: samples.isEmpty ? nil : (samples, rate))
                    return
                }
                rate = pcm.format.sampleRate
                samples += AudioFileReader.mono(pcm)
            }
        }
    }

    /// 界面语言 → 系统语音的语言代码。
    static func speechLanguage(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "pt-BR": return "pt-BR"
        case "it": return "it-IT"
        case "ru": return "ru-RU"
        case "tr": return "tr-TR"
        default: return "en-US"
        }
    }
}

/// 把一段声音处理成节拍音：切掉开头的静音（按能量找起音点），截到最长时长，峰值归一化，首尾加短淡入淡出。
enum SoundClipProcessor {
    static func process(_ raw: [Float], rate: Double, maxSeconds: Double) -> [Float]? {
        guard !raw.isEmpty, rate > 0 else { return nil }
        let peak = raw.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0.01 else { return nil }   // 全是静音
        let threshold = max(peak * 0.1, 0.004)

        // 起音点：第一个超过阈值的采样，往前留 1 ms
        guard let first = raw.firstIndex(where: { abs($0) > threshold }) else { return nil }
        let start = max(0, first - Int(0.001 * rate))
        // 结尾：最后一个超过阈值的采样，往后留 30 ms 尾音
        let last = raw.lastIndex(where: { abs($0) > threshold * 0.5 }) ?? (raw.count - 1)
        let end = min(raw.count, last + Int(0.03 * rate), start + Int(maxSeconds * rate))
        guard end > start else { return nil }

        var out = Array(raw[start..<end])
        let scale = 0.95 / peak
        let fadeIn = max(1, Int(0.0005 * rate)), fadeOut = min(out.count, max(1, Int(0.01 * rate)))
        for i in out.indices {
            var g = scale
            if i < fadeIn { g *= Float(i + 1) / Float(fadeIn) }
            let fromEnd = out.count - i
            if fromEnd <= fadeOut { g *= Float(fromEnd) / Float(fadeOut) }
            out[i] *= g
        }
        return out
    }
}

/// 读音频文件、把 PCM 缓冲区转成单声道浮点。
enum AudioFileReader {
    static func read(_ url: URL) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return (mono(buffer), file.processingFormat.sampleRate)
    }

    static func mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let n = Int(buffer.frameLength)
        if let data = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: n))
        }
        if let data = buffer.int16ChannelData {
            return UnsafeBufferPointer(start: data[0], count: n).map { Float($0) / 32_768 }
        }
        if let data = buffer.int32ChannelData {
            return UnsafeBufferPointer(start: data[0], count: n).map { Float($0) / 2_147_483_648 }
        }
        return []
    }
}

/// 录“我的声音”：最长 2 秒，录完交给 DynamicSounds 处理保存。录音前先停掉节拍器，把音频会话切到录音。
@MainActor
@Observable
final class CustomVoiceRecorder: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable { case idle, recording(slot: Int), denied }

    private(set) var state: State = .idle
    /// 最近一次结果的提示（例如“没有录到声音”）。
    private(set) var message: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private weak var sounds: DynamicSounds?

    func record(slot: Int, sounds: DynamicSounds, before: () -> Void) {
        guard state != .recording(slot: slot) else { stop(); return }
        self.sounds = sounds
        message = nil
        before()
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                guard granted else { self.state = .denied; return }
                self.begin(slot: slot)
            }
        }
    }

    func stop() { recorder?.stop() }

    private func begin(slot: Int) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appending(path: "custom-voice-\(slot).caf")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            recorder = r
            r.record(forDuration: VoiceBank.dynamicMaxSeconds)
            state = .recording(slot: slot)
        } catch {
            log.error("record failed: \(error.localizedDescription, privacy: .public)")
            message = String(localized: "无法录音：\(error.localizedDescription)", bundle: .appLanguage, locale: .appLanguage)
            state = .idle
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor in self.finish(url: url) }
    }

    private func finish(url: URL) {
        guard case let .recording(slot) = state else { return }
        state = .idle
        recorder = nil
        guard let (raw, rate) = AudioFileReader.read(url), let sounds,
              sounds.setCustom(slot: slot, raw: raw, rate: rate) != nil else {
            message = String(localized: "没有录到声音，请靠近麦克风再录一次", bundle: .appLanguage, locale: .appLanguage)
            return
        }
        try? FileManager.default.removeItem(at: url)
        play(slot: slot)
    }

    /// 试听一段录音（处理后的）。
    func play(slot: Int) {
        guard let clip = sounds?.clip(slot: slot),
              let format = AVAudioFormat(standardFormatWithSampleRate: clip.rate, channels: 1) else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: "custom-preview.caf")
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(clip.samples.count)
        clip.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: clip.samples.count) }
        do {
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback && session.category != .playAndRecord {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            log.error("preview failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func attach(_ sounds: DynamicSounds) { self.sounds = sounds }
}

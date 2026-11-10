import Foundation
import AVFoundation

/// 用 AVAudioEngine 的 input node 采集麦克风，并在后台队列上做音高检测。
///
/// 回调 `onDetection` 在内部串行队列上触发（不是主线程），约每 `hopSeconds` 秒一次；
/// 信号太弱或没有音高时参数为 nil。一般不需要直接用它——`TunerModel` 已经封装好了。
public final class MicrophoneInput {
    public enum MicError: Error { case noInputFormat }

    public var onDetection: (@Sendable (RawPitch?) -> Void)?
    /// 两次检测之间的间隔（秒）。
    public var hopSeconds: Double = 0.025
    /// 为 true 时开始时会设置 `.playAndRecord` 音频会话（仅 iOS）。
    /// App 若已自行管理会话（例如和节拍器共用），请设为 false。
    public var configuresAudioSession = true

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "TunerKit.MicrophoneInput", qos: .userInitiated)
    private let detector = PitchDetector()
    private var ring: [Float] = []
    private var sinceLastDetection = 0
    private var frameLength = 4096
    private var sampleRate: Double = 44100
    private var hop = 1102
    public private(set) var isRunning = false

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        #if os(iOS)
        if configuresAudioSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicError.noInputFormat }

        sampleRate = format.sampleRate
        frameLength = PitchDetector.recommendedFrameLength(sampleRate: sampleRate,
                                                           minFrequency: detector.configuration.minFrequency)
        hop = max(256, Int(sampleRate * hopSeconds))
        queue.sync {
            ring = [Float](repeating: 0, count: frameLength)
            sinceLastDetection = 0
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async { self.consume(chunk) }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func consume(_ chunk: [Float]) {
        guard isRunning else { return }
        let n = chunk.count
        if n >= ring.count {
            ring = Array(chunk.suffix(ring.count))
        } else {
            ring.removeFirst(n)
            ring.append(contentsOf: chunk)
        }
        sinceLastDetection += n
        guard sinceLastDetection >= hop else { return }
        sinceLastDetection = 0
        let result = detector.detect(ring, sampleRate: sampleRate)
        onDetection?(result)
    }
}

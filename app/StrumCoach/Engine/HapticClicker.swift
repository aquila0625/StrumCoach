import CoreHaptics
import MetronomeCore
import QuartzCore

/// 每拍的触感反馈：强拍重、弱拍轻。按音频时钟算出的时间点提前排程，和声音对齐。
final class HapticClicker {
    let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var engineRunning = false

    func prepare() {
        guard isSupported else { return }
        if engine == nil {
            guard let e = try? CHHapticEngine() else { return }
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = false
            e.stoppedHandler = { [weak self] _ in self?.engineRunning = false }
            e.resetHandler = { [weak self] in self?.engineRunning = false }
            engine = e
        }
        if !engineRunning {
            engineRunning = (try? engine?.start()) != nil
        }
    }

    /// 在设备时钟 `hostTime`（CACurrentMediaTime 时基）播放一次触感。
    func play(_ accent: AccentLevel, atHostTime hostTime: Double) {
        guard accent != .muted else { return }
        prepare()
        guard let engine, engineRunning else { return }
        let (intensity, sharpness): (Float, Float) = switch accent {
        case .strong: (1.0, 0.7)
        case .medium: (0.7, 0.5)
        default: (0.4, 0.3)
        }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        // 把设备时钟换算到触感引擎自己的时钟上
        let delay = max(0, hostTime - CACurrentMediaTime())
        try? player.start(atTime: engine.currentTime + delay)
    }

    func stop() {
        engine?.stop()
        engineRunning = false
    }
}

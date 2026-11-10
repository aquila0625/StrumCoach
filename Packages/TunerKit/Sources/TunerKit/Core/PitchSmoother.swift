import Foundation

/// 对连续的检测结果做平滑，避免指针乱跳。
///
/// - 在对数频率域做中值滤波 + 指数平滑；
/// - 突然跳到别的音（超过 `jumpCents`）时，要连续 `confirmFrames` 帧都稳定在新音上才接受，单帧误判会被丢弃；
/// - 信号短暂丢失时保持上一次的结果 `holdFrames` 帧，之后才输出 nil。
public struct PitchSmoother: Sendable {
    public var medianCount = 5
    /// 指数平滑系数（0…1，越大跟得越快）。
    public var alpha = 0.45
    public var jumpCents = 70.0
    public var confirmFrames = 3
    public var holdFrames = 12

    private var history: [Double] = []     // log2(Hz)
    private var pending: [Double] = []
    private var current: Double?
    private var clarity = 0.0
    private var misses = 0

    public init() {}

    public mutating func reset() {
        history.removeAll(); pending.removeAll()
        current = nil; clarity = 0; misses = 0
    }

    public var isActive: Bool { current != nil }

    @discardableResult
    public mutating func process(_ raw: RawPitch?, a4: Double) -> PitchReading? {
        guard let raw else {
            misses += 1
            if misses > holdFrames { reset(); return nil }
            return reading(a4: a4)
        }
        misses = 0
        let lf = log2(raw.frequency)

        guard let cur = current else {
            history = [lf]; current = lf; clarity = raw.clarity
            return reading(a4: a4)
        }

        if abs(lf - cur) * 1200 > jumpCents {
            // 可能是误判，也可能是真的换了音：先攒着
            if let last = pending.last, abs(lf - last) * 1200 > jumpCents / 2 { pending.removeAll() }
            pending.append(lf)
            if pending.count >= confirmFrames {
                history = pending; current = median(pending); clarity = raw.clarity
                pending.removeAll()
            }
            return reading(a4: a4)
        }

        pending.removeAll()
        history.append(lf)
        if history.count > medianCount { history.removeFirst(history.count - medianCount) }
        let med = median(history)
        current = cur + alpha * (med - cur)
        clarity += 0.5 * (raw.clarity - clarity)
        return reading(a4: a4)
    }

    private func reading(a4: Double) -> PitchReading? {
        guard let current else { return nil }
        return PitchReading(frequency: pow(2, current), clarity: clarity, a4: a4)
    }

    private func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        return s[s.count / 2]
    }
}

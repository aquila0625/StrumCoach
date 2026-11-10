import Foundation

/// 连续演奏的时间线：一个接一个的“循环”（一小节扫弦，或分解指法走完一遍）在采样时钟上首尾相接。
/// 纯计算，不碰音频硬件，所以衔接是否无缝、有没有漂移都可以在测试里直接验证。
///
/// 每个循环的起点是前一个循环的终点（整数采样），所以首尾相接没有空隙；终点按“累计的理想秒数”四舍五入，
/// 所以和理想节拍的误差永远不超过半个采样，播多久都不会漂移（不是把每个循环各自取整再相加）。
struct LoopTimeline {
    struct Cycle: Equatable {
        /// 调用方给的标记（模型用它找到这个循环对应的和弦状态）。
        let tag: Int
        let startSample: Int64
        let lengthSamples: Int
        /// 事件时间相对本循环起点，秒。
        let events: [PluckEvent]

        var endSample: Int64 { startSample + Int64(lengthSamples) }
    }

    let sampleRate: Double
    private(set) var cycles: [Cycle] = []
    /// 已排程的最后一个循环的终点，也就是下一个循环的起点。
    private(set) var scheduledEnd: Int64 = 0
    /// 累计的理想时长（秒）。
    private var idealEnd = 0.0

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// 排下一个循环；返回它（含起点）。
    @discardableResult
    mutating func append(tag: Int, length: Double, events: [PluckEvent]) -> Cycle {
        idealEnd += length
        let end = max(scheduledEnd + 1, Int64((idealEnd * sampleRate).rounded()))
        let cycle = Cycle(tag: tag, startSample: scheduledEnd, lengthSamples: Int(end - scheduledEnd), events: events)
        cycles.append(cycle)
        scheduledEnd = cycle.endSample
        return cycle
    }

    /// 包含这个采样位置的循环。
    func cycle(at sample: Int64) -> Cycle? {
        cycles.last { $0.startSample <= sample && sample < $0.endSample }
    }

    /// 此刻每个元素距上一次被拨到过了多久（秒）。只看 `accepting` 认可的循环（换和弦之后旧和弦的余音动画不该画在新指法图上）。
    func ages(at sample: Int64, window: Double = PluckClock.window, accepting: (Int) -> Bool = { _ in true }) -> [Int: Double] {
        var result: [Int: Double] = [:]
        let now = Double(sample) / sampleRate
        for c in cycles where c.startSample <= sample && accepting(c.tag) {
            let start = Double(c.startSample) / sampleRate
            guard now - start < Double(c.lengthSamples) / sampleRate + window else { continue }
            for e in c.events {
                let age = now - (start + e.time)
                if age >= 0 && age < window { result[e.key] = min(result[e.key] ?? .infinity, age) }
            }
        }
        return result
    }

    /// 丢掉已经播完很久的循环。
    mutating func prune(before sample: Int64) {
        let keep = Int64(2 * sampleRate)
        cycles.removeAll { $0.endSample + keep < sample }
    }

    mutating func reset() { cycles.removeAll(); scheduledEnd = 0; idealEnd = 0 }
}

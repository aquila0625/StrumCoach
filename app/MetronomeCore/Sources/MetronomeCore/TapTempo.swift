import Foundation

/// TAP 测速：取最近 4 次点按的平均间隔；距上次点按超过 2 秒就重新计算。
public struct TapTempo: Sendable {
    public var resetInterval: TimeInterval = 2
    public var window = 4
    public private(set) var taps: [TimeInterval] = []

    public init() {}

    /// 记录一次点按，返回算出的 BPM（至少两次点按才有结果），已限制在 20–400。
    public mutating func tap(at time: TimeInterval) -> Double? {
        if let last = taps.last, time - last > resetInterval || time <= last {
            taps.removeAll()
        }
        taps.append(time)
        if taps.count > window { taps.removeFirst(taps.count - window) }
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
        let average = (last - first) / Double(taps.count - 1)
        let range = MetronomeConfig.bpmRange
        return min(max(60 / average, range.lowerBound), range.upperBound)
    }

    public mutating func reset() { taps.removeAll() }
}

/// 速度术语，随 BPM 变化。
public enum TempoTerm {
    private static let table: [(upTo: Double, zh: String, it: String)] = [
        (40, "庄板", "Grave"),
        (60, "广板", "Largo"),
        (66, "小广板", "Larghetto"),
        (76, "柔板", "Adagio"),
        (108, "行板", "Andante"),
        (120, "中板", "Moderato"),
        (156, "快板", "Allegro"),
        (176, "活板", "Vivace"),
        (200, "急板", "Presto"),
        (.infinity, "最急板", "Prestissimo"),
    ]

    /// 意大利文术语，例如 120 → "Allegro"。区间左闭右开。
    public static func italian(for bpm: Double) -> String { entry(for: bpm).it }

    /// 当前语言的本地名称，例如中文“快板”、日文“アレグロ”；英文等直接用意大利文的语言为空。
    public static func localName(for bpm: Double) -> String { L10n.lookup(entry(for: bpm).zh) }

    /// 界面上显示的完整术语：本地名称 + 意大利文，例如 "快板 Allegro"；没有本地名称时只显示意大利文。
    public static func name(for bpm: Double) -> String {
        let local = localName(for: bpm), it = italian(for: bpm)
        return local.isEmpty || local == it ? it : "\(local) \(it)"
    }

    private static func entry(for bpm: Double) -> (upTo: Double, zh: String, it: String) {
        table.first { bpm < $0.upTo } ?? table[table.count - 1]
    }
}

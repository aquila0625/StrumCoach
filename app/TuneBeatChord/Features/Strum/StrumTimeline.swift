import ChordKit
import Foundation
import TunerKit

/// 训练页用和弦库同一套扫弦节奏型（ChordKit 的 `StrumRhythm`）：预设在前，用户自定义的在后。
extension StrumRhythm {
    /// 某类乐器能用的节奏型；没有和弦库（测试）时只有预设。
    @MainActor static func available(for family: InstrumentFamily, library: ChordLibraryModel?) -> [StrumRhythm] {
        library?.strumRhythms(for: family) ?? presets(for: family)
    }

    /// 按 id 找：先找预设，再找所有乐器里自定义的。找不到（比如自定义的已经删了）是 nil。
    @MainActor static func find(_ id: String, library: ChordLibraryModel?) -> StrumRhythm? {
        if let preset = preset(id: id) { return preset }
        return library?.customRhythms.values.joined().compactMap(\.rhythm).first { $0.id == id }
    }

    /// 界面上的名字：预设按 App 语言；自定义的是用户起的名字，没起名就叫“自定义”。
    var displayTitle: String {
        let title = ChordStrings.current.title(self)
        if isCustom, title.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "自定义", bundle: .appLanguage, locale: .appLanguage)
        }
        return title
    }
}

/// 一次示范或跟练里，每个应该扫的格在时间轴上的位置（秒，和 `start` 同一时钟）。
struct StrumTimeline: Sendable {
    struct Stroke: Equatable, Sendable {
        /// 第几小节（0 起）
        var bar: Int
        /// 小节里第几格
        var step: Int
        var stroke: StrumCell
        var time: Double
    }

    let pattern: StrumRhythm
    let bpm: Double
    /// 第一小节第一格的时间
    let start: Double
    let bars: Int

    var beatDuration: Double { 60 / bpm }
    var stepDuration: Double { beatDuration / Double(pattern.cellsPerBeat) }
    var barDuration: Double { beatDuration * Double(pattern.beatsPerBar) }
    var end: Double { start + barDuration * Double(bars) }

    /// 所有要扫的格（不含空格），按时间先后
    var strokes: [Stroke] {
        (0..<bars).flatMap { bar in
            pattern.cells.enumerated().compactMap { i, s in
                s.isStroke ? Stroke(bar: bar, step: i, stroke: s, time: start + barDuration * Double(bar) + stepDuration * Double(i)) : nil
            }
        }
    }

    /// 某一时刻在第几小节第几格；还没开始或已经结束是 nil
    func position(at t: Double) -> (bar: Int, step: Int)? {
        guard t >= start, t < end else { return nil }
        let index = Int((t - start) / stepDuration)
        return (index / pattern.cells.count, index % pattern.cells.count)
    }

    /// 紧接着的下一遍（循环时用：从这一遍结束的那一刻开始，没有空隙）
    func following() -> StrumTimeline { StrumTimeline(pattern: pattern, bpm: bpm, start: end, bars: bars) }

    /// 倒数一小节的拍点（从 start 往前数）
    var countInBeats: [Double] {
        (0..<pattern.beatsPerBar).map { start - beatDuration * Double(pattern.beatsPerBar - $0) }
    }
}

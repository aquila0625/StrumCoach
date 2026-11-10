import Foundation
import TunerKit

/// 一小节（或分解指法走完一遍）的演奏计划：每一项在小节里的**拍位置**（不是秒）和它的事件。
///
/// 连续演奏时每次只排一拍（`segment`）：每拍用当时的速度换算成秒，所以演奏中改速度，从下一拍开始生效，
/// 不打断、不跳拍；换和弦、换节奏型仍然只在小节开头生效。纯计算，可测试。
struct BarPlan {
    struct Item {
        /// 在小节里的位置，单位是拍（四分音符）。
        let beat: Double
        /// 事件时间相对这一项自己（扫弦里弦与弦之间的几毫秒间隔，不随速度变）。
        let events: [PluckEvent]
    }

    var lengthBeats: Double
    var items: [Item]
    /// 扫弦节奏型每拍几格（小格子高亮用）；分解指法为 nil。
    var cellsPerBeat: Int?

    /// 从第 `start` 拍起的一个片段：最多一拍（小节末尾可能不足一拍，分解指法的步数是奇数时）。
    /// 事件时间相对片段起点，单位秒，按 `beatDuration`（一拍多少秒）换算。
    func segment(from start: Double, beatDuration: Double) -> (events: [PluckEvent], beats: Double) {
        let beats = max(0, min(1, lengthBeats - start))
        let eps = 1e-9
        var events: [PluckEvent] = []
        for item in items where item.beat >= start - eps && item.beat < start + beats - eps {
            let offset = (item.beat - start) * beatDuration
            events += item.events.map {
                PluckEvent(time: offset + $0.time, string: $0.string, fret: $0.fret, pitch: $0.pitch, gain: $0.gain, hold: $0.hold)
            }
        }
        return (events, beats)
    }

    /// 整个小节的事件（按 `beatDuration` 换算成秒），测试和一次性试听用。
    func wholeBar(beatDuration: Double) -> [PluckEvent] {
        var all: [PluckEvent] = []
        var s = 0.0
        while s < lengthBeats - 1e-9 {
            let seg = segment(from: s, beatDuration: beatDuration)
            all += seg.events.map {
                PluckEvent(time: s * beatDuration + $0.time, string: $0.string, fret: $0.fret, pitch: $0.pitch, gain: $0.gain, hold: $0.hold)
            }
            s += 1
        }
        return all
    }
}

extension PlaybackBuilder {
    /// 扫弦节奏型的一小节计划：每个 B / D / d / U / X 格是一项，位置是 格序号 ÷ 每拍格数 拍。
    /// `rootPitchClass` 是和弦的根音音级（决定根音弦）；不传时取按法里最低的音。
    static func strumRhythmPlan(voicing: ChordVoicing, rhythm: StrumRhythm, voice: InstrumentTone.Voice, a4: Double,
                                rootPitchClass: Int? = nil) -> BarPlan {
        let root = rootPitchClass ?? voicing.lowestPitch?.pitchClass ?? 0
        let items = rhythm.cells.enumerated().compactMap { i, cell -> BarPlan.Item? in
            guard cell.isStroke else { return nil }
            let hit = RhythmStrum.playback(voicing: voicing, cell: cell, rootPitchClass: root,
                                           velocity: rhythm.velocity(ofCell: i), voice: voice, a4: a4)
            return BarPlan.Item(beat: Double(i) / Double(rhythm.cellsPerBeat), events: hit.events)
        }
        return BarPlan(lengthBeats: Double(rhythm.beatsPerBar), items: items, cellsPerBeat: rhythm.cellsPerBeat)
    }

    /// 把“事件时间单位是拍”的循环事件表（分解指法用 `interval: 0.5` 生成，即每步半拍）变成计划。
    static func loopPlan(fromBeats loop: ChordPlayback) -> BarPlan {
        let items = loop.events.map {
            BarPlan.Item(beat: $0.time, events: [PluckEvent(time: 0, string: $0.string, fret: $0.fret, pitch: $0.pitch, gain: $0.gain, hold: $0.hold)])
        }
        return BarPlan(lengthBeats: loop.cycle ?? ((loop.events.map(\.time).max() ?? 0) + 0.5), items: items, cellsPerBeat: nil)
    }
}

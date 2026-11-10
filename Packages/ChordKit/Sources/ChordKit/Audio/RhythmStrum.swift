import Foundation
import TunerKit

/// 扫弦的方向。
public enum StrumDirection: String, Codable, Sendable, CaseIterable {
    /// 下扫：从低音弦扫到高音弦，所有发声的弦。
    case down
    /// 上扫：从高音弦往回，只扫较高的 3–4 根弦（更接近真实的上扫）。
    case up
}

/// 节奏扫弦（给训练页的“扫弦节奏型”跟练用）：比和弦库里试听的扫弦快、短，可以分方向、力度和闷音。
/// 这里只生成事件表（纯计算，可测试）；预约到音频时钟上的时间点由 `RhythmStrummer` 做。
public enum RhythmStrum {
    /// 默认的弦间隔（秒）：下扫约 12 毫秒，上扫更快约 9 毫秒；各带 ±10% 的确定性小起伏。
    public static let downGap = 0.012
    public static let upGap = 0.009
    /// 一次扫弦之后留的余音（秒）；闷音只留一瞬间。
    public static let tail = 1.2
    public static let mutedTail = 0.09

    /// 这个方向实际扫哪几根弦（物理序号，按拨弦先后排）。
    /// 下扫是全部发声的弦从低到高；上扫是最高的几根（5 根以上取 4 根，否则 3 根），从最高的一根开始往回。
    public static func strings(for voicing: ChordVoicing, direction: StrumDirection) -> [Int] {
        let sounding = voicing.soundingStrings
        switch direction {
        case .down:
            return sounding
        case .up:
            let k = min(sounding.count, sounding.count >= 5 ? 4 : 3)
            return Array(sounding.suffix(k).reversed())
        }
    }

    // MARK: 按记号选弦（B / D / d / U / X）

    /// 根音弦（物理序号）：发声的弦里音高最低的、音名是根音的那一根；找不到时取音高最低的发声弦。
    public static func rootString(of voicing: ChordVoicing, rootPitchClass: Int) -> Int? {
        let sounding = voicing.soundingStrings
        let withRoot = sounding.filter { voicing.pitches[$0]?.pitchClass == rootPitchClass }
        func pitch(_ i: Int) -> Int { voicing.pitches[i]?.midi ?? .max }
        return (withRoot.isEmpty ? sounding : withRoot).min { pitch($0) < pitch($1) }
    }

    /// 高音的几根弦（物理序号，低到高）：发声的弦 5 根以上取最细的 4 根，否则取 3 根（尤克里里 4 根弦取 3 根）。
    public static func trebleStrings(of voicing: ChordVoicing) -> [Int] {
        let sounding = voicing.soundingStrings
        return Array(sounding.suffix(min(sounding.count, sounding.count >= 5 ? 4 : 3)))
    }

    /// 这一格实际拨哪几根弦（物理序号，按拨弦先后排）：
    /// - `B`：只有根音弦；
    /// - `D`（全扫）：从根音弦扫到最细的弦，音高比根音弦低的弦不扫（尤克里里的高音 G 比根音弦高，照扫）；
    /// - `d`（半扫）：高音的 3–4 根弦，从低往高；`U`：同样的弦，从最细的一根往回；
    /// - `X`（闷音）：全部发声的弦；空拍：没有。
    public static func strings(for voicing: ChordVoicing, cell: StrumCell, rootPitchClass: Int) -> [Int] {
        switch cell {
        case .rest: return []
        case .mute: return voicing.soundingStrings
        case .bass: return rootString(of: voicing, rootPitchClass: rootPitchClass).map { [$0] } ?? []
        case .up: return Array(trebleStrings(of: voicing).reversed())
        case .downTreble: return trebleStrings(of: voicing)
        case .down:
            guard let root = rootString(of: voicing, rootPitchClass: rootPitchClass), let floor = voicing.pitches[root] else {
                return voicing.soundingStrings
            }
            return voicing.soundingStrings.filter { (voicing.pitches[$0] ?? floor) >= floor }
        }
    }

    /// 一格的事件表。`rootPitchClass` 是和弦的根音音级（0…11）。
    public static func playback(voicing: ChordVoicing, cell: StrumCell, rootPitchClass: Int, velocity: Float = 1,
                                voice: InstrumentTone.Voice, a4: Double = TunerDefaults.a4, gap: Double? = nil) -> ChordPlayback {
        let order = strings(for: voicing, cell: cell, rootPitchClass: rootPitchClass)
        let level = min(max(velocity, 0.05), 1.6)
        let muted = cell == .mute
        let up = cell == .up
        let base = gap ?? (up ? upGap : downGap)
        // 根音单拨用比扫弦里单根弦更大的力度；半扫 / 上扫整体更轻
        let each: Float = cell == .bass
            ? 0.45 * level
            : Float(0.5 / Double(max(2, order.count)).squareRoot()) * level * (muted ? 0.8 : 1) * ((up || cell == .downTreble) ? 0.85 : 1)
        var time = 0.0
        var events: [PluckEvent] = []
        for (k, i) in order.enumerated() {
            if k > 0 { time += base * (1 + 0.1 * sin(Double(k) * 2.399 + Double(i))) }
            let weight = Float(1 - 0.15 * Double(k) / Double(max(1, order.count - 1)))
            guard let pitch = voicing.pitches[i] else { continue }
            events.append(PluckEvent(time: time, string: i, pitch: pitch, gain: each * weight, hold: muted ? mutedTail : nil))
        }
        return ChordPlayback(events: events, cycle: nil, voice: voice, a4: a4, tail: muted ? mutedTail : tail)
    }

    /// - Parameters:
    ///   - velocity: 力度，1 是普通；重音可以给 1.25，弱拍 0.7。夹在 0.05…1.6。
    ///   - muted: 闷音（切音）：只发一声短促的“嚓”，余音立刻切掉。
    ///   - gap: 弦间隔（秒），默认见 `downGap` / `upGap`。
    public static func playback(voicing: ChordVoicing, direction: StrumDirection = .down, velocity: Float = 1,
                                muted: Bool = false, voice: InstrumentTone.Voice, a4: Double = TunerDefaults.a4,
                                gap: Double? = nil) -> ChordPlayback {
        let order = strings(for: voicing, direction: direction)
        let base = gap ?? (direction == .down ? downGap : upGap)
        let level = min(max(velocity, 0.05), 1.6)
        let each = Float(0.5 / Double(max(2, order.count)).squareRoot()) * level * (muted ? 0.8 : 1) * (direction == .up ? 0.8 : 1)
        var time = 0.0
        var events: [PluckEvent] = []
        for (k, i) in order.enumerated() {
            if k > 0 { time += base * (1 + 0.1 * sin(Double(k) * 2.399 + Double(i))) }
            // 下扫低音弦力度稍大，上扫从最高的弦开始越往低越重一点
            let weight = Float(1 - 0.15 * Double(k) / Double(max(1, order.count - 1)))
            guard let pitch = voicing.pitches[i] else { continue }
            events.append(PluckEvent(time: time, string: i, pitch: pitch, gain: each * weight, hold: muted ? mutedTail : nil))
        }
        return ChordPlayback(events: events, cycle: nil, voice: voice, a4: a4, tail: muted ? mutedTail : tail)
    }
}

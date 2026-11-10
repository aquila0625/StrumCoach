import Foundation
import TunerKit

/// 一次拨弦：什么时候、哪根弦、什么音。动画和声音共用同一份事件表，所以画面和声音永远对得上。
public struct PluckEvent: Hashable, Sendable {
    /// 在一个周期（或一次扫弦）里的时间，秒。
    public let time: Double
    /// 弦的物理序号（与定弦一致，0 = 第一根弦）。
    public let string: Int
    /// 贝斯的和弦音位置图用品位来区分同一根弦上的标记；吉他、尤克里里为 nil。
    public let fret: Int?
    public let pitch: Pitch
    /// 这一下的力度（峰值幅度，0…1）。
    public let gain: Float
    /// 这个音最多响多久（秒），之后切掉（闷音）；nil 表示自然衰减。
    public let hold: Double?

    public init(time: Double, string: Int, fret: Int? = nil, pitch: Pitch, gain: Float, hold: Double? = nil) {
        self.time = time; self.string = string; self.fret = fret; self.pitch = pitch; self.gain = gain; self.hold = hold
    }

    /// 动画里用来对应图上的元素：吉他、尤克里里是弦序号；贝斯是 弦 × 100 + 品。
    public var key: Int { fret.map { string * 100 + $0 } ?? string }
}

/// 一段要播放的内容：扫弦（播一遍）或分解和弦（按周期循环到停止）。
public struct ChordPlayback: Equatable, Sendable {
    public var events: [PluckEvent]
    /// 循环周期（秒）；nil 表示只播一遍。
    public var cycle: Double?
    public var voice: InstrumentTone.Voice
    public var a4: Double = TunerDefaults.a4
    /// 一遍播完后留的余音（秒），循环时不用。
    public var tail: Double = 3.0
    /// 每个音最多响多久（秒）；nil 用默认（2.6 秒，单次播放时再加上余音）。连续演奏时要短一些，省渲染。
    public var noteSeconds: Double?

    public init(events: [PluckEvent], cycle: Double?, voice: InstrumentTone.Voice,
                a4: Double = TunerDefaults.a4, tail: Double = 3.0, noteSeconds: Double? = nil) {
        self.events = events; self.cycle = cycle; self.voice = voice; self.a4 = a4; self.tail = tail
        self.noteSeconds = noteSeconds
    }

    public var isLooping: Bool { cycle != nil }
}

/// 把播放位置换算成“每个元素距上一次被拨到过了多久”，供指法图做高亮和抖动。纯计算，可测试。
public enum PluckClock {
    /// 动画持续的时间（秒）；超过就不再高亮。
    public static let window = 0.9

    /// - Parameters:
    ///   - time: 在这段播放里的位置（秒）。循环播放时会按周期取余。
    /// - Returns: `PluckEvent.key` → 距上一次拨到的时间（秒，0 表示刚拨），只含窗口内的。
    public static func ages(events: [PluckEvent], cycle: Double?, time: Double, window: Double = window) -> [Int: Double] {
        guard time >= 0 else { return [:] }
        var result: [Int: Double] = [:]
        let position = cycle.map { $0 > 0 ? time.truncatingRemainder(dividingBy: $0) : time } ?? time
        for e in events {
            var since = position - e.time
            if since < 0, let cycle { since += cycle }
            guard since >= 0, since < window else { continue }
            result[e.key] = min(result[e.key] ?? .infinity, since)
        }
        return result
    }
}

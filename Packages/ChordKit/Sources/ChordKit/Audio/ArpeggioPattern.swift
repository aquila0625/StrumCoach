import Foundation
import TunerKit

/// 一种分解和弦的弹法：按什么弦序一个音一个音地拨。
///
/// 弦号用习惯的写法（吉他 6 弦最粗、1 弦最细；尤克里里 4 弦是高音 G、1 弦是 A），
/// 吉他里的 **5 代表“根音弦”**：C 和弦根音在 5 弦就是 5，D 和弦在 4 弦就换成 4，G 和弦在 6 弦就换成 6。
/// 指法里的弦在当前把位不弹时，这一拍跳过（节奏不变）。
///
/// **加新指法**：在 `ArpeggioPattern.all` 里加一条即可，说明文字要进 String Catalog。
public struct ArpeggioPattern: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// 固定的弦号序列。吉他里的 5 在运行时换成根音弦。
        case strings([Int])
        /// 上行 + 下行琶音：从根音弦依次到 1 弦，再回到根音弦的上一根弦（接着循环）。
        case sweep
        /// 贝斯：根音、五度、八度、五度。
        case rootFifthOctave
        /// 用户自定义：弦号序列，`.root` 是当前和弦的根音弦（所有乐器都按“最低的带根音的发声弦”换）。
        case custom([ArpeggioStep])
    }

    /// 自定义指法的 id 前缀。
    public static let customPrefix = "custom-"
    public var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    public let id: String
    public let family: InstrumentFamily
    public let kind: Kind
    /// 面板里显示的数字串，例如 "5 3 2 1"（用空格隔开：输入时短横是空拍，显示也不用短横，免得误导）。
    public let digits: String
    /// 一行说明（String Catalog 的键，简体中文原文）。
    public let summary: String
    public let englishSummary: String

    public init(id: String, family: InstrumentFamily, kind: Kind, digits: String, summary: String, englishSummary: String) {
        self.id = id; self.family = family; self.kind = kind
        self.digits = digits; self.summary = summary; self.englishSummary = englishSummary
    }

    /// 吉他里代表“根音弦”的占位弦号。
    public static let rootSlot = 5

    public static let all: [ArpeggioPattern] = [
        ArpeggioPattern(id: "g-5321", family: .guitar, kind: .strings([5, 3, 2, 1]),
                        digits: "5 3 2 1", summary: "四拍上行", englishSummary: "Four-beat rise"),
        ArpeggioPattern(id: "g-53231323", family: .guitar, kind: .strings([5, 3, 2, 3, 1, 3, 2, 3]),
                        digits: "5 3 2 3 1 3 2 3", summary: "八分音符分解", englishSummary: "Eighth-note arpeggio"),
        ArpeggioPattern(id: "g-532313", family: .guitar, kind: .strings([5, 3, 2, 3, 1, 3]),
                        digits: "5 3 2 3 1 3", summary: "三拍子分解", englishSummary: "Waltz arpeggio"),
        ArpeggioPattern(id: "g-523132", family: .guitar, kind: .strings([5, 2, 3, 1, 3, 2]),
                        digits: "5 2 3 1 3 2", summary: "交替八分", englishSummary: "Alternating eighths"),
        ArpeggioPattern(id: "g-sweep", family: .guitar, kind: .sweep,
                        digits: "5 4 3 2 1 2 3 4", summary: "上行下行琶音", englishSummary: "Up-and-down sweep"),
        ArpeggioPattern(id: "u-4321", family: .ukulele, kind: .strings([4, 3, 2, 1]),
                        digits: "4 3 2 1", summary: "四弦上行", englishSummary: "Four-string rise"),
        ArpeggioPattern(id: "u-432123", family: .ukulele, kind: .strings([4, 3, 2, 1, 2, 3]),
                        digits: "4 3 2 1 2 3", summary: "来回分解", englishSummary: "Back-and-forth"),
        ArpeggioPattern(id: "u-3212", family: .ukulele, kind: .strings([3, 2, 1, 2]),
                        digits: "3 2 1 2", summary: "常见指弹", englishSummary: "Classic fingerpicking"),
        ArpeggioPattern(id: "b-rfof", family: .bass, kind: .rootFifthOctave,
                        digits: "R 5 8 5", summary: "根音 · 五度 · 八度 · 五度", englishSummary: "Root · fifth · octave · fifth"),
    ]

    public static func patterns(for family: InstrumentFamily) -> [ArpeggioPattern] {
        all.filter { $0.family == family }
    }

    public static func pattern(id: String) -> ArpeggioPattern? { all.first { $0.id == id } }

    /// 每种乐器默认用哪一个。
    public static func defaultPattern(for family: InstrumentFamily) -> ArpeggioPattern? { patterns(for: family).first }

    // MARK: 展开成弦序

    /// 吉他的“根音弦”弦号：和弦里最低的那根带根音的发声弦；没有时取最低的发声弦。
    public static func rootStringNumber(voicing: ChordVoicing, chord: Chord, tuning: Tuning) -> Int? {
        let sounding = voicing.soundingStrings
        let withRoot = sounding.filter { voicing.pitches[$0]?.pitchClass == chord.root }
        let pick = withRoot.min { voicing.pitches[$0]!.midi < voicing.pitches[$1]!.midi }
            ?? sounding.min { voicing.pitches[$0]!.midi < voicing.pitches[$1]!.midi }
        return pick.map { tuning.strings[$0].number }
    }

    /// 把指法展开成每一拍的弦号（吉他里的 5 已换成根音弦；自定义指法里的空拍是 0）；贝斯不用。
    public func stringNumbers(rootString: Int?) -> [Int] {
        switch kind {
        case .strings(let list):
            guard family == .guitar, let r = rootString else { return list }
            return list.map { $0 == Self.rootSlot ? r : $0 }
        case .sweep:
            let r = rootString ?? Self.rootSlot
            guard r > 1 else { return [1] }
            return Array((1...r).reversed()) + Array(2..<r)       // r … 1，再 2 … r-1
        case .rootFifthOctave:
            return []
        case .custom(let list):
            return list.map { step in
                switch step {
                case .string(let n): return n
                case .root: return rootString ?? Self.rootSlot
                case .rest: return 0                                    // 0 = 空拍（不弹，占一拍）
                }
            }
        }
    }

    /// 展开成按拍的弦序号（物理序号）；这一拍的弦不弹时是 nil（休止，节奏不变）。
    public func steps(voicing: ChordVoicing, chord: Chord, tuning: Tuning) -> [Int?] {
        let root = Self.rootStringNumber(voicing: voicing, chord: chord, tuning: tuning)
        return stringNumbers(rootString: root).map { number in
            guard let index = tuning.strings.firstIndex(where: { $0.number == number }),
                  voicing.frets.indices.contains(index), voicing.frets[index] >= 0 else { return nil }
            return index
        }
    }
}

/// 把扫弦、分解和弦做成一段 `ChordPlayback`（事件表）。纯计算，可测试。
public enum PlaybackBuilder {
    /// 每个音的默认间隔（秒）：一个八分音符。BPM 没传时按 100。
    public static func noteInterval(bpm: Double?) -> Double {
        let b = (bpm ?? 100).clamped(to: 30...300)
        return (60 / b / 2).clamped(to: 0.1...0.7)
    }

    /// 扫弦：按弦序从低到高（物理顺序），不弹的弦跳过。
    public static func strum(voicing: ChordVoicing, voice: InstrumentTone.Voice, a4: Double,
                             gap: Double = ChordStrummer.defaultGap) -> ChordPlayback {
        let strings = voicing.soundingStrings
        guard let first = strings.first, let firstPitch = voicing.pitches[first] else {
            return ChordPlayback(events: [], cycle: nil, voice: voice, a4: a4)
        }
        let times = ChordStrummer.strumTimes(count: strings.count, gap: gap, firstFrequency: firstPitch.frequency(a4: a4))
        let each = Float(0.5 / Double(max(2, strings.count)).squareRoot())
        let events = strings.enumerated().map { k, i in
            // 向下扫弦：低音弦力度稍大，越往高音弦越轻
            let weight = Float(1 - 0.18 * Double(k) / Double(max(1, strings.count - 1)))
            return PluckEvent(time: times[k], string: i, pitch: voicing.pitches[i]!, gain: each * weight)
        }
        return ChordPlayback(events: events, cycle: nil, voice: voice, a4: a4)
    }

    /// 吉他、尤克里里的分解和弦：每拍一个音，循环。
    public static func arpeggio(pattern: ArpeggioPattern, voicing: ChordVoicing, chord: Chord, tuning: Tuning,
                                voice: InstrumentTone.Voice, a4: Double, interval: Double) -> ChordPlayback {
        let steps = pattern.steps(voicing: voicing, chord: chord, tuning: tuning)
        var events: [PluckEvent] = []
        for (k, step) in steps.enumerated() {
            guard let i = step, let pitch = voicing.pitches[i] else { continue }
            events.append(PluckEvent(time: Double(k) * interval, string: i, pitch: pitch, gain: k == 0 ? 0.5 : 0.38))
        }
        return ChordPlayback(events: events, cycle: Double(steps.count) * interval, voice: voice, a4: a4)
    }

    /// 连续演奏用：把循环播放的事件表变成“一个循环”的内容（单次播放 + 余音 + 循环长度）。
    public static func performedCycle(from loop: ChordPlayback) -> (playback: ChordPlayback, length: Double) {
        let length = loop.cycle ?? ((loop.events.map(\.time).max() ?? 0) + 0.3)
        let tail = min(1.4, 2 * length)
        return (ChordPlayback(events: loop.events, cycle: nil, voice: loop.voice, a4: loop.a4, tail: tail, noteSeconds: 1.8), length)
    }

    /// 一小节扫弦：4 拍，每拍下扫一次，第 1 拍重音。速度按 `bpm`（没有时 100），一拍是一个四分音符。
    public static func strumBar(voicing: ChordVoicing, voice: InstrumentTone.Voice, a4: Double, bpm: Double?,
                                beats: Int = 4) -> (playback: ChordPlayback, length: Double) {
        let beat = 60 / (bpm ?? 100).clamped(to: 30...300)
        var events: [PluckEvent] = []
        for b in 0..<beats {
            let strum = RhythmStrum.playback(voicing: voicing, direction: .down, velocity: b == 0 ? 1.25 : 0.9, voice: voice, a4: a4)
            events += strum.events.map {
                PluckEvent(time: Double(b) * beat + $0.time, string: $0.string, fret: $0.fret, pitch: $0.pitch, gain: $0.gain, hold: $0.hold)
            }
        }
        let length = Double(beats) * beat
        return (ChordPlayback(events: events, cycle: nil, voice: voice, a4: a4, tail: min(1.4, 2 * length), noteSeconds: 1.8), length)
    }

    /// 一小节按节奏型扫弦：每个 D / U / X 格在它的时间点扫一下（下扫、上扫、闷音），空拍不发声。
    /// 一拍是一个四分音符，速度按 `bpm`（没有时 100）。循环长度是一小节。
    public static func strumRhythmBar(voicing: ChordVoicing, rhythm: StrumRhythm, voice: InstrumentTone.Voice, a4: Double,
                                      bpm: Double?, rootPitchClass: Int? = nil) -> (playback: ChordPlayback, length: Double) {
        let tempo = (bpm ?? 100).clamped(to: 30...300)
        let root = rootPitchClass ?? voicing.lowestPitch?.pitchClass ?? 0
        var events: [PluckEvent] = []
        for stroke in rhythm.strokes(bpm: tempo) {
            let hit = RhythmStrum.playback(voicing: voicing, cell: stroke.cell, rootPitchClass: root,
                                           velocity: rhythm.velocity(ofCell: stroke.index), voice: voice, a4: a4)
            events += hit.events.map {
                PluckEvent(time: stroke.time + $0.time, string: $0.string, fret: $0.fret, pitch: $0.pitch, gain: $0.gain, hold: $0.hold)
            }
        }
        let length = rhythm.barDuration(bpm: tempo)
        return (ChordPlayback(events: events, cycle: nil, voice: voice, a4: a4, tail: min(1.4, 2 * length), noteSeconds: 1.8), length)
    }

    /// 贝斯的自定义指法：每一步是一根弦（`R` 是根音所在的弦），发这根弦上品位最低的那个和弦音标记；
    /// 这根弦上没有标记的步休止（节奏不变）。
    public static func bassCustom(pattern: ArpeggioPattern, chord: Chord, tuning: Tuning, positions: BassPositions?,
                                  voice: InstrumentTone.Voice, a4: Double, interval: Double) -> ChordPlayback? {
        guard case .custom(let list) = pattern.kind,
              let positions = positions ?? BassPositions.make(chord: chord, tuning: tuning), let anchor = positions.anchor else { return nil }
        var events: [PluckEvent] = []
        for (k, step) in list.enumerated() {
            let marker: BassPositions.Marker?
            switch step {
            case .root: marker = anchor
            case .rest: marker = nil                                   // 空拍：不弹，占一步
            case .string(let n):
                marker = tuning.strings.firstIndex { $0.number == n }.flatMap { index in
                    positions.markers.filter { $0.string == index }.min { $0.fret < $1.fret }
                }
            }
            guard let m = marker else { continue }
            events.append(PluckEvent(time: Double(k) * interval, string: m.string, fret: m.fret, pitch: m.pitch, gain: k == 0 ? 0.55 : 0.42))
        }
        return ChordPlayback(events: events, cycle: Double(list.count) * interval, voice: voice, a4: a4)
    }

    /// 贝斯：根音 - 五度 - 八度 - 五度，循环。五度取该和弦的五度（减三和弦是减五度，增三和弦是增五度）。
    /// 有把位框时每个音带上它在框里的位置，动画据此高亮对应的标记。
    public static func bassArpeggio(chord: Chord, tuning: Tuning, positions: BassPositions?, voice: InstrumentTone.Voice,
                                    a4: Double, interval: Double) -> ChordPlayback? {
        guard let anchor = positions?.anchor ?? BassPositions.make(chord: chord, tuning: tuning)?.anchor else { return nil }
        let fifth = chord.type.intervals.count > 2 ? chord.type.intervals[2] : 7
        let offsets = [0, fifth, 12, fifth]
        let events = offsets.enumerated().map { k, offset -> PluckEvent in
            let pitch = anchor.pitch.transposed(by: offset)
            let marker = positions?.markers.first { $0.pitch == pitch }
                ?? (offset == 0 ? anchor : nil)
            return PluckEvent(time: Double(k) * interval, string: marker?.string ?? -1, fret: marker?.fret,
                              pitch: pitch, gain: k == 0 ? 0.55 : 0.42)
        }
        return ChordPlayback(events: events, cycle: Double(offsets.count) * interval, voice: voice, a4: a4)
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

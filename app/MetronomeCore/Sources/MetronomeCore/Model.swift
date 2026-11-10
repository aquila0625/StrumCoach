import Foundation
@_exported import PracticeKit

// 节拍器的配置模型。
//
// 拍号、重音、切分、音色 ID 统一用 RhythmKit 的类型（PracticeKit 会 re-export），训练方案用 PracticeKit 的
// TrainingPlan，这里不再定义第二套。下面的扩展只补音频线程需要的“不分配内存”的访问方式和界面文案。
// MetronomeConfig 是给音频线程用的快照：全部是纯值（POD），复制时不会触发内存分配或引用计数。

extension AccentLevel {
    /// 混音增益。用 switch 而不是数组，避免音频线程里访问堆内存。
    public var gain: Float {
        switch self {
        case .strong: return 1.0
        case .medium: return 0.78
        case .weak: return 0.6
        case .muted: return 0
        }
    }

    /// 发声用哪一档音色；静音拍不发声，这里随便给一个。
    public var voiceLevel: VoiceLevel {
        switch self {
        case .strong: return .strong
        case .medium: return .medium
        case .weak, .muted: return .weak
        }
    }

    public var title: String {
        switch self {
        case .strong: return L10n.string("强")
        case .medium: return L10n.string("次强")
        case .weak: return L10n.string("弱")
        case .muted: return L10n.string("静音")
        }
    }
}

/// 每种音色分强、次强、弱三个音。
public enum VoiceLevel: Int, CaseIterable, Sendable {
    case strong = 0, medium, weak
}

/// 一小节内各拍的重音，打包进一个 UInt64（每拍 2 bit，最多 32 拍，和 RhythmKit 的拍数上限一致）。
/// RhythmSettings 里的 `[AccentLevel]` 是堆上的数组，音频线程用这个。
public struct AccentPattern: Equatable, Sendable {
    public static let maxCount = TimeSignature.beatsRange.upperBound
    public private(set) var count: Int
    private var bits: UInt64

    public init(_ accents: [AccentLevel]) {
        precondition(!accents.isEmpty && accents.count <= Self.maxCount)
        count = accents.count
        bits = 0
        for (i, a) in accents.enumerated() { bits |= UInt64(a.rawValue) << (2 * UInt64(i)) }
    }

    public init(repeating accent: AccentLevel, count: Int) {
        self.init(Array(repeating: accent, count: count))
    }

    public subscript(index: Int) -> AccentLevel {
        get {
            precondition(index >= 0 && index < count)
            return AccentLevel(rawValue: Int((bits >> (2 * UInt64(index))) & 0b11))!
        }
        set {
            precondition(index >= 0 && index < count)
            let shift = 2 * UInt64(index)
            bits = (bits & ~(0b11 << shift)) | (UInt64(newValue.rawValue) << shift)
        }
    }

    public var array: [AccentLevel] { (0..<count).map { self[$0] } }
}

extension TimeSignature {
    public init(_ beatsPerBar: Int, _ beatUnit: Int) {
        self.init(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
    }

    /// 设置面板里拍号分子的可选范围（设计稿：1–16）。类型本身支持到 32。
    public static let editorBeats = 1...16
    /// 设置面板里的常用拍号快捷选项。
    public static let quickPicks: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .sixEight, .sevenEight]
}

extension Subdivision {
    /// 一拍内的点数。和 RhythmKit 的 `clicksPerBeat` 相同，但不经过数组，音频线程可用。
    public var clickCount: Int {
        switch self {
        case .quarter: return 1
        case .eighth, .dotted: return 2
        case .triplet, .eighthSixteenth, .sixteenthEighth, .syncopation: return 3
        case .sixteenth: return 4
        }
    }

    /// 第 index 个点在一拍内的位置，等于 RhythmKit 的 `offsets[index]`（测试保证两者一致）。
    public func offset(_ index: Int) -> Double {
        switch (self, index) {
        case (_, 0): return 0
        case (.eighth, 1), (.eighthSixteenth, 1), (.sixteenthEighth, 2), (.sixteenth, 2): return 0.5
        case (.triplet, 1): return 1.0 / 3.0
        case (.triplet, 2): return 2.0 / 3.0
        case (.sixteenth, 1), (.sixteenthEighth, 1), (.syncopation, 1): return 0.25
        case (.sixteenth, 3), (.dotted, 1), (.eighthSixteenth, 2), (.syncopation, 2): return 0.75
        default: preconditionFailure("subdivision index out of range")
        }
    }

    public var title: String {
        switch self {
        case .quarter: return L10n.string("四分")
        case .eighth: return L10n.string("八分")
        case .triplet: return L10n.string("三连音")
        case .sixteenth: return L10n.string("十六分")
        case .dotted: return L10n.string("附点")
        case .eighthSixteenth: return L10n.string("前八后十六")
        case .sixteenthEighth: return L10n.string("前十六后八")
        case .syncopation: return L10n.string("切分音")
        }
    }
}

/// 节拍音色。RhythmSettings 里存的是 ToneID，这里是它在 App 里的具体定义。
/// rawValue 决定 VoiceBank 里的槽位，只能在末尾追加。`voice`（人声报数）和 `custom`（我的声音）
/// 的实际声音在运行时写进 VoiceBank 的动态槽位，还没准备好时用合成的备用音。
public enum SoundKind: Int, CaseIterable, Sendable {
    case woodblock, electronic, cowbell
    case tick, block, clave, click, digital, sonar
    case rimshot, hihat, kickSnare, shaker
    case marimba, triangle, bell
    case voice, custom

    public var tone: ToneID {
        switch self {
        case .woodblock: return "woodblock"
        case .electronic: return "electronic"
        case .cowbell: return "cowbell"
        case .tick: return "tick"
        case .block: return "woodBlock"
        case .clave: return "clave"
        // RhythmKit 的默认值是 "click"，那一直表示木鱼，所以 Click 音色用别的 ID
        case .click: return "metroClick"
        case .digital: return "digital"
        case .sonar: return "sonar"
        case .rimshot: return "rimshot"
        case .hihat: return "hihat"
        case .kickSnare: return "kickSnare"
        case .shaker: return "shaker"
        case .marimba: return "marimba"
        case .triangle: return "triangle"
        case .bell: return "bell"
        case .voice: return "voiceCount"
        case .custom: return "customVoice"
        }
    }

    /// 不认识的 ToneID（包括 RhythmKit 的默认 "click"）按木鱼处理。
    public init(tone: ToneID) {
        self = Self.allCases.first { $0.tone == tone } ?? .woodblock
    }

    public var title: String {
        switch self {
        case .woodblock: return L10n.string("木鱼")
        case .electronic: return L10n.string("哔声")
        case .cowbell: return L10n.string("牛铃")
        case .tick: return L10n.string("机械摆锤")
        case .block: return L10n.string("木块")
        case .clave: return L10n.string("响棒")
        case .click: return L10n.string("咔嗒")
        case .digital: return L10n.string("数码")
        case .sonar: return L10n.string("柔和")
        case .rimshot: return L10n.string("鼓边")
        case .hihat: return L10n.string("踩镲")
        case .kickSnare: return L10n.string("底鼓军鼓")
        case .shaker: return L10n.string("沙锤")
        case .marimba: return L10n.string("马林巴")
        case .triangle: return L10n.string("三角铁")
        case .bell: return L10n.string("铃")
        case .voice: return L10n.string("人声报数")
        case .custom: return L10n.string("我的声音")
        }
    }

    /// 实际声音在运行时生成或录制（人声报数、我的声音）。
    public var isDynamic: Bool { self == .voice || self == .custom }
}

/// 音色分组（音色列表按这个顺序显示）。
public enum SoundGroup: Int, CaseIterable, Sendable {
    case classic, electronic, drums, melodic, voice

    public var title: String {
        switch self {
        case .classic: return L10n.string("经典")
        case .electronic: return L10n.string("电子")
        case .drums: return L10n.string("鼓组")
        case .melodic: return L10n.string("旋律")
        case .voice: return L10n.string("人声")
        }
    }

    public var sounds: [SoundKind] {
        switch self {
        case .classic: return [.tick, .woodblock, .block, .clave, .cowbell]
        case .electronic: return [.click, .electronic, .digital, .sonar]
        case .drums: return [.rimshot, .hihat, .kickSnare, .shaker]
        case .melodic: return [.marimba, .triangle, .bell]
        case .voice: return [.voice, .custom]
        }
    }
}

/// 重音预设（App 的功能，RhythmKit 只有“首拍强”的默认值）。
public enum AccentPreset: Int, CaseIterable, Codable, Sendable {
    /// 首拍强，其余弱（等于 RhythmSettings.defaultAccents）
    case firstStrong
    /// 全部均等（都用弱拍音）
    case allEqual
    /// 按拍号分组：每组第一拍次强，首拍强
    case grouped

    public var title: String {
        switch self {
        case .firstStrong: return L10n.string("首拍强")
        case .allEqual: return L10n.string("全部均等")
        case .grouped: return L10n.string("按拍号分组")
        }
    }

    public func accents(for ts: TimeSignature) -> [AccentLevel] {
        switch self {
        case .firstStrong:
            return RhythmSettings.defaultAccents(for: ts)
        case .allEqual:
            return Array(repeating: .weak, count: ts.beatsPerBar)
        case .grouped:
            var list = Array(repeating: AccentLevel.weak, count: ts.beatsPerBar)
            var start = 0
            for size in Self.groups(for: ts) {
                list[start] = start == 0 ? .strong : .medium
                start += size
            }
            return list
        }
    }

    public func pattern(for ts: TimeSignature) -> AccentPattern { AccentPattern(accents(for: ts)) }

    /// 拍号的分组方式，例如 6/8 → 3+3，7/8 → 2+2+3，4/4 → 2+2。
    public static func groups(for ts: TimeSignature) -> [Int] {
        let n = ts.beatsPerBar
        switch n {
        case ...3: return [n]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 7: return [2, 2, 3]
        case 8 where ts.beatUnit >= 8: return [3, 3, 2]
        default:
            if n % 3 == 0 { return Array(repeating: 3, count: n / 3) }
            if n % 2 == 0 { return Array(repeating: 2, count: n / 2) }
            return Array(repeating: 2, count: (n - 3) / 2) + [3]
        }
    }
}

/// 节拍器的完整配置：RhythmSettings 的内容 + BPM + 切分音量 + 训练方案。界面线程改它，音频线程读它。
public struct MetronomeConfig: Equatable, Sendable {
    public static let bpmRange = Double(Tempo.minimum)...Double(Tempo.maximum)
    public static let defaultSubdivisionVolume: Float = 0.6

    public var bpm: Double {
        didSet { bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound) }
    }
    public private(set) var timeSignature: TimeSignature
    public var accents: AccentPattern
    public var subdivision: Subdivision
    /// 切分点相对主拍的音量，默认 60%。
    public var subdivisionVolume: Float
    public var sound: SoundKind
    /// 渐进提速 / 静音训练。nil 为普通播放。开了渐进提速时 BPM 由方案决定，`bpm` 不起作用。
    public var training: TrainingPlan?

    public init(bpm: Double = Double(Tempo.default),
                timeSignature: TimeSignature = .fourFour,
                accents: AccentPattern? = nil,
                subdivision: Subdivision = .quarter,
                subdivisionVolume: Float = MetronomeConfig.defaultSubdivisionVolume,
                sound: SoundKind = .woodblock,
                training: TrainingPlan? = nil) {
        self.bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        self.timeSignature = timeSignature
        let a = accents ?? AccentPreset.grouped.pattern(for: timeSignature)
        precondition(a.count == timeSignature.beatsPerBar)
        self.accents = a
        self.subdivision = subdivision
        self.subdivisionVolume = subdivisionVolume
        self.sound = sound
        self.training = training
    }

    /// 从 RhythmKit 的节奏设置构造。
    public init(rhythm: RhythmSettings, bpm: Double, subdivisionVolume: Float = MetronomeConfig.defaultSubdivisionVolume,
                training: TrainingPlan? = nil) {
        self.init(bpm: bpm, timeSignature: rhythm.timeSignature, accents: AccentPattern(rhythm.accents),
                  subdivision: rhythm.subdivision, subdivisionVolume: subdivisionVolume,
                  sound: SoundKind(tone: rhythm.tone), training: training)
    }

    /// 转回 RhythmKit 的节奏设置（存盘、交给 PracticeKit 等）。
    public var rhythm: RhythmSettings {
        RhythmSettings(timeSignature: timeSignature, accents: accents.array, subdivision: subdivision, tone: sound.tone)
    }

    /// 改拍号时按预设重新生成重音，保证重音数和拍数一致。
    public mutating func setTimeSignature(_ ts: TimeSignature, preset: AccentPreset) {
        timeSignature = ts
        accents = preset.pattern(for: ts)
    }

    public static let `default` = MetronomeConfig()
}

extension MetronomeConfig: Codable {
    private enum CodingKeys: String, CodingKey { case rhythm, bpm, subdivisionVolume, training }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rhythm: try c.decode(RhythmSettings.self, forKey: .rhythm),
                  bpm: try c.decode(Double.self, forKey: .bpm),
                  subdivisionVolume: try c.decodeIfPresent(Float.self, forKey: .subdivisionVolume) ?? Self.defaultSubdivisionVolume,
                  training: try c.decodeIfPresent(TrainingPlan.self, forKey: .training))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rhythm, forKey: .rhythm)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(subdivisionVolume, forKey: .subdivisionVolume)
        try c.encodeIfPresent(training, forKey: .training)
    }
}

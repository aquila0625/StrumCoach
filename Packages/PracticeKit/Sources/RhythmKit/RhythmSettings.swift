/// 一份完整的节奏设置：拍号、每拍重音、切分、音色（不含 BPM）。
///
/// 不变量：`accents.count == timeSignature.beatsPerBar`。初始化、解码、修改拍号时都会自动维持。
public struct RhythmSettings: Codable, Hashable, Sendable {
    public private(set) var timeSignature: TimeSignature
    public private(set) var accents: [AccentLevel]
    public var subdivision: Subdivision
    public var tone: ToneID

    /// 默认重音：第一拍强，其余弱。
    public static func defaultAccents(for timeSignature: TimeSignature) -> [AccentLevel] {
        (0..<timeSignature.beatsPerBar).map { $0 == 0 ? .strong : .weak }
    }

    /// `accents` 传 nil 用默认重音；数量不符时，多的截掉，缺的补弱拍。
    public init(
        timeSignature: TimeSignature = .fourFour,
        accents: [AccentLevel]? = nil,
        subdivision: Subdivision = .quarter,
        tone: ToneID = .default
    ) {
        self.timeSignature = timeSignature
        self.accents = Self.normalized(accents ?? Self.defaultAccents(for: timeSignature), to: timeSignature)
        self.subdivision = subdivision
        self.tone = tone
    }

    private static func normalized(_ accents: [AccentLevel], to ts: TimeSignature) -> [AccentLevel] {
        if accents.count == ts.beatsPerBar { return accents }
        if accents.count > ts.beatsPerBar { return Array(accents.prefix(ts.beatsPerBar)) }
        return accents + Array(repeating: .weak, count: ts.beatsPerBar - accents.count)
    }

    /// 改拍号：已有的重音设置尽量保留，新增的拍为弱，减少的拍被截掉。
    public mutating func setTimeSignature(_ newValue: TimeSignature) {
        timeSignature = newValue
        accents = Self.normalized(accents, to: newValue)
    }

    /// 某一拍的重音；`beat` 从 0 开始，越界时按小节循环取模。
    public func accent(atBeat beat: Int) -> AccentLevel {
        let n = accents.count
        return accents[((beat % n) + n) % n]
    }

    /// 设置某一拍的重音；越界的 `beat` 被忽略。
    public mutating func setAccent(_ level: AccentLevel, atBeat beat: Int) {
        guard accents.indices.contains(beat) else { return }
        accents[beat] = level
    }

    private enum CodingKeys: String, CodingKey { case timeSignature, accents, subdivision, tone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timeSignature: try c.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) ?? .fourFour,
            accents: try c.decodeIfPresent([AccentLevel].self, forKey: .accents),
            subdivision: try c.decodeIfPresent(Subdivision.self, forKey: .subdivision) ?? .quarter,
            tone: try c.decodeIfPresent(ToneID.self, forKey: .tone) ?? .default
        )
    }
}

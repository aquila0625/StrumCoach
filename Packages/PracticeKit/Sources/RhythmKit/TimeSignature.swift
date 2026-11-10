/// 拍号，例如 4/4、6/8。
///
/// 初始化和解码时都会把非法值修正到合法范围：拍数 1...32，单位拍只允许 2/4/8/16（其余按 4 处理）。
public struct TimeSignature: Codable, Hashable, Sendable {
    public static let beatsRange = 1...32
    public static let allowedBeatUnits = [2, 4, 8, 16]

    public let beatsPerBar: Int
    public let beatUnit: Int

    public init(beatsPerBar: Int, beatUnit: Int) {
        self.beatsPerBar = min(max(beatsPerBar, Self.beatsRange.lowerBound), Self.beatsRange.upperBound)
        self.beatUnit = Self.allowedBeatUnits.contains(beatUnit) ? beatUnit : 4
    }

    private enum CodingKeys: String, CodingKey { case beatsPerBar, beatUnit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            beatsPerBar: try c.decode(Int.self, forKey: .beatsPerBar),
            beatUnit: try c.decode(Int.self, forKey: .beatUnit)
        )
    }

    public var displayName: String { "\(beatsPerBar)/\(beatUnit)" }

    public static let twoFour = TimeSignature(beatsPerBar: 2, beatUnit: 4)
    public static let threeFour = TimeSignature(beatsPerBar: 3, beatUnit: 4)
    public static let fourFour = TimeSignature(beatsPerBar: 4, beatUnit: 4)
    public static let fiveFour = TimeSignature(beatsPerBar: 5, beatUnit: 4)
    public static let sixEight = TimeSignature(beatsPerBar: 6, beatUnit: 8)
    public static let sevenEight = TimeSignature(beatsPerBar: 7, beatUnit: 8)
    public static let nineEight = TimeSignature(beatsPerBar: 9, beatUnit: 8)
    public static let twelveEight = TimeSignature(beatsPerBar: 12, beatUnit: 8)

    public static let presets: [TimeSignature] = [
        .twoFour, .threeFour, .fourFour, .fiveFour, .sixEight, .sevenEight, .nineEight, .twelveEight,
    ]
}

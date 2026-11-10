/// 一拍内的切分方式。`offsets` 是每个发声点在这一拍内的位置（0 ..< 1，以拍长为 1）。
public enum Subdivision: String, Codable, CaseIterable, Sendable {
    /// 四分：一拍一下。
    case quarter
    /// 八分：一拍两下。
    case eighth
    /// 三连音：一拍三下。
    case triplet
    /// 十六分：一拍四下。
    case sixteenth
    /// 附点：附点八分 + 十六分。
    case dotted
    /// 前八后十六：八分 + 十六分 + 十六分。
    case eighthSixteenth
    /// 前十六后八：十六分 + 十六分 + 八分。
    case sixteenthEighth
    /// 切分音：十六分 + 八分 + 十六分。
    case syncopation

    public var offsets: [Double] {
        switch self {
        case .quarter: [0]
        case .eighth: [0, 1.0 / 2]
        case .triplet: [0, 1.0 / 3, 2.0 / 3]
        case .sixteenth: [0, 1.0 / 4, 2.0 / 4, 3.0 / 4]
        case .dotted: [0, 3.0 / 4]
        case .eighthSixteenth: [0, 1.0 / 2, 3.0 / 4]
        case .sixteenthEighth: [0, 1.0 / 4, 2.0 / 4]
        case .syncopation: [0, 1.0 / 4, 3.0 / 4]
        }
    }

    /// 一拍内发声的次数。
    public var clicksPerBeat: Int { offsets.count }
}

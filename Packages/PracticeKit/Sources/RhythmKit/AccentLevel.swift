/// 每拍的重音强度。
public enum AccentLevel: Int, Codable, CaseIterable, Sendable {
    case muted = 0
    case weak = 1
    case medium = 2
    case strong = 3

    public var isAudible: Bool { self != .muted }

    /// 点按一拍时的循环顺序：强 → 次强 → 弱 → 静音 → 强。
    public var cycled: AccentLevel {
        switch self {
        case .strong: .medium
        case .medium: .weak
        case .weak: .muted
        case .muted: .strong
        }
    }
}

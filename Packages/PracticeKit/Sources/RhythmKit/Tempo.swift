/// BPM 的允许范围与夹取。
public enum Tempo {
    public static let minimum = 20
    public static let maximum = 400
    public static let range = minimum...maximum
    public static let `default` = 120

    public static func clamp(_ bpm: Int) -> Int {
        min(max(bpm, minimum), maximum)
    }
}

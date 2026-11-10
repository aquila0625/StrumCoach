/// 一次练习用的模式。
public enum PracticeMode: String, Codable, CaseIterable, Sendable {
    /// 普通播放，没开任何训练。
    case free
    /// 渐进提速。
    case ramp
    /// 静音小节 / 随机静音。
    case mute
    /// 两种训练同时开启。
    case rampAndMute
    /// 扫弦节奏型跟练（App 训练页，收音评分）。
    case strum
}

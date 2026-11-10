import Foundation

/// 一次练习的训练方案：渐进提速和静音可以单独开，也可以同时开。
/// 不碰音频，只回答“第几小节第几拍应该是什么状态”。
public struct TrainingPlan: Codable, Hashable, Sendable {
    /// 某一拍的状态。
    public struct BeatState: Equatable, Sendable {
        public var bpm: Int
        public var isMuted: Bool
        public var isFinished: Bool
    }

    /// 没开渐进提速时使用的速度。
    public var baseBPM: Int
    public var ramp: RampSettings?
    public var mute: MuteSettings?

    public init(baseBPM: Int, ramp: RampSettings? = nil, mute: MuteSettings? = nil) {
        self.baseBPM = Tempo.clamp(baseBPM)
        self.ramp = ramp
        self.mute = mute
    }

    public var mode: PracticeMode {
        switch (ramp != nil, mute != nil) {
        case (false, false): .free
        case (true, false): .ramp
        case (false, true): .mute
        case (true, true): .rampAndMute
        }
    }

    public func bpm(atBar bar: Int) -> Int {
        ramp?.bpm(atBar: bar) ?? baseBPM
    }

    public func isMuted(bar: Int, beat: Int) -> Bool {
        mute?.isMuted(bar: bar, beat: beat) ?? false
    }

    /// 渐进提速进度 0...1；没开提速时返回 nil。
    public func progress(atBar bar: Int) -> Double? {
        ramp?.progress(atBar: bar)
    }

    public func isFinished(atBar bar: Int) -> Bool {
        ramp?.isFinished(atBar: bar) ?? false
    }

    public func state(bar: Int, beat: Int) -> BeatState {
        BeatState(bpm: bpm(atBar: bar), isMuted: isMuted(bar: bar, beat: beat), isFinished: isFinished(atBar: bar))
    }

    /// 播放到第 `bar` 小节（含）为止，BPM 的最低和最高值，写练习记录时用。
    public func bpmRange(throughBar bar: Int) -> ClosedRange<Int> {
        guard let ramp else { return baseBPM...baseBPM }
        // 0...barsToTarget 之间单调；之后 stop/hold 停在目标，loop 回到起点，都不超出这个区间。
        let a = ramp.bpm(atBar: 0)
        let b = ramp.bpm(atBar: min(max(0, bar), ramp.barsToTarget))
        return min(a, b)...max(a, b)
    }
}

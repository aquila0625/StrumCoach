package com.example.strumcoach.metronome

import com.example.strumcoach.rhythm.AccentLevel
import com.example.strumcoach.rhythm.Subdivision
import com.example.strumcoach.rhythm.VoiceLevel

/** 调度器发出的一个发声事件（主拍或切分点）。 */
data class ClickEvent(
    /** 绝对采样位置（从开始播放那一刻的渲染计数算起）。 */
    val sample: Long,
    /** 从开始播放算起的第几拍，0 起。 */
    val beatSerial: Long,
    /** 从开始播放算起的第几小节，0 起。 */
    val bar: Int,
    /** 小节内第几拍，0 起。 */
    val beatInBar: Int,
    val beatsPerBar: Int,
    /** 0 = 主拍，其余是切分点。 */
    val subIndex: Int,
    /** 这一拍实际用的切分（改切分在下一拍才生效）。 */
    val subdivision: Subdivision,
    /** 所属那一拍的重音（用户设置的，不含训练静音）。 */
    val accent: AccentLevel,
    /** 这一拍被静音训练静掉了。 */
    val isTrainingMuted: Boolean,
    /** 这一拍实际的 BPM（开了渐进提速时由训练方案决定）。 */
    val bpm: Double,
    val level: VoiceLevel,
    val gain: Float,
    val sound: SoundKind,
) {
    val isMainBeat: Boolean get() = subIndex == 0
}

/**
 * 采样级节拍调度。
 *
 * 每拍的位置按 `origin + n * beatLength` 计算后四舍五入到整数采样，不做逐拍累加，所以没有累计漂移。
 * 播放中的任何配置改动都先放进 `pending`，到下一拍的拍头才生效；速度变化（手动改 BPM 或渐进提速换档）
 * 时以那个拍头为新速度段的起点。小节内的位置接着走，不回到第 1 拍。
 *
 * 训练方案按小节决定 BPM、按拍决定是否静音，stop 型提速到点后停止调度。
 * 可以 [copy] 出一份预测接下来几拍（给界面高亮用），不影响原调度器。
 */
class BeatScheduler(val sampleRate: Double, config: MetronomeConfig) {
    var config: MetronomeConfig = config
        private set
    var pending: MetronomeConfig? = null
        private set
    var isRunning = false
        private set

    /** 训练方案要求的结束点到了（只有渐进提速选“到目标后停止”时会发生）。 */
    var isFinished = false
        private set

    /** 当前这一拍在小节里的位置。 */
    var beatInBar = 0
        private set

    /** 当前这一拍从开始播放算起的序号。 */
    var beatSerial = 0L
        private set

    /** 当前小节序号，0 起。 */
    var bar = 0
        private set

    /** 当前速度段实际使用的 BPM。 */
    var currentBPM: Double = config.bpm
        private set

    private var origin = 0.0
    private var beatInSegment = 0L
    private var nextSub = 0

    /** 一拍有多少采样（可以带小数）。 */
    val beatLength: Double get() = sampleRate * 60 / currentBPM

    /** 当前这一拍拍头的精确位置。 */
    val currentBeatPosition: Double get() = origin + beatInSegment * beatLength

    fun copy(): BeatScheduler {
        val c = BeatScheduler(sampleRate, config)
        c.pending = pending; c.isRunning = isRunning; c.isFinished = isFinished
        c.beatInBar = beatInBar; c.beatSerial = beatSerial; c.bar = bar; c.currentBPM = currentBPM
        c.origin = origin; c.beatInSegment = beatInSegment; c.nextSub = nextSub
        return c
    }

    private fun targetBPM(bar: Int): Double {
        val plan = config.training
        return if (plan != null && plan.ramp != null) plan.bpm(bar).toDouble() else config.bpm
    }

    /** 从 `sample` 开始播放，第一拍就在这个位置。 */
    fun start(sample: Long) {
        pending?.let { config = it; pending = null }
        origin = sample.toDouble()
        beatInSegment = 0; beatInBar = 0; beatSerial = 0; bar = 0; nextSub = 0
        currentBPM = targetBPM(0)
        isFinished = false
        isRunning = true
    }

    fun stop() {
        isRunning = false
        pending?.let { config = it; pending = null }
    }

    /** 更新配置。播放中在下一拍拍头生效，停止时立即生效。连续多次更新以最后一次为准。 */
    fun update(newConfig: MetronomeConfig) {
        if (isRunning) pending = newConfig
        else {
            config = newConfig
            currentBPM = targetBPM(bar)
        }
    }

    /**
     * 生成 `[start, start + count)` 范围内的所有事件，按时间顺序回调。
     * 必须按顺序、不重叠地调用（每个渲染周期一次）。
     */
    fun generate(start: Long, count: Int, emit: (ClickEvent) -> Unit) {
        if (!isRunning || count <= 0) return
        val end = start + count
        while (isRunning) {
            if (nextSub >= config.subdivision.clickCount) {
                // 这一拍的点都发完了。下一拍拍头还不在这段范围内就先不前进，
                // 这样在它发声之前收到的改动都还能赶上“下一拍生效”。
                val boundary = origin + (beatInSegment + 1) * beatLength
                if (Math.round(boundary) >= end) return
                advanceBeat()
                continue
            }
            val length = beatLength
            val position = origin + beatInSegment * length + config.subdivision.offset(nextSub) * length
            val sample = roundHalfAwayFromZero(position)
            if (sample >= end) return
            emit(makeEvent(maxOf(sample, start), nextSub))
            nextSub += 1
        }
    }

    private fun roundHalfAwayFromZero(x: Double): Long = if (x >= 0) Math.floor(x + 0.5).toLong() else -Math.floor(-x + 0.5).toLong()

    private fun makeEvent(sample: Long, subIndex: Int): ClickEvent {
        val accent = config.accents[beatInBar]
        val silenced = config.training?.isMuted(bar, beatInBar) ?: false
        val isMain = subIndex == 0
        val gain = if (silenced) 0f else if (isMain) accent.gain else accent.gain * config.subdivisionVolume
        return ClickEvent(
            sample = sample, beatSerial = beatSerial, bar = bar, beatInBar = beatInBar,
            beatsPerBar = config.timeSignature.beatsPerBar, subIndex = subIndex, subdivision = config.subdivision,
            accent = accent, isTrainingMuted = silenced, bpm = currentBPM,
            level = if (isMain) accent.voiceLevel else VoiceLevel.WEAK, gain = gain, sound = config.sound,
        )
    }

    private fun advanceBeat() {
        val boundary = origin + (beatInSegment + 1) * beatLength
        beatInSegment += 1
        beatSerial += 1
        nextSub = 0
        pending?.let { pending = null; config = it }
        beatInBar = (beatInBar + 1) % config.timeSignature.beatsPerBar
        if (beatInBar == 0) bar += 1
        if (config.training?.isFinished(bar) == true) {
            isFinished = true
            isRunning = false
            return
        }
        val bpm = targetBPM(bar)
        if (bpm != currentBPM) {
            origin = boundary
            beatInSegment = 0
            currentBPM = bpm
        }
    }
}

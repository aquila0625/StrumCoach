package com.example.tunebeatchord.rhythm

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** 一次练习用的模式。 */
enum class PracticeMode(val id: String) {
    /** 普通播放，没开任何训练。 */
    FREE("free"),
    /** 渐进提速。 */
    RAMP("ramp"),
    /** 静音小节 / 随机静音。 */
    MUTE("mute"),
    /** 两种训练同时开启。 */
    RAMP_AND_MUTE("rampAndMute"),
    /** 扫弦节奏型跟练（训练页，收音评分）。 */
    STRUM("strum");

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: FREE
    }
}

/** 静音训练：训练“自己心里的拍子”。 */
data class MuteSettings(val pattern: Pattern, val keepsDownbeat: Boolean = false) {
    sealed interface Pattern {
        /** 有声 `audible` 小节，接着静音 `muted` 小节，循环。 */
        data class Bars(val audible: Int, val muted: Int) : Pattern

        /** 每一拍以 `probability`（0…1）的概率静音。同一个种子永远得到同一个结果，可以复现。 */
        data class RandomBeats(val probability: Double, val seed: Long) : Pattern
    }

    /** 第 `bar` 小节的第 `beat` 拍是否静音（都从 0 开始，负数按 0 处理）。 */
    fun isMuted(bar: Int, beat: Int): Boolean {
        val b = max(0, bar)
        val k = max(0, beat)
        return when (val p = pattern) {
            is Pattern.Bars -> {
                val on = max(1, p.audible)
                val off = max(0, p.muted)
                b % (on + off) >= on
            }
            is Pattern.RandomBeats -> {
                if (keepsDownbeat && k == 0) return false
                val prob = p.probability.coerceIn(0.0, 1.0)
                val h = mix(mix(mix(p.seed.toULong()) xor b.toULong()) xor k.toULong())
                val unit = (h shr 11).toDouble() / (1L shl 53).toDouble()   // [0, 1)
                unit < prob
            }
        }
    }

    companion object {
        fun bars(audible: Int, muted: Int) = MuteSettings(Pattern.Bars(audible, muted))
        fun randomBeats(probability: Double, seed: Long, keepsDownbeat: Boolean = false) =
            MuteSettings(Pattern.RandomBeats(probability, seed), keepsDownbeat)

        /** SplitMix64 的混合函数（和 iOS 版逐位一致，同一个种子在两个平台得到同样的静音位置）。 */
        private fun mix(x: ULong): ULong {
            var z = x + 0x9E3779B97F4A7C15uL
            z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
            z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
            return z xor (z shr 31)
        }
    }
}

/**
 * 渐进提速：从起始 BPM 出发，每 `barsPerStep` 小节增加 `step`，直到目标 BPM。目标低于起始时是渐进减速。
 * 所有函数都是纯函数，小节序号 `bar` 从 0 开始。
 */
class RampSettings(
    startBPM: Int,
    targetBPM: Int,
    step: Int,
    barsPerStep: Int,
    val endBehavior: EndBehavior = EndBehavior.HOLD,
) {
    enum class EndBehavior(val id: String) {
        /** 目标速度那一档播完后停止。 */
        STOP("stop"),
        /** 到目标后一直保持目标速度。 */
        HOLD("hold"),
        /** 目标速度那一档播完后回到起始 BPM，重新爬。 */
        LOOP("loop");

        companion object {
            fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: HOLD
        }
    }

    val startBPM = Tempo.clamp(startBPM)
    val targetBPM = Tempo.clamp(targetBPM)
    /** 每档变化的 BPM，恒为正数；方向由起止决定。 */
    val step = max(1, step)
    /** 每档持续的小节数，至少 1。 */
    val barsPerStep = max(1, barsPerStep)

    val isAscending get() = targetBPM >= startBPM

    /** 从起始到目标要走几档（最后一档不足一个 step 时直接落到目标）。 */
    val stepCount get() = (abs(targetBPM - startBPM) + this.step - 1) / this.step

    /** 目标速度出现的第一个小节序号。 */
    val barsToTarget get() = stepCount * barsPerStep

    /** 目标速度那一档播完的小节序号：stop 在这里结束，loop 在这里回到起点。 */
    val cycleBars get() = (stepCount + 1) * barsPerStep

    /** 第 bar 小节所在的档位（0 = 起始速度）。loop 时按周期折回。 */
    fun stepIndex(bar: Int): Int {
        var b = max(0, bar)
        if (endBehavior == EndBehavior.LOOP) b %= cycleBars
        return min(b / barsPerStep, stepCount)
    }

    fun bpm(bar: Int): Int {
        val travelled = min(stepIndex(bar) * step, abs(targetBPM - startBPM))
        return if (isAscending) startBPM + travelled else startBPM - travelled
    }

    /** 进度 0…1：已走档数 / 总档数。起止相同（0 档）时恒为 1。 */
    fun progress(bar: Int): Double = if (stepCount > 0) stepIndex(bar).toDouble() / stepCount else 1.0

    /** 只有 stop 会结束：目标速度那一档播完后返回 true。 */
    fun isFinished(bar: Int) = endBehavior == EndBehavior.STOP && max(0, bar) >= cycleBars

    override fun equals(other: Any?) = other is RampSettings && other.startBPM == startBPM && other.targetBPM == targetBPM &&
        other.step == step && other.barsPerStep == barsPerStep && other.endBehavior == endBehavior
    override fun hashCode() = listOf(startBPM, targetBPM, step, barsPerStep, endBehavior).hashCode()
}

/** 一次练习的训练方案：渐进提速和静音可以单独开，也可以同时开。不碰音频。 */
data class TrainingPlan(val baseBPM: Int, val ramp: RampSettings? = null, val mute: MuteSettings? = null) {
    data class BeatState(val bpm: Int, val isMuted: Boolean, val isFinished: Boolean)

    val mode: PracticeMode
        get() = when {
            ramp != null && mute != null -> PracticeMode.RAMP_AND_MUTE
            ramp != null -> PracticeMode.RAMP
            mute != null -> PracticeMode.MUTE
            else -> PracticeMode.FREE
        }

    fun bpm(bar: Int): Int = ramp?.bpm(bar) ?: Tempo.clamp(baseBPM)
    fun isMuted(bar: Int, beat: Int): Boolean = mute?.isMuted(bar, beat) ?: false

    /** 渐进提速进度 0…1；没开提速时返回 null。 */
    fun progress(bar: Int): Double? = ramp?.progress(bar)
    fun isFinished(bar: Int): Boolean = ramp?.isFinished(bar) ?: false
    fun state(bar: Int, beat: Int) = BeatState(bpm(bar), isMuted(bar, beat), isFinished(bar))

    /** 播放到第 bar 小节（含）为止，BPM 的最低和最高值，写练习记录时用。 */
    fun bpmRange(throughBar: Int): IntRange {
        val r = ramp ?: return Tempo.clamp(baseBPM)..Tempo.clamp(baseBPM)
        val a = r.bpm(0)
        val b = r.bpm(min(max(0, throughBar), r.barsToTarget))
        return min(a, b)..max(a, b)
    }
}

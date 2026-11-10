package com.example.tunebeatchord.tuner

import kotlin.math.abs

/** 把检测到的音高对到目标音（某根弦，或半音阶里最近的半音）。 */
data class TuningResult(
    val reading: PitchReading,
    /** 目标音；半音阶模式下就是最近的半音。 */
    val target: Pitch,
    /** 目标是哪根弦（半音阶模式为 null）。 */
    val stringIndex: Int?,
    /** 相对目标音的偏差（音分）。可能远超 ±50（例如手动锁定了别的弦）。 */
    val cents: Double,
    val targetFrequency: Double,
) {
    val isInTune: Boolean get() = abs(cents) <= TunerDefaults.IN_TUNE_CENTS
    val isFlat: Boolean get() = cents < -TunerDefaults.IN_TUNE_CENTS
    val isSharp: Boolean get() = cents > TunerDefaults.IN_TUNE_CENTS
}

/** 离给定频率最近的一根弦（按音分距离，对回弦定弦同样有效）。 */
fun Tuning.closestString(frequency: Double, a4: Double = TunerDefaults.A4): Pair<InstrumentString, Double>? {
    if (frequency <= 0) return null
    var best: Pair<InstrumentString, Double>? = null
    for (s in strings) {
        val c = Pitch.cents(s.pitch.frequency(a4), frequency)
        if (best == null || abs(c) < abs(best.second)) best = s to c
    }
    return best
}

/**
 * 为一次检测结果找目标。
 * @param lockedString 手动锁定的弦；为 null（或越界）时自动选最近的弦。
 */
fun Tuning.match(reading: PitchReading, lockedString: Int? = null): TuningResult {
    val a4 = reading.a4
    if (isChromatic) {
        val p = reading.pitch
        return TuningResult(reading, p, null, reading.cents, p.frequency(a4))
    }
    if (lockedString != null && lockedString in strings.indices) {
        val s = strings[lockedString]
        val f = s.pitch.frequency(a4)
        return TuningResult(reading, s.pitch, s.index, Pitch.cents(f, reading.frequency), f)
    }
    val (s, c) = closestString(reading.frequency, a4)!!
    return TuningResult(reading, s.pitch, s.index, c, s.pitch.frequency(a4))
}

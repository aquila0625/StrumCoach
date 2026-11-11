package com.example.strumcoach.tuner

import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow

/**
 * 对连续的检测结果做平滑，避免指针乱跳。
 *
 * - 在对数频率域做中值滤波 + 指数平滑；
 * - 突然跳到别的音（超过 `jumpCents`）时，要连续 `confirmFrames` 帧都稳定在新音上才接受，单帧误判会被丢弃；
 * - 信号短暂丢失时保持上一次的结果 `holdFrames` 帧，之后才输出 null。
 */
class PitchSmoother {
    var medianCount = 5
    /** 指数平滑系数（0…1，越大跟得越快）。 */
    var alpha = 0.45
    var jumpCents = 70.0
    var confirmFrames = 3
    var holdFrames = 12

    private var history = ArrayList<Double>()   // log2(Hz)
    private var pending = ArrayList<Double>()
    private var current: Double? = null
    private var clarity = 0.0
    private var misses = 0

    fun reset() {
        history.clear(); pending.clear()
        current = null; clarity = 0.0; misses = 0
    }

    val isActive: Boolean get() = current != null

    fun process(raw: RawPitch?, a4: Double): PitchReading? {
        if (raw == null) {
            misses += 1
            if (misses > holdFrames) {
                reset()
                return null
            }
            return reading(a4)
        }
        misses = 0
        val lf = ln(raw.frequency) / ln(2.0)

        val cur = current
        if (cur == null) {
            history = arrayListOf(lf); current = lf; clarity = raw.clarity
            return reading(a4)
        }

        if (abs(lf - cur) * 1200 > jumpCents) {
            // 可能是误判，也可能是真的换了音：先攒着
            val last = pending.lastOrNull()
            if (last != null && abs(lf - last) * 1200 > jumpCents / 2) pending.clear()
            pending.add(lf)
            if (pending.size >= confirmFrames) {
                history = ArrayList(pending); current = median(pending); clarity = raw.clarity
                pending.clear()
            }
            return reading(a4)
        }

        pending.clear()
        history.add(lf)
        while (history.size > medianCount) history.removeAt(0)
        val med = median(history)
        current = cur + alpha * (med - cur)
        clarity += 0.5 * (raw.clarity - clarity)
        return reading(a4)
    }

    private fun reading(a4: Double): PitchReading? =
        current?.let { PitchReading(2.0.pow(it), clarity, a4) }

    private fun median(values: List<Double>): Double = values.sorted()[values.size / 2]
}

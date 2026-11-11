package com.example.strumcoach.audio

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * 调准一根弦时的“叮—咚”提示音：程序合成，不使用任何外部录音。
 * 两个钟琴音（E6 → C6），基频加一个很弱、衰减很快的非谐和泛音和一点低八度的“咚”，4 ms 起音、指数衰减，峰值 0.4，末尾淡出。
 */
object TuneChime {
    const val FIRST_FREQUENCY = 1318.51
    const val SECOND_FREQUENCY = 1046.50
    const val NOTE_GAP = 0.17
    const val DURATION = 0.85

    fun render(sampleRate: Double, peak: Float = 0.4f): FloatArray {
        val n = (DURATION * sampleRate).toInt()
        val out = FloatArray(n)
        addBell(out, sampleRate, 0.0, FIRST_FREQUENCY, 0.85, 6.5)
        addBell(out, sampleRate, NOTE_GAP, SECOND_FREQUENCY, 1.0, 5.0)
        val top = out.maxOf { abs(it) }
        val scale = if (top > 0) peak / top else 0f
        val fade = (0.06 * sampleRate).toInt()
        for (i in 0 until n) {
            var v = out[i] * scale
            if (i >= n - fade) v *= (n - 1 - i).toFloat() / fade
            out[i] = v
        }
        return out
    }

    private fun addBell(out: FloatArray, sr: Double, start: Double, f: Double, gain: Double, decay: Double) {
        val first = (start * sr).toInt()
        val attack = 0.004
        for (i in first until out.size) {
            val t = (i - first) / sr
            val env = min(1.0, t / attack) * exp(-decay * t)
            val body = sin(2 * PI * f * t)
            val sparkle = 0.12 * sin(2 * PI * f * 2.76 * t) * exp(-18 * t)
            val low = 0.18 * sin(2 * PI * f * 0.5 * t) * exp(-9 * t)
            out[i] += (gain * env * (body + sparkle + low)).toFloat()
        }
    }
}

package com.example.tunebeatchord.audio

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * 按乐器发出一个音（参考音、和弦试听共用）。纯计算，没有音频硬件依赖，可以离线渲染测音准。
 * 用内置的真实乐器采样按目标频率重采样；采样库里没有这件乐器时，退回几个泛音按各自速度衰减的简单合成。
 */
object InstrumentTone {
    /** 渲染一个音，峰值约 `amplitude`。 */
    fun render(
        bank: SampleBank?, voice: Voice, frequency: Double, sampleRate: Double,
        duration: Double, amplitude: Float = 0.5f,
    ): FloatArray {
        val n = max(0, (duration * sampleRate).toInt())
        if (n == 0 || frequency <= 10) return FloatArray(n)
        val sample = bank?.sample(voice, frequency)
        val out = if (sample != null) {
            SamplePlayback.render(sample, frequency, sampleRate, duration).also { fadeOut(it, 0.03, sampleRate) }
        } else {
            synthesized(frequency, sampleRate, n, if (voice.isSustained) 8.0 else 3.0)
        }
        normalize(out, amplitude)
        return out
    }

    private fun synthesized(f: Double, sr: Double, n: Int, decaySeconds: Double): FloatArray {
        val partials = listOf(Triple(1.0, 1.0, 1.0), Triple(2.0, 0.55, 1.6), Triple(3.0, 0.30, 2.4), Triple(4.0, 0.18, 3.4), Triple(5.0, 0.10, 4.6))
        val out = FloatArray(n)
        for (i in 0 until n) {
            val t = i / sr
            var v = 0.0
            for ((ratio, level, decay) in partials) if (f * ratio < sr / 2) v += level * exp(-decay * t * 3.0 / decaySeconds) * sin(2 * PI * f * ratio * t)
            out[i] = (v * min(1.0, t / 0.004)).toFloat()
        }
        fadeOut(out, 0.03, sr)
        return out
    }

    private fun fadeOut(x: FloatArray, seconds: Double, sr: Double) {
        val k = min(x.size, (seconds * sr).toInt())
        for (i in 0 until k) x[x.size - 1 - i] *= i.toFloat() / k
    }

    private fun normalize(x: FloatArray, peak: Float) {
        var p = 0f
        for (v in x) p = max(p, abs(v))
        if (p > 0) {
            val g = peak / p
            for (i in x.indices) x[i] *= g
        }
    }
}

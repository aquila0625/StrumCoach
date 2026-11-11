package com.example.strumcoach.metronome

import com.example.strumcoach.rhythm.VoiceLevel
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * 程序合成的点击音：每种音色 × 强 / 次强 / 弱三档，纯计算、没有任何外部录音。
 * 公式和 iOS 版（ClickSynth.swift）一致，所以两个平台听起来相同。
 */
object ClickSynth {
    fun make(sound: SoundKind, level: VoiceLevel, sampleRate: Double): FloatArray = when (sound) {
        SoundKind.WOODBLOCK, SoundKind.CUSTOM -> woodblock(level, sampleRate)   // 还没录时用木鱼
        SoundKind.ELECTRONIC -> electronic(level, sampleRate)
        SoundKind.COWBELL -> cowbell(level, sampleRate)
        SoundKind.TICK -> tick(level, sampleRate)
        SoundKind.BLOCK -> block(level, sampleRate)
        SoundKind.CLAVE -> clave(level, sampleRate)
        SoundKind.CLICK, SoundKind.VOICE -> click(level, sampleRate)
        SoundKind.DIGITAL -> digital(level, sampleRate)
        SoundKind.SONAR -> sonar(level, sampleRate)
        SoundKind.RIMSHOT -> rimshot(level, sampleRate)
        SoundKind.HIHAT -> hihat(level, sampleRate)
        SoundKind.KICK_SNARE -> kickSnare(level, sampleRate)
        SoundKind.SHAKER -> shaker(level, sampleRate)
        SoundKind.MARIMBA -> marimba(level, sampleRate)
        SoundKind.TRIANGLE -> triangle(level, sampleRate)
        SoundKind.BELL -> bell(level, sampleRate)
    }

    private fun pick(level: VoiceLevel, a: Double, b: Double, c: Double) = when (level) {
        VoiceLevel.STRONG -> a
        VoiceLevel.MEDIUM -> b
        VoiceLevel.WEAK -> c
    }

    private const val TAU = 2 * PI

    private fun woodblock(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 1650.0, 1320.0, 1050.0)
        val noise = Noise()
        return render(0.12, sr) { t ->
            val body = sin(TAU * f * t) * exp(-t / 0.018)
            val overtone = 0.35 * sin(TAU * f * 2.76 * t) * exp(-t / 0.007)
            val knock = 0.25 * noise.next() * exp(-t / 0.0015)
            body + overtone + knock
        }
    }

    private fun electronic(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 2093.0, 1760.0, 1319.0)
        return render(0.07, sr) { t ->
            val wave = sin(TAU * f * t) + 0.25 * sin(TAU * 3 * f * t)
            val release = if (t > 0.055) max(0.0, 1 - (t - 0.055) / 0.015) else 1.0
            wave * exp(-t / 0.03) * release
        }
    }

    private fun cowbell(level: VoiceLevel, sr: Double): FloatArray {
        val pitch = pick(level, 1.12, 1.0, 0.89)
        val f1 = 587 * pitch
        val f2 = 845 * pitch
        return render(0.3, sr) { t ->
            val env = 0.65 * exp(-t / 0.012) + 0.35 * exp(-t / 0.09)
            (square(f1, t, sr) + square(f2, t, sr)) * env
        }
    }

    private fun tick(level: VoiceLevel, sr: Double): FloatArray {
        val p = pick(level, 1.0, 0.9, 0.82)
        val noise = Noise(0x2468_ACE0)
        return render(0.06, sr) { t ->
            val hit = noise.next() * exp(-t / 0.0007)
            val ring = 0.6 * sin(TAU * 3300 * p * t) * exp(-t / 0.006) + 0.4 * sin(TAU * 4870 * p * t) * exp(-t / 0.004)
            val tock = if (level == VoiceLevel.STRONG) 0.5 * sin(TAU * 1250 * t) * exp(-t / 0.012) else 0.0
            hit + ring + tock
        }
    }

    private fun block(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 1180.0, 990.0, 860.0)
        val noise = Noise(0x1357_9BDF)
        return render(0.1, sr) { t ->
            val body = sin(TAU * f * t) * exp(-t / 0.022)
            val second = 0.45 * sin(TAU * f * 1.58 * t) * exp(-t / 0.012)
            val knock = 0.3 * noise.next() * exp(-t / 0.001)
            body + second + knock
        }
    }

    private fun clave(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 2650.0, 2450.0, 2250.0)
        return render(0.08, sr) { t -> sin(TAU * f * (t - 0.6 * t * t)) * exp(-t / 0.016) }
    }

    private fun click(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 5200.0, 4300.0, 3500.0)
        val noise = Noise(0x0F0F_1234)
        return render(0.03, sr) { t -> sin(TAU * f * t) * exp(-t / 0.0012) + 0.3 * noise.next() * exp(-t / 0.0004) }
    }

    private fun digital(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 1200.0, 1000.0, 800.0)
        return render(0.06, sr) { t ->
            val gate = if (t < 0.04) 1.0 else max(0.0, 1 - (t - 0.04) / 0.012)
            square(f, t, sr) * gate
        }
    }

    private fun sonar(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 988.0, 784.0, 659.0)
        return render(0.25, sr) { t ->
            val attack = min(1.0, t / 0.004)
            (sin(TAU * f * t) + 0.15 * sin(TAU * 2 * f * t)) * attack * exp(-t / 0.06)
        }
    }

    private fun rimshot(level: VoiceLevel, sr: Double): FloatArray {
        val p = pick(level, 1.1, 1.0, 0.9)
        val noise = Noise(0x5555_AAAA)
        return render(0.12, sr) { t ->
            val crack = noise.next() * exp(-t / 0.003)
            val body = 0.7 * sin(TAU * 470 * p * t) * exp(-t / 0.02)
            val ring = 0.35 * sin(TAU * 1750 * p * t) * exp(-t / 0.012)
            crack + body + ring
        }
    }

    private fun hihat(level: VoiceLevel, sr: Double): FloatArray {
        val decay = pick(level, 0.09, 0.05, 0.03)
        val freqs = listOf(205.3, 304.4, 369.6, 522.7, 540.0, 800.0).map { it * 3.3 }
        var previous = 0.0
        return render(0.25, sr) { t ->
            var metal = 0.0
            for (f in freqs) metal += if (sin(TAU * f * t) >= 0) 1 else -1
            val high = metal - previous
            previous = metal
            high * exp(-t / decay)
        }
    }

    private fun kickSnare(level: VoiceLevel, sr: Double): FloatArray {
        if (level == VoiceLevel.STRONG) {
            // 频率从 160 Hz 指数下滑到 50 Hz，相位是频率的积分
            return render(0.3, sr) { t ->
                val phase = TAU * (50 * t + 110 * 0.03 * (1 - exp(-t / 0.03)))
                sin(phase) * exp(-t / 0.12) + 0.3 * sin(TAU * 1000 * t) * exp(-t / 0.002)
            }
        }
        val decay = if (level == VoiceLevel.MEDIUM) 0.09 else 0.05
        val noise = Noise(0x7777_1111)
        return render(0.2, sr) { t ->
            val snares = noise.next() * exp(-t / decay)
            val body = 0.6 * sin(TAU * 190 * t) * exp(-t / 0.04)
            snares + body
        }
    }

    private fun shaker(level: VoiceLevel, sr: Double): FloatArray {
        val decay = pick(level, 0.045, 0.035, 0.025)
        val noise = Noise(0x3141_5926)
        var previous = 0.0
        return render(0.15, sr) { t ->
            val n = noise.next()
            val high = n - previous
            previous = n
            high * min(1.0, t / 0.006) * exp(-t / decay)
        }
    }

    private fun marimba(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 1046.5, 784.0, 659.3)
        return render(0.35, sr) { t -> sin(TAU * f * t) * exp(-t / 0.09) + 0.25 * sin(TAU * 3.93 * f * t) * exp(-t / 0.015) }
    }

    private fun triangle(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 3150.0, 2900.0, 2650.0)
        return render(0.6, sr) { t ->
            (sin(TAU * f * t) + 0.6 * sin(TAU * 2.76 * f * t) + 0.4 * sin(TAU * 5.40 * f * t)) * exp(-t / 0.16)
        }
    }

    private fun bell(level: VoiceLevel, sr: Double): FloatArray {
        val f = pick(level, 1318.5, 1108.7, 987.8)
        val partials = listOf(Triple(1.0, 1.0, 0.14), Triple(2.0, 0.6, 0.1), Triple(2.4, 0.4, 0.08), Triple(3.0, 0.3, 0.06), Triple(4.07, 0.2, 0.04))
        return render(0.5, sr) { t ->
            var s = 0.0
            for ((ratio, amp, decay) in partials) if (ratio * f < sr / 2) s += amp * sin(TAU * ratio * f * t) * exp(-t / decay)
            s
        }
    }

    /** 带谐波的方波（奇次谐波叠加，避免超过奈奎斯特频率）。 */
    private fun square(f: Double, t: Double, sr: Double): Double {
        var s = 0.0
        var k = 1
        while (k <= 9) {
            if (k * f < sr / 2) s += sin(TAU * k * f * t) / k
            k += 2
        }
        return s
    }

    /** 渲染一段：0.3 毫秒淡入、2 毫秒淡出，峰值归一到 0.95。 */
    private fun render(seconds: Double, sr: Double, f: (Double) -> Double): FloatArray {
        val n = (seconds * sr).toInt()
        val attack = max(1, (0.0003 * sr).toInt())
        val release = max(1, (0.002 * sr).toInt())
        val out = FloatArray(n)
        var peak = 0f
        for (i in 0 until n) {
            val t = i / sr
            var v = f(t)
            if (i < attack) v *= (i + 1).toDouble() / attack
            if (i >= n - release) v *= (n - i).toDouble() / release
            out[i] = v.toFloat()
            peak = max(peak, abs(out[i]))
        }
        if (peak > 0) {
            val scale = 0.95f / peak
            for (i in 0 until n) out[i] *= scale
        }
        return out
    }

    /** 固定种子的噪声（线性同余），每次合成结果相同。 */
    private class Noise(var state: Int = 0x1234_5678) {
        fun next(): Double {
            state = state * 1_664_525 + 1_013_904_223
            return (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
        }
    }
}

/** 预先合成好的全部点击音（按采样率），音频线程只读。 */
class VoiceBank(val sampleRate: Double) {
    private val buffers: Array<FloatArray> = Array(SoundKind.entries.size * 3) { i ->
        ClickSynth.make(SoundKind.entries[i / 3], VoiceLevel.entries[i % 3], sampleRate)
    }

    fun buffer(sound: SoundKind, level: VoiceLevel): FloatArray = buffers[sound.ordinal * 3 + level.ordinal]
}

package com.example.strumcoach.tuner

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** 测试用的合成信号。 */
object Signal {
    enum class Shape { SINE, SAWTOOTH, HARMONICS }

    fun make(
        shape: Shape, frequency: Double, sampleRate: Double = 44100.0,
        count: Int = 4096, amplitude: Float = 0.5f, phase: Double = 0.0,
    ): FloatArray = FloatArray(count) { i ->
        val ph = frequency * (i / sampleRate) + phase
        when (shape) {
            Shape.SINE -> amplitude * sin(2 * PI * ph).toFloat()
            Shape.SAWTOOTH -> amplitude * (2 * (ph - floor(ph)) - 1).toFloat()
            Shape.HARMONICS -> {
                // 基频很弱、二三次泛音更强的“吉他式”音色
                var v = 0.0
                for ((h, a) in listOf(1 to 0.35, 2 to 1.0, 3 to 0.8, 4 to 0.5, 5 to 0.3)) v += a * sin(2 * PI * h * ph)
                amplitude * (v / 2.2).toFloat()
            }
        }
    }

    /** 加高斯白噪声，snrDB 为信噪比（按功率）。固定种子，结果可复现。 */
    fun addNoise(x: FloatArray, snrDB: Double, seed: ULong = 42u): FloatArray {
        val rng = SplitMix64(seed)
        val power = x.sumOf { it.toDouble() * it } / x.size
        val sigma = sqrt(power / 10.0.pow(snrDB / 10))
        return FloatArray(x.size) { i ->
            val u1 = maxOf(rng.nextUnit(), 1e-12)
            val u2 = rng.nextUnit()
            val g = sqrt(-2 * ln(u1)) * cos(2 * PI * u2)
            x[i] + (sigma * g).toFloat()
        }
    }
}

class SplitMix64(seed: ULong) {
    private var state = seed
    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    fun nextUnit(): Double = (next() shr 11).toDouble() / (1L shl 53).toDouble()
}

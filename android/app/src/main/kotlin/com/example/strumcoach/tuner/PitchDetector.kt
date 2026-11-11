package com.example.strumcoach.tuner

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** 检测器的原始输出（未平滑）。 */
data class RawPitch(val frequency: Double, val clarity: Double)

/**
 * McLeod 音高检测（MPM）：归一化平方差函数 + 峰值挑选 + 抛物线插值。
 *
 * 对富含泛音的信号（吉他、提琴）比朴素自相关更不容易出现八度误判。
 * 实例带有复用的缓冲区，**不是线程安全的**：每个线程用自己的实例。
 */
class PitchDetector(var configuration: Configuration = Configuration()) {
    class Configuration {
        /** 能识别的最低频率（5 弦贝斯最低音 B0 ≈ 30.9 Hz，再留出调低的余量）。 */
        var minFrequency = 27.0

        /** 能识别的最高频率。 */
        var maxFrequency = 2100.0

        /** 低于这个 RMS（满量程为 1）视为静音，不输出音高。 */
        var silenceRMS = 0.003f

        /** MPM 的峰值阈值 k：选第一个不低于 k × 最高峰的峰。 */
        var peakThreshold = 0.9

        /** 最高峰低于这个值就不算有音高（噪声、杂音）。 */
        var minClarity = 0.8
    }

    private var nsdf = FloatArray(0)
    private var prefix = DoubleArray(0)

    fun detect(x: FloatArray, sampleRate: Double, count: Int = x.size): RawPitch? {
        val n = count
        if (n < 64 || sampleRate <= 0) return null
        val cfg = configuration

        // 静音门限
        var sumSq = 0.0
        for (i in 0 until n) sumSq += x[i].toDouble() * x[i]
        val rms = sqrt(sumSq / n).toFloat()
        if (rms < cfg.silenceRMS) return null

        val minLag = max(2, (sampleRate / cfg.maxFrequency).toInt())
        val maxLag = min((sampleRate / cfg.minFrequency).toInt(), n / 2)
        if (maxLag <= minLag + 2) return null

        // x² 的前缀和，用来 O(1) 得到每个 lag 的能量项 m(τ)
        if (prefix.size != n + 1) prefix = DoubleArray(n + 1)
        var acc = 0.0
        prefix[0] = 0.0
        for (i in 0 until n) {
            val v = x[i].toDouble()
            acc += v * v
            prefix[i + 1] = acc
        }

        // NSDF(τ) = 2·r(τ) / m(τ)，r 为自相关，m 为两段能量之和
        if (nsdf.size != maxLag + 2) nsdf = FloatArray(maxLag + 2)
        for (tau in 1..maxLag + 1) {
            val len = n - tau
            var r = 0f
            for (i in 0 until len) r += x[i] * x[i + tau]
            val m = prefix[len] + (prefix[n] - prefix[tau])
            nsdf[tau] = if (m > 1e-12) (2 * r.toDouble() / m).toFloat() else 0f
        }

        // 跳过起始的正值主瓣，找到第一次下穿 0 的位置
        var tau = 1
        while (tau <= maxLag && nsdf[tau] > 0) tau++
        if (tau > maxLag) return null

        // 每个“正值区间”取一个峰
        val peakLags = ArrayList<Int>()
        val peakValues = ArrayList<Float>()
        var bestValue = 0f
        while (tau <= maxLag) {
            while (tau <= maxLag && nsdf[tau] <= 0) tau++
            if (tau > maxLag) break
            var peakLag = tau
            var peakValue = nsdf[tau]
            while (tau <= maxLag && nsdf[tau] > 0) {
                if (nsdf[tau] > peakValue) {
                    peakValue = nsdf[tau]; peakLag = tau
                }
                tau++
            }
            if (peakLag in minLag..maxLag) {
                peakLags.add(peakLag); peakValues.add(peakValue)
                bestValue = max(bestValue, peakValue)
            }
        }
        if (bestValue <= 0) return null

        val limit = cfg.peakThreshold.toFloat() * bestValue
        val chosen = peakValues.indexOfFirst { it >= limit }
        if (chosen < 0) return null

        // 抛物线插值求亚采样精度的周期
        val k = peakLags[chosen]
        val a = nsdf[k - 1]
        val b = nsdf[k]
        val c = nsdf[k + 1]
        val denom = a - 2 * b + c
        var shift = 0f
        var value = b
        if (abs(denom) > 1e-12) {
            shift = 0.5f * (a - c) / denom
            if (abs(shift) > 1) shift = 0f
            value = b - 0.25f * (a - c) * shift
        }
        val clarity = min(max(value, 0f), 1f).toDouble()
        if (clarity < cfg.minClarity) return null

        val period = k.toDouble() + shift.toDouble()
        return RawPitch(sampleRate / period, clarity)
    }

    companion object {
        /** 建议的分析窗口长度：至少覆盖最低频率的两个周期。 */
        fun recommendedFrameLength(sampleRate: Double, minFrequency: Double = Configuration().minFrequency): Int =
            ceil(2.1 * sampleRate / minFrequency).toInt()
    }
}

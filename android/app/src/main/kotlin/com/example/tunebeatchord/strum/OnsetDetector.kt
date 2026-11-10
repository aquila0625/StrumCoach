package com.example.tunebeatchord.strum

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln1p
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 扫弦起音检测（收音结束后对整段录音做，不在音频线程里跑）。
 *
 * 1. 频谱通量：1024 点 FFT、每 256 个采样一帧，取对数幅度谱里“比上一帧变大的部分”之和；
 * 2. 自适应阈值：前后各 0.25 秒内通量的中位数 × 1.5，再加上整段最大通量的 8%（压住持续的底噪和余音）；
 * 3. 峰值：超过阈值、是前后各 3 帧里最大的；两个起音至少隔 70 毫秒；
 * 4. 精确定位：在峰值附近按约 1.3 毫秒一块算高通（一阶差分）后的能量，取第一块“明显比前面响”的位置，也就是扫弦第一根弦的起音。
 *
 * 根音单拨（节奏型里的 `B`）只有一根弦，比扫弦轻得多：在“该拨根音”的时间附近（`sensitive`）用更低的阈值，
 * 能检测到起音就算；其他位置照旧，杂音不会因此被当成起音。
 */
class OnsetDetector(val sampleRate: Double) {
    var frameSize = 1024
    var hop = 256
    var minInterval = 0.070
    var thresholdRatio = 1.5f
    var thresholdFloor = 0.08f
    /** 根音单拨附近：阈值倍数、整段最大通量的比例放低。 */
    var sensitiveRatio = 1.2f
    var sensitiveFloor = 0.025f

    /** 返回起音所在的采样位置（从 0 起），按时间先后。`sensitive`：这些采样范围里（根音单拨附近）用更低的阈值。 */
    fun detect(samples: FloatArray, sensitive: List<IntRange> = emptyList()): List<Int> {
        val flux = spectralFlux(samples)
        if (flux.size <= 8) return emptyList()
        val maxFlux = flux.max()
        if (maxFlux <= 0f) return emptyList()
        val half = max(1, (0.25 * sampleRate).toInt() / hop)
        val minGap = (minInterval * sampleRate).toInt()
        val onsets = ArrayList<Int>()
        for (t in 1 until flux.size) {
            val center = t * hop + frameSize / 2
            val soft = sensitive.any { center in it }
            val lo = max(0, t - half)
            val hi = min(flux.size, t + half + 1)
            val threshold = median(flux, lo, hi) * (if (soft) sensitiveRatio else thresholdRatio) + (if (soft) sensitiveFloor else thresholdFloor) * maxFlux
            if (flux[t] <= threshold) continue
            val nlo = max(0, t - 3)
            val nhi = min(flux.size, t + 4)
            var localMax = flux[nlo]
            for (i in nlo until nhi) localMax = max(localMax, flux[i])
            if (flux[t] != localMax) continue
            val onset = refine(samples, t)
            if (onsets.isNotEmpty() && onset - onsets.last() < minGap) continue
            onsets.add(onset)
        }
        return onsets
    }

    // 频谱通量 -------------------------------------------------------------

    private val window by lazy { FloatArray(frameSize) { (0.5 * (1 - cos(2 * PI * it / frameSize))).toFloat() } }

    fun spectralFlux(samples: FloatArray): FloatArray {
        if (samples.size < frameSize) return FloatArray(0)
        val bins = frameSize / 2
        val previous = FloatArray(bins)
        val flux = ArrayList<Float>()
        val re = FloatArray(frameSize)
        val im = FloatArray(frameSize)
        var start = 0
        while (start + frameSize <= samples.size) {
            for (i in 0 until frameSize) {
                re[i] = samples[start + i] * window[i]; im[i] = 0f
            }
            fft(re, im)
            var sum = 0f
            for (k in 1 until bins) {
                // 乘 2：和 iOS 版用的 vDSP 实数 FFT 的幅度刻度一致
                val mag = 2 * sqrt(re[k] * re[k] + im[k] * im[k])
                val m = ln1p(mag * 10)
                val d = m - previous[k]
                if (d > 0) sum += d
                previous[k] = m
            }
            flux.add(if (start == 0) 0f else sum)
            start += hop
        }
        return flux.toFloatArray()
    }

    private val cosTable by lazy { FloatArray(frameSize / 2) { cos(2 * PI * it / frameSize).toFloat() } }
    private val sinTable by lazy { FloatArray(frameSize / 2) { (-sin(2 * PI * it / frameSize)).toFloat() } }

    /** 原地的基 2 FFT（长度必须是 2 的幂）。 */
    private fun fft(re: FloatArray, im: FloatArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit; bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var len = 2
        while (len <= n) {
            val step = n / len
            var i = 0
            while (i < n) {
                for (k in 0 until len / 2) {
                    val wr = cosTable[k * step]
                    val wi = sinTable[k * step]
                    val a = i + k
                    val b = a + len / 2
                    val xr = re[b] * wr - im[b] * wi
                    val xi = re[b] * wi + im[b] * wr
                    re[b] = re[a] - xr; im[b] = im[a] - xi
                    re[a] += xr; im[a] += xi
                }
                i += len
            }
            len = len shl 1
        }
    }

    // 定位 -----------------------------------------------------------------

    /** 第 t 帧的通量最大；起音在这一帧窗口里。按小块能量找第一块“比前面明显响”的位置。 */
    fun refine(samples: FloatArray, frame: Int): Int {
        val block = max(16, (sampleRate * 0.0013).toInt())
        val regionStart = max(0, frame * hop - frameSize / 2)
        val regionEnd = min(samples.size, frame * hop + frameSize)
        val energies = ArrayList<Float>()
        var s = regionStart
        // 用一阶差分（高通）算能量：拨弦的起音是宽频的，前一下还在响的余音主要是低频，差分后压下去
        while (s + block <= regionEnd) {
            var e = 0f
            for (i in max(1, s) until s + block) {
                val d = samples[i] - samples[i - 1]
                e += d * d
            }
            energies.add(e)
            s += block
        }
        val peak = energies.maxOrNull() ?: 0f
        if (peak <= 0f) return frame * hop + frameSize / 2
        for ((b, e) in energies.withIndex()) {
            if (e < 0.3f * peak) continue
            var before = Float.MAX_VALUE
            for (i in max(0, b - 8) until b) before = min(before, energies[i])
            if (b == 0) before = 0f
            if (b == 0 || e > 3 * before + 1e-9f) return regionStart + b * block
        }
        return frame * hop + frameSize / 2
    }

    private fun median(values: FloatArray, from: Int, to: Int): Float {
        val copy = values.copyOfRange(from, to)
        copy.sort()
        return copy[copy.size / 2]
    }
}

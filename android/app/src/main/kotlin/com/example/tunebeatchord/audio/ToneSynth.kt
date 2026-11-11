package com.example.tunebeatchord.audio

import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/** 参考音的音色。 */
enum class ToneTimbre {
    /** 纯正弦，最容易听出拍音。 */
    SINE,
    /** 简单的拨弦合成：几个泛音按各自速度衰减，每隔一会儿重新拨一次，形成持续的“嗡”。 */
    PLUCK,
    /** 当前所选乐器的声音（真实采样）。 */
    INSTRUMENT,
}

/**
 * 参考音的合成核心：纯计算，没有音频硬件依赖，便于测试。`render` 在音频线程调用。
 * 淡入淡出 10 ms / 80 ms 避免爆音；采样音色里拨弦类拨一次就自然衰减完（和 iOS 一样），拉弦类在循环区间里一直拉；
 * 合成的“拨弦”音色按 `pluckInterval` 重新拨。
 */
class ToneSynth(private val outputRate: Double) {
    var frequency = 440.0
    var timbre = ToneTimbre.SINE
    var amplitude = 0.3f
    var pluckInterval = 2.4

    private var sample: SampleBuffer? = null
    private var playback: SamplePlayback? = null
    private var phase = 0.0
    private var gain = 0f
    private var target = 0f
    private var sincePluck = 0.0

    val isSounding: Boolean get() = target > 0 || gain > 0.0001f
    val hasSampler: Boolean get() = sample != null

    fun start() {
        if (target == 0f) {
            sincePluck = 0.0
            playback = sample?.let { SamplePlayback(it, frequency, outputRate) }
        }
        target = 1f
    }

    fun stop() {
        target = 0f
    }

    /** 换成真实采样（之后调 start）。 */
    fun load(sample: SampleBuffer?) {
        this.sample = sample
        playback = sample?.let { SamplePlayback(it, frequency, outputRate) }
    }

    /** 改变正在发声的采样的频率，不重新开始。 */
    fun retune(frequency: Double) {
        this.frequency = frequency
        playback?.retune(frequency)
    }

    private val scratch = FloatArray(4096)

    fun render(out: FloatArray, count: Int) {
        val fadeIn = (1 / (0.01 * outputRate)).toFloat()
        val fadeOut = (1 / (0.08 * outputRate)).toFloat()
        val sampler = sample
        if (timbre == ToneTimbre.INSTRUMENT && sampler != null) {
            var done = 0
            while (done < count) {
                val n = min(scratch.size, count - done)
                var pb = playback
                if (pb == null) { pb = SamplePlayback(sampler, frequency, outputRate); playback = pb }
                // 拨弦类（吉他、贝斯、尤克里里、钢琴）和 iOS 一样只拨一次、让它自然衰减完；中途重拨会截断余音、带出咔哒声，
                // 听起来不像真琴。播完就停（界面上的按钮随之复位）。拉弦类的循环采样一直拉，不会结束。
                if (pb.isFinished) {
                    target = 0f; gain = 0f
                    for (i in 0 until count - done) out[done + i] = 0f
                    return
                }
                pb.render(scratch, n)
                for (i in 0 until n) {
                    if (gain < target) gain = min(target, gain + fadeIn) else if (gain > target) gain = maxOf(target, gain - fadeOut)
                    out[done + i] = scratch[i] * gain * amplitude * SAMPLE_GAIN_PER_AMPLITUDE
                }
                done += n
            }
            return
        }
        val dt = 1 / outputRate
        val step = frequency / outputRate
        val fade = (1 / (0.01 * outputRate)).toFloat()
        for (i in 0 until count) {
            if (gain < target) gain = min(target, gain + fade) else if (gain > target) gain = maxOf(target, gain - fade)
            var v: Double
            if (timbre == ToneTimbre.PLUCK) {
                if (sincePluck >= pluckInterval) sincePluck -= pluckInterval
                val t = sincePluck
                v = 0.0
                for ((ratio, level, decay) in PARTIALS) if (frequency * ratio < outputRate / 2) v += level * exp(-decay * t) * sin(2 * PI * phase * ratio)
                v *= min(1.0, t / 0.004) * 0.6
                sincePluck += dt
            } else {
                v = sin(2 * PI * phase)
            }
            out[i] = v.toFloat() * amplitude * gain
            phase += step
            if (phase >= 1) phase -= 1
        }
        if (timbre == ToneTimbre.SINE) sincePluck = 0.0
    }

    private companion object {
        /** 采样路径的整体增益：默认 amplitude（0.3）对应 0.9。 */
        const val SAMPLE_GAIN_PER_AMPLITUDE = 3f
        val PARTIALS = listOf(Triple(1.0, 1.0, 1.1), Triple(2.0, 0.55, 1.8), Triple(3.0, 0.30, 2.6), Triple(4.0, 0.18, 3.6), Triple(5.0, 0.10, 5.0), Triple(6.0, 0.06, 6.5))
    }
}

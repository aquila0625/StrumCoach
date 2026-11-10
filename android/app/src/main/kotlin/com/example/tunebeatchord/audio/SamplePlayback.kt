package com.example.tunebeatchord.audio

/** 一段解码好的乐器采样（单声道）。 */
class SampleBuffer(
    val voice: Voice,
    val midi: Int,
    /** 这段采样里弹的音实际的基频（真人演奏不是标准平均律，所以不等于 midi 对应的频率）。 */
    val rootFrequency: Double,
    val sampleRate: Double,
    val data: FloatArray,
    /** 拉弦采样的循环区间 [start, end)；拨弦采样为 null（只播一遍，自然衰减）。 */
    val loopStart: Int? = null,
    val loopEnd: Int? = null,
) {
    val duration: Double get() = data.size / sampleRate
}

/** 声音的种类：和乐器一一对应（“自动”半音阶用钢琴）。 */
enum class Voice(val id: String) {
    PIANO("piano"), GUITAR("guitar"), UKULELE("ukulele"), BASS("bass"), VIOLIN("violin"), VIOLA("viola"), CELLO("cello");

    /** 拨弦 / 击弦类会自然衰减，需要定时重新触发；弓弦类可以一直拉。 */
    val isSustained: Boolean get() = this == VIOLIN || this == VIOLA || this == CELLO

    companion object {
        fun fromFamily(family: com.example.tunebeatchord.tuner.InstrumentFamily) = when (family) {
            com.example.tunebeatchord.tuner.InstrumentFamily.CHROMATIC -> PIANO
            com.example.tunebeatchord.tuner.InstrumentFamily.GUITAR -> GUITAR
            com.example.tunebeatchord.tuner.InstrumentFamily.UKULELE -> UKULELE
            com.example.tunebeatchord.tuner.InstrumentFamily.BASS -> BASS
            com.example.tunebeatchord.tuner.InstrumentFamily.VIOLIN -> VIOLIN
            com.example.tunebeatchord.tuner.InstrumentFamily.VIOLA -> VIOLA
            com.example.tunebeatchord.tuner.InstrumentFamily.CELLO -> CELLO
        }
    }
}

/**
 * 用一段采样发出任意音高的声音：按 目标频率 ÷ 采样基频 的比例做四点 Hermite 插值重采样。
 * 拉弦采样在循环区间里无缝循环（位置按小数累加）；拨弦采样播完就结束。
 * 纯计算、没有音频硬件依赖，可以在渲染线程里用，也可以离线渲染测音准。
 */
class SamplePlayback(sample: SampleBuffer, frequency: Double, private val outputRate: Double) {
    private val data = sample.data
    private val sourceRate = sample.sampleRate
    private val root = sample.rootFrequency
    private val loopStart = sample.loopStart ?: 0
    private val loopEnd = sample.loopEnd ?: 0           // 0 表示不循环
    private var step = frequency / sample.rootFrequency * sample.sampleRate / outputRate
    private var position = 0.0

    var isFinished = false
        private set
    val isLooping: Boolean get() = loopEnd > 0

    /** 在发声过程中改变目标频率（比如调整标准音 A4）；播放位置不动，所以不会有断点。 */
    fun retune(frequency: Double) {
        step = frequency / root * sourceRate / outputRate
    }

    private fun at(index: Int): Float {
        var i = index
        if (loopEnd > 0 && i >= loopEnd) i = loopStart + (i - loopStart) % (loopEnd - loopStart)
        if (i < 0) return data[0]
        if (i >= data.size) return 0f
        return data[i]
    }

    /** 写出 `count` 个采样（覆盖 `out` 的前 count 个）；播完后补零。 */
    fun render(out: FloatArray, count: Int, offset: Int = 0) {
        val n = data.size
        if (n <= 3 || isFinished) {
            for (i in 0 until count) out[offset + i] = 0f
            return
        }
        val loopLength = loopEnd - loopStart
        for (k in 0 until count) {
            if (isFinished) {
                out[offset + k] = 0f; continue
            }
            val i = position.toInt()
            val t = (position - i).toFloat()
            val y0 = at(i - 1); val y1 = at(i); val y2 = at(i + 1); val y3 = at(i + 2)
            val c1 = 0.5f * (y2 - y0)
            val c2 = y0 - 2.5f * y1 + 2 * y2 - 0.5f * y3
            val c3 = 0.5f * (y3 - y0) + 1.5f * (y1 - y2)
            out[offset + k] = ((c3 * t + c2) * t + c1) * t + y1
            position += step
            if (loopEnd > 0) {
                if (position >= loopEnd) position -= loopLength
            } else if (position >= n - 2) isFinished = true
        }
    }

    companion object {
        /** 离线渲染 `duration` 秒。 */
        fun render(sample: SampleBuffer, frequency: Double, sampleRate: Double, duration: Double): FloatArray {
            val count = maxOf(0, (duration * sampleRate).toInt())
            val out = FloatArray(count)
            if (count > 0) SamplePlayback(sample, frequency, sampleRate).render(out, count)
            return out
        }
    }
}

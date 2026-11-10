package com.example.tunebeatchord.strum

import com.example.tunebeatchord.chord.StrumCell
import kotlin.math.max

/** 录音的一个缓冲，连同它被麦克风收到的时刻（秒，`System.nanoTime` 的时间基）。 */
class StrumCaptureChunk(val time: Double, val samples: FloatArray)

/**
 * 一段录音：每个缓冲连同自己的时间一起存下，结束后整段做起音检测，再按起音所在缓冲的时间换算回时钟（不累积误差）。
 */
class StrumCapture(val chunks: List<StrumCaptureChunk>, val sampleRate: Double) {
    /** 起音的时间（秒）。`sensitive`：根音单拨附近的时间段（同一个时钟），这些地方放低检测门槛。 */
    fun onsetTimes(sensitive: List<ClosedFloatingPointRange<Double>> = emptyList()): List<Double> {
        if (chunks.isEmpty()) return emptyList()
        var total = 0
        val starts = IntArray(chunks.size)
        for ((i, c) in chunks.withIndex()) {
            starts[i] = total; total += c.samples.size
        }
        val all = FloatArray(total)
        for ((i, c) in chunks.withIndex()) System.arraycopy(c.samples, 0, all, starts[i], c.samples.size)

        fun index(t: Double): Int {
            var k = 0
            while (k + 1 < chunks.size && chunks[k + 1].time <= t) k++
            return starts[k] + max(0, ((t - chunks[k].time) * sampleRate).toInt())
        }
        val ranges = sensitive.map { index(it.start)..max(index(it.start), index(it.endInclusive)) }
        return OnsetDetector(sampleRate).detect(all, ranges).map { i ->
            var k = 0
            while (k + 1 < starts.size && starts[k + 1] <= i) k++
            chunks[k].time + (i - starts[k]) / sampleRate
        }
    }
}

object StrumTrainerLogic {
    /** 根音单拨（B）附近 ±120 ms 的时间段，换算到录音的时钟（录到的声音比实际晚 `delay` 秒）。 */
    fun bassWindows(tl: StrumTimeline, delay: Double): List<ClosedFloatingPointRange<Double>> =
        tl.strokes.filter { it.stroke == StrumCell.BASS }.map { (it.time + delay - StrumScore.OFF_WINDOW)..(it.time + delay + StrumScore.OFF_WINDOW) }
}

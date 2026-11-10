package com.example.tunebeatchord.strum

import com.example.tunebeatchord.chord.StrumCell
import com.example.tunebeatchord.chord.StrumRhythm
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.sin

class OnsetDetectorTest {
    private val sr = 48_000.0

    /** 一根弦：基频加泛音，指数衰减，开头一小撮拨弦的噪声。 */
    private fun pluck(f: Double, tail: Double, amplitude: Float, rng: java.util.Random): FloatArray {
        val n = (tail * sr).toInt()
        val fade = (0.05 * sr).toInt()
        return FloatArray(n) { i ->
            val t = i / sr
            var v = 0.0
            for (h in 1..5) v += sin(2 * PI * f * h * t) * exp(-t / (0.12 / h)) / h
            v += (rng.nextDouble() * 2 - 1) * exp(-t / 0.002) * 0.3
            // 末尾淡出：真实的弦是自然衰减到几乎听不见，不会在还响着的时候被截断
            val tailGain = if (i >= n - fade) (n - 1 - i).toDouble() / fade else 1.0
            (v * amplitude * 0.5 * tailGain).toFloat()
        }
    }

    private fun strum(freqs: List<Double>, gap: Double, tail: Double, amplitude: Float, rng: java.util.Random): FloatArray {
        val n = ((tail + gap * freqs.size) * sr).toInt()
        val out = FloatArray(n)
        for ((k, f) in freqs.withIndex()) {
            val clip = pluck(f, tail, amplitude, rng)
            val start = (k * gap * sr).toInt()
            for (i in clip.indices) if (start + i < n) out[start + i] += clip[i]
        }
        return out
    }

    /** 合成一段扫弦录音：每个该扫的格放一下，加上持续的底噪和几下很小的杂音。 */
    private fun synthesize(tl: StrumTimeline, noise: Float = 0.002f, clicks: List<Double> = emptyList(), loud: Float = 0.6f, bassLevel: Float = 0.35f): FloatArray {
        val rng = java.util.Random(42)
        val total = ((tl.end + 1) * sr).toInt()
        val audio = FloatArray(total)
        val c = listOf(130.81, 164.81, 196.0, 261.63, 329.63)
        for (s in tl.strokes) {
            val start = (s.time * sr).toInt()
            val clip = when (s.stroke) {
                StrumCell.DOWN -> strum(c, 0.010, 0.6, loud, rng)
                StrumCell.UP -> strum(c.reversed().take(4), 0.010, 0.5, loud * 0.7f, rng)
                StrumCell.DOWN_TREBLE -> strum(c.takeLast(4), 0.010, 0.5, loud * 0.75f, rng)
                StrumCell.BASS -> strum(listOf(c[0]), 0.0, 0.6, loud * bassLevel, rng)
                StrumCell.MUTE -> FloatArray((0.03 * sr).toInt()) { i -> (rng.nextDouble() * 2 - 1).toFloat() * loud * 0.6f * exp(-i / (0.008 * sr)).toFloat() }
                StrumCell.REST -> FloatArray(0)
            }
            for (i in clip.indices) if (start + i < total) audio[start + i] += clip[i]
        }
        for (t in clicks) {
            val start = (t * sr).toInt()
            for (i in 0 until (0.004 * sr).toInt()) if (start + i < total) audio[start + i] += (rng.nextDouble() * 2 - 1).toFloat() * 0.004f
        }
        for (i in 0 until total) audio[i] += (rng.nextDouble() * 2 - 1).toFloat() * noise
        return audio
    }

    private fun check(id: String, bpm: Double) {
        val tl = StrumTimeline(StrumRhythm.preset(id)!!, bpm, 0.5, 2)
        val noise = tl.strokes.dropLast(1).map { it.time + tl.stepDuration / 2 }
        val onsets = OnsetDetector(sr).detect(synthesize(tl, clicks = noise)).map { it / sr }
        val score = StrumScore.grade(tl, onsets)
        assertEquals("$id：起音数 expected=${tl.strokes.map { "%.3f".format(it.time) }} got=${onsets.map { "%.3f".format(it) }}", tl.strokes.size, onsets.size)
        assertEquals("$id：每下都在 ±60 ms 内", tl.strokes.size, score.good)
        assertEquals("$id：杂音和余音不算起音", 0, score.extras.size)
        assertTrue("$id：平均误差 ${score.meanOffsetMs}", abs(score.meanOffsetMs ?: 99.0) < 8)
    }

    @Test fun detectsFolkPattern() = check("folk1", 90.0)
    @Test fun detectsHalfStrums() = check("country", 100.0)
    @Test fun detectsFastEighths() = check("eighths", 140.0)
    @Test fun detectsMutedStrokes() = check("chunk", 100.0)
    @Test fun detectsSixteenthFunk() = check("funk", 90.0)

    /** 根音单拨很轻：在该拨根音的格子附近放低门槛，都能算命中；节拍外的杂音照样不算。 */
    @Test fun quietRootNotesCountNearTheirCells() {
        val tl = StrumTimeline(StrumRhythm.preset("rootStrum")!!, 90.0, 0.5, 2)
        val noise = tl.strokes.dropLast(1).map { it.time + tl.stepDuration / 2 }
        val audio = synthesize(tl, clicks = noise, bassLevel = 0.08f)
        val windows = StrumTrainerLogic.bassWindows(tl, 0.0).map { (it.start * sr).toInt()..(it.endInclusive * sr).toInt() }
        val onsets = OnsetDetector(sr).detect(audio, windows).map { it / sr }
        val score = StrumScore.grade(tl, onsets)
        assertEquals("每个根音都收到", 0, score.missed)
        assertEquals("杂音不算", 0, score.extras.size)
        assertEquals(4, score.hits.count { it.stroke == StrumCell.BASS })
    }

    @Test fun silenceAndSteadyNoiseGiveNoOnsets() {
        val d = OnsetDetector(sr)
        assertEquals(emptyList<Int>(), d.detect(FloatArray((sr * 3).toInt())))
        val rng = java.util.Random(7)
        assertEquals("持续的底噪不算扫弦", emptyList<Int>(), d.detect(FloatArray((sr * 3).toInt()) { (rng.nextDouble() * 2 - 1).toFloat() * 0.003f }))
    }

    /** 弹得早或晚，检测出来的时间跟着走（误差在 5 ms 内）。 */
    @Test fun onsetTimesAreAccurate() {
        val tl = StrumTimeline(StrumRhythm.preset("quarters")!!, 80.0, 0.5, 2)
        val shift = 0.037
        val shifted = StrumTimeline(tl.pattern, 80.0, 0.5 + shift, 2)
        val onsets = OnsetDetector(sr).detect(synthesize(shifted)).map { it / sr }
        assertEquals(shift * 1000, StrumScore.grade(tl, onsets).meanOffsetMs!!, 5.0)
    }

    /** 录音换算成时间：每个缓冲自己的时间戳，缓冲之间有空隙也不累积误差。 */
    @Test fun capturedBuffersMapToTheClock() {
        val tl = StrumTimeline(StrumRhythm.preset("quarters")!!, 100.0, 0.4, 2)
        val audio = synthesize(tl)
        val host0 = 5_000.0
        val chunks = ArrayList<StrumCaptureChunk>()
        var i = 0
        var skew = 0.0
        while (i < audio.size) {
            if (i >= (1.2 * sr).toInt()) skew = 0.003
            chunks.add(StrumCaptureChunk(host0 + i / sr + skew, audio.copyOfRange(i, minOf(audio.size, i + 1024))))
            i += 1024
        }
        val times = StrumCapture(chunks, sr).onsetTimes()
        assertEquals(tl.strokes.size, times.size)
        for ((t, s) in times.zip(tl.strokes)) assertEquals(host0 + s.time + if (s.time >= 1.2) 0.003 else 0.0, t, 0.006)
    }
}

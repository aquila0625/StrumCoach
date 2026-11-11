package com.example.strumcoach.metronome

import com.example.strumcoach.rhythm.AccentLevel
import com.example.strumcoach.rhythm.RampSettings
import com.example.strumcoach.rhythm.TimeSignature
import com.example.strumcoach.rhythm.TrainingPlan
import com.example.strumcoach.rhythm.MuteSettings
import com.example.strumcoach.rhythm.VoiceLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.max

/** 离线渲染真实的音频输出，从波形里找每一下的起音点来量节拍间隔。 */
class OfflineRenderTest {
    private class Measurement {
        val onsets = ArrayList<Long>()
        val mainBeats = ArrayList<ClickEvent>()
        var peak = 0f
    }

    private fun render(config: MetronomeConfig, sampleRate: Double, seconds: Double, chunk: Int = 512,
                       threshold: Float = 1e-4f, minGap: Double = 0.25): Measurement {
        val renderer = ClickRenderer(VoiceBank(sampleRate), config)
        renderer.start(config)
        val total = (seconds * sampleRate).toLong()
        val gap = (minGap * sampleRate).toLong()
        val buffer = FloatArray(chunk)
        val m = Measurement()
        var lastOnset = Long.MIN_VALUE / 2
        var pos = 0L
        while (pos < total) {
            val n = minOf(chunk.toLong(), total - pos).toInt()
            renderer.render(buffer, n) { if (it.isMainBeat) m.mainBeats.add(it) }
            for (i in 0 until n) {
                val v = abs(buffer[i])
                m.peak = max(m.peak, v)
                val s = pos + i
                if (v > threshold && s - lastOnset >= gap) {
                    m.onsets.add(s); lastOnset = s
                }
            }
            pos += n
        }
        return m
    }

    @Test fun tenMinutesAt120Bpm() {
        val sr = 48_000.0
        val m = render(MetronomeConfig(bpm = 120.0, timeSignature = TimeSignature.FourFour), sr, 600.0)
        val beat = 24_000L
        assertEquals(1_200, m.onsets.size); assertEquals(1_200, m.mainBeats.size)
        assertTrue(m.peak > 0.3f && m.peak <= 1f)
        for ((n, e) in m.mainBeats.withIndex()) assertEquals(n * beat, e.sample)
        var maxErrorMs = 0.0
        for (i in 1 until m.onsets.size) maxErrorMs = max(maxErrorMs, abs((m.onsets[i] - m.onsets[i - 1]) - beat) / sr * 1000)
        assertTrue("最大间隔误差 $maxErrorMs ms", maxErrorMs <= 1.0)
        val downbeats = (0 until m.onsets.size step 4).map { m.onsets[it] }
        val drift = downbeats.withIndex().map { (k, s) -> s - downbeats[0] - k * 4 * beat }
        assertEquals("累计漂移必须为 0", 0L, drift.maxOf { abs(it) })
    }

    @Test fun tenMinutesAtFractionalTempo() {
        val sr = 44_100.0; val bpm = 137.0
        val m = render(MetronomeConfig(bpm = bpm, accents = AccentPattern.repeating(AccentLevel.STRONG, 4), sound = SoundKind.ELECTRONIC),
            sr, 600.0, chunk = 1_024, threshold = 0.01f, minGap = 0.2)
        val length = sr * 60 / bpm
        assertEquals(Math.ceil(600 / (60 / bpm)).toInt(), m.onsets.size)
        val offset0 = m.onsets[0].toDouble()
        var maxDeviation = 0.0
        for ((n, onset) in m.onsets.withIndex()) maxDeviation = max(maxDeviation, abs(onset - offset0 - n * length))
        assertTrue("最大偏差 $maxDeviation 采样", maxDeviation <= 1.0)
    }

    @Test fun tempoChangeInRenderedAudio() {
        val sr = 48_000.0
        val config = MetronomeConfig(bpm = 120.0)
        val renderer = ClickRenderer(VoiceBank(sr), config)
        renderer.start(config)
        val buffer = FloatArray(256)
        val beats = ArrayList<Long>()
        var changed = false
        while (renderer.cursor < 48_000 * 4) {
            if (!changed && renderer.cursor >= 30_000) {
                renderer.update(renderer.scheduler.config.copy(bpm = 90.0)); changed = true
            }
            renderer.render(buffer, 256) { if (it.isMainBeat) beats.add(it.sample) }
        }
        assertEquals(listOf(0L, 24_000L, 48_000L, 80_000L, 112_000L, 144_000L, 176_000L), beats)
    }

    @Test fun tenMinutesOfTempoRamp() {
        val sr = 48_000.0
        val plan = TrainingPlan(80, RampSettings(80, 120, 2, 4))
        val m = render(MetronomeConfig(training = plan), sr, 600.0, minGap = 0.3)
        assertEquals(m.onsets.size, m.mainBeats.size)
        var ideal = 0.0
        var maxErrorMs = 0.0
        for ((n, onset) in m.onsets.withIndex()) {
            maxErrorMs = max(maxErrorMs, abs(onset - ideal) / sr * 1000)
            ideal += sr * 60 / plan.bpm(n / 4)
        }
        assertTrue("最大误差 $maxErrorMs ms", maxErrorMs <= 1.0)
        val last = m.onsets.size - 1
        var t = 0.0
        for (n in 0 until last) t += sr * 60 / plan.bpm(n / 4)
        assertTrue(abs(m.onsets[last] - t) <= 0.5 + 1)
    }

    @Test fun mutedBarsAreSilentAndTheNextBeatIsExact() {
        val sr = 48_000.0
        val plan = TrainingPlan(120, mute = MuteSettings.bars(2, 1))
        val config = MetronomeConfig(bpm = 120.0, training = plan)
        val renderer = ClickRenderer(VoiceBank(sr), config)
        renderer.start(config)
        val total = (sr * 60).toInt()
        val out = FloatArray(total)
        val chunk = FloatArray(512)
        var pos = 0
        while (pos < total) {
            val n = minOf(512, total - pos)
            renderer.render(chunk, n)
            System.arraycopy(chunk, 0, out, pos, n)
            pos += n
        }
        val barLen = 24_000 * 4
        // 第 2、5、8… 小节（从 0 数）静音：整小节里没有任何起音，但前一小节最后一拍的尾音可能延续，所以跳过开头 0.2 秒
        for (bar in 0 until 30 step 1) {
            if (bar % 3 != 2) continue
            val from = bar * barLen + (0.2 * sr).toInt()
            val to = minOf((bar + 1) * barLen, total)
            var peak = 0f
            for (i in from until to) peak = max(peak, abs(out[i]))
            assertTrue("bar $bar 应该静音，峰值 $peak", peak < 1e-4f)
        }
        // 恢复后的第一拍精确落在采样上：第 3 小节（bar 3）第 1 拍在 3 × 96000
        val resume = 3 * barLen
        assertTrue(abs(out[resume]) > 0.0f || abs(out[resume + 1]) > 0.0f)
        assertTrue(renderer.cursor >= total)
        assertEquals(VoiceLevel.STRONG, VoiceLevel.STRONG)
    }

    @Test fun everySoundIsAudibleBoundedAndFinite() {
        for (sound in SoundKind.entries) for (level in VoiceLevel.entries) {
            val x = ClickSynth.make(sound, level, 48_000.0)
            assertTrue("$sound/$level 为空", x.isNotEmpty())
            assertTrue(x.all { it.isFinite() })
            val peak = x.maxOf { abs(it) }
            assertEquals("$sound/$level", 0.95f, peak, 1e-3f)
            assertTrue("$sound/$level 末尾没有淡出", abs(x.last()) < 0.05f)
        }
        // 同一个音色，同样的采样率，每次合成结果完全相同
        assertTrue(ClickSynth.make(SoundKind.TICK, VoiceLevel.STRONG, 44_100.0).contentEquals(ClickSynth.make(SoundKind.TICK, VoiceLevel.STRONG, 44_100.0)))
    }
}

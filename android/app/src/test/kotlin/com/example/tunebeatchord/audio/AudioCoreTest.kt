package com.example.tunebeatchord.audio

import com.example.tunebeatchord.tuner.PitchDetector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin

class AudioCoreTest {
    /** 合成一段拨弦采样：基频 f0，带几个泛音，自然衰减。 */
    private fun pluck(f0: Double, sr: Double = 44_100.0, seconds: Double = 1.5, voice: Voice = Voice.GUITAR): SampleBuffer {
        val n = (seconds * sr).toInt()
        val data = FloatArray(n) { i ->
            val t = i / sr
            val v = sin(2 * PI * f0 * t) + 0.5 * sin(2 * PI * 2 * f0 * t) + 0.25 * sin(2 * PI * 3 * f0 * t)
            (v * exp(-t / 0.8) * 0.3).toFloat()
        }
        return SampleBuffer(voice, 40, f0, sr, data)
    }

    private fun centsError(a: Double, b: Double) = 1200 * ln(a / b) / ln(2.0)

    @Test fun resamplingHitsTheRequestedPitch() {
        val sample = pluck(82.4)
        val detector = PitchDetector()
        for (target in listOf(80.0, 82.41, 87.31, 90.0)) {
            val out = SamplePlayback.render(sample, target, 48_000.0, 1.0)
            val frame = out.copyOfRange(2000, 2000 + 4096)
            val r = detector.detect(frame, 48_000.0)
            assertNotNull("$target Hz", r)
            assertEquals("$target Hz", 0.0, centsError(r!!.frequency, target), 3.0)
        }
    }

    @Test fun pluckedSampleEndsAndLoopedSampleKeepsGoing() {
        val plain = pluck(220.0, seconds = 0.5)
        val pb = SamplePlayback(plain, 220.0, 44_100.0)
        val buf = FloatArray(44_100)
        pb.render(buf, buf.size)
        assertTrue(pb.isFinished); assertEquals(0f, buf.last(), 0f)
        // 循环采样：区间是整数个周期，播很久也不结束
        val n = 44_100
        val period = 44_100.0 / 441.0
        val data = FloatArray(n) { sin(2 * PI * 441.0 * it / 44_100.0).toFloat() * 0.5f }
        val loop = SampleBuffer(Voice.VIOLIN, 69, 441.0, 44_100.0, data, 10_000, 10_000 + (period * 100).toInt())
        val pb2 = SamplePlayback(loop, 441.0, 44_100.0)
        val out = FloatArray(44_100 * 5)
        pb2.render(out, out.size)
        assertFalse(pb2.isFinished); assertTrue(abs(out.last()) <= 0.5f && out.takeLast(4000).maxOf { abs(it) } > 0.4f)
        val r = PitchDetector().detect(out.copyOfRange(out.size - 8192, out.size), 44_100.0)
        assertEquals(0.0, centsError(r!!.frequency, 441.0), 2.0)
    }

    @Test fun retuneChangesPitchWithoutRestart() {
        val sample = pluck(110.0, seconds = 3.0)
        val pb = SamplePlayback(sample, 110.0, 48_000.0)
        val a = FloatArray(8192); pb.render(a, a.size)
        pb.retune(110.0 * Math.pow(2.0, 20.0 / 1200))
        val b = FloatArray(8192); pb.render(b, b.size)
        val d = PitchDetector()
        val fa = d.detect(a.copyOfRange(2000, 6096), 48_000.0)!!.frequency
        val fb = d.detect(b.copyOfRange(2000, 6096), 48_000.0)!!.frequency
        assertEquals(20.0, centsError(fb, fa), 3.0)
    }

    private val manifest = """{"version":1,"voices":{"guitar":{"sampleRate":44100,"samples":[
        {"file":"guitar/a.ogg","midi":40,"f0":82.4,"frames":1000},{"file":"guitar/b.ogg","midi":45,"f0":110.0,"frames":1000},
        {"file":"guitar/c.ogg","midi":50,"f0":146.8,"frames":1000}]},
        "violin":{"sampleRate":44100,"samples":[{"file":"violin/a.ogg","midi":55,"f0":196.0,"frames":1000,"loopStart":100,"loopEnd":900}]}}}"""

    @Test fun sampleBankPicksNearestAndAlignsLength() {
        val loads = ArrayList<String>()
        val bank = SampleBank(manifest) { file -> loads.add(file); FloatArray(1024) { 0.1f } }
        assertTrue(bank.hasSamples(Voice.GUITAR)); assertFalse(bank.hasSamples(Voice.CELLO))
        assertEquals(listOf(40 to 82.4, 45 to 110.0, 50 to 146.8), bank.roots(Voice.GUITAR))
        val s = bank.sample(Voice.GUITAR, 105.0)!!
        assertEquals(45, s.midi); assertEquals(1000, s.data.size); assertNull(s.loopStart)
        bank.sample(Voice.GUITAR, 108.0)
        assertEquals("同一段采样只解码一次", listOf("guitar/b.ogg"), loads)
        assertEquals(40, bank.sample(Voice.GUITAR, 60.0)!!.midi); assertEquals(50, bank.sample(Voice.GUITAR, 500.0)!!.midi)
        val v = bank.sample(Voice.VIOLIN, 200.0)!!
        assertEquals(100, v.loopStart); assertEquals(900, v.loopEnd)
        assertNull(bank.sample(Voice.CELLO, 100.0)); assertNull(bank.sample(Voice.GUITAR, 0.0))
        assertNull(SampleBank("not json") { null }.sample(Voice.GUITAR, 100.0))
        assertNull(SampleBank(manifest) { null }.sample(Voice.GUITAR, 100.0))
    }

    @Test fun instrumentToneFallsBackToSynthesisAndIsNormalized() {
        val out = InstrumentTone.render(null, Voice.GUITAR, 220.0, 48_000.0, 1.0, amplitude = 0.5f)
        assertEquals(48_000, out.size)
        assertEquals(0.5f, out.maxOf { abs(it) }, 1e-3f)
        assertEquals(0f, out.last(), 0.01f)
        val r = PitchDetector().detect(out.copyOfRange(3000, 3000 + 4096), 48_000.0)!!
        assertEquals(0.0, centsError(r.frequency, 220.0), 3.0)
        assertEquals(0, InstrumentTone.render(null, Voice.GUITAR, 5.0, 48_000.0, 1.0).count { it != 0f })
    }

    @Test fun toneSynthSineIsAccurateAndFadesWithoutClicks() {
        val sr = 48_000.0
        val synth = ToneSynth(sr).apply { frequency = 440.0; timbre = ToneTimbre.SINE; amplitude = 0.3f }
        assertFalse(synth.isSounding)
        synth.start()
        val x = FloatArray(48_000); synth.render(x, x.size)
        assertEquals(0.0, centsError(PitchDetector().detect(x.copyOfRange(10_000, 14_096), sr)!!.frequency, 440.0), 1.0)
        assertEquals(0.3f, x.takeLast(1000).maxOf { abs(it) }, 0.01f)
        assertEquals(0f, x[0], 0.01f)
        val maxStep = (1 until x.size).maxOf { abs(x[it] - x[it - 1]) }
        assertTrue(maxStep < 0.1f)
        synth.stop()
        val y = FloatArray(8000); synth.render(y, y.size)
        assertEquals(0f, y.last(), 1e-4f); assertFalse(synth.isSounding)
    }

    @Test fun toneSynthInstrumentUsesTheSampleAndRetriggers() {
        val sr = 48_000.0
        val synth = ToneSynth(sr).apply { frequency = 110.0; timbre = ToneTimbre.INSTRUMENT; pluckInterval = 0.5 }
        synth.load(pluck(110.0, 44_100.0, 0.4))
        assertTrue(synth.hasSampler)
        synth.start()
        val x = FloatArray(48_000); synth.render(x, x.size)
        // 采样只有 0.4 秒，每 0.5 秒重新拨一次：第二次拨弦的起头比第一次结束后的静默响得多
        val gap = x.copyOfRange(22_000, 23_500).maxOf { abs(it) }
        val retrigger = x.copyOfRange(24_500, 26_500).maxOf { abs(it) }
        assertTrue("重拨后应有声音：$retrigger vs $gap", retrigger > gap * 3 && retrigger > 0.05f)
        assertEquals(0.0, centsError(PitchDetector().detect(x.copyOfRange(2_000, 6_096), sr)!!.frequency, 110.0), 3.0)
    }

    @Test fun noteMixerSchedulesAtFramesAndEndsVoices() {
        val m = NoteMixer()
        assertFalse(m.isActive)
        m.play(FloatArray(100) { 1f }, startFrame = 150, gain = 0.5f)
        assertTrue(m.isActive)
        val out = FloatArray(128)
        m.mixInto(out, 128, 100)
        assertEquals(0f, out[49], 0f); assertEquals(0.5f, out[50], 0f); assertEquals(0.5f, out[127], 0f)
        val out2 = FloatArray(128)
        m.mixInto(out2, 128, 228)
        assertEquals(0.5f, out2[0], 0f); assertEquals(0.5f, out2[21], 0f); assertEquals(0f, out2[22], 0f)
        assertFalse(m.isActive)
        // 闷音：放 50 帧后淡出
        m.play(FloatArray(1000) { 1f }, startFrame = 0, gain = 1f, holdFrames = 50, fadeFrames = 50)
        val o3 = FloatArray(200); m.mixInto(o3, 200, 0)
        assertEquals(1f, o3[49], 0f); assertTrue(o3[75] in 0.3f..0.7f); assertEquals(0f, o3[150], 0f)
        m.play(FloatArray(10) { 1f }, 0, 1f); m.stopAll(); assertFalse(m.isActive)
    }
}

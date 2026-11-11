package com.example.strumcoach.rhythm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RhythmTrainingTest {
    private val ramp = RampSettings(80, 120, 2, 4, RampSettings.EndBehavior.HOLD)

    @Test fun rampBpmAtBar() {
        assertEquals(80, ramp.bpm(0)); assertEquals(80, ramp.bpm(3)); assertEquals(82, ramp.bpm(4))
        assertEquals(94, ramp.bpm(31)); assertEquals(96, ramp.bpm(32)); assertEquals(118, ramp.bpm(79))
        assertEquals(120, ramp.bpm(80)); assertEquals(120, ramp.bpm(10_000)); assertEquals(120, ramp.bpm(Int.MAX_VALUE))
        assertEquals(80, ramp.bpm(-5))
    }

    @Test fun stepMathAndProgress() {
        assertEquals(20, ramp.stepCount); assertEquals(80, ramp.barsToTarget); assertEquals(84, ramp.cycleBars)
        assertEquals(0.0, ramp.progress(0), 0.0); assertEquals(0.5, ramp.progress(40), 1e-9)
        assertEquals(1.0, ramp.progress(80), 0.0); assertEquals(1.0, ramp.progress(500), 0.0)
    }

    @Test fun lastStepLandsExactlyOnTarget() {
        val r = RampSettings(80, 121, 2, 1)
        assertEquals(21, r.stepCount); assertEquals(120, r.bpm(20)); assertEquals(121, r.bpm(21)); assertEquals(121, r.bpm(22))
        val big = RampSettings(100, 103, 10, 2)
        assertEquals(1, big.stepCount); assertEquals(100, big.bpm(1)); assertEquals(103, big.bpm(2))
    }

    @Test fun descendingAndEqual() {
        val r = RampSettings(120, 100, 5, 2)
        assertFalse(r.isAscending)
        assertEquals(listOf(120, 115, 105, 100, 100), listOf(0, 2, 6, 8, 50).map { r.bpm(it) })
        val same = RampSettings(100, 100, 5, 4, RampSettings.EndBehavior.STOP)
        assertEquals(0, same.stepCount); assertEquals(100, same.bpm(7)); assertEquals(1.0, same.progress(0), 0.0)
        assertFalse(same.isFinished(3)); assertTrue(same.isFinished(4))
    }

    @Test fun endBehaviours() {
        val stop = RampSettings(80, 120, 2, 4, RampSettings.EndBehavior.STOP)
        assertFalse(stop.isFinished(80)); assertFalse(stop.isFinished(83)); assertTrue(stop.isFinished(84)); assertEquals(120, stop.bpm(84))
        assertFalse(ramp.isFinished(1_000_000))
        val loop = RampSettings(80, 120, 2, 4, RampSettings.EndBehavior.LOOP)
        assertEquals(120, loop.bpm(83)); assertEquals(80, loop.bpm(84)); assertEquals(96, loop.bpm(84 + 32))
        assertEquals(0.0, loop.progress(84), 0.0); assertFalse(loop.isFinished(10_000))
    }

    @Test fun invalidParametersAreCorrected() {
        val r = RampSettings(5, 9999, 0, -3)
        assertEquals(20, r.startBPM); assertEquals(400, r.targetBPM); assertEquals(1, r.step); assertEquals(1, r.barsPerStep)
        assertEquals(21, r.bpm(1))
    }

    @Test fun muteBarCycle() {
        val m = MuteSettings.bars(2, 1)
        assertEquals(listOf(false, false, true, false, false, true, false, false, true), (0 until 9).map { m.isMuted(it, 0) })
        assertEquals(m.isMuted(2, 0), m.isMuted(2, 3))
        assertTrue((0 until 30).all { !MuteSettings.bars(3, 0).isMuted(it, 0) })
        assertEquals(listOf(false, true, true, false, true, true), (0 until 6).map { MuteSettings.bars(0, 2).isMuted(it, 0) })
        assertFalse(MuteSettings.bars(1, -4).isMuted(5, 0))
    }

    @Test fun randomMuteIsDeterministicAndHonoursProbability() {
        fun pattern(m: MuteSettings) = (0 until 50).flatMap { bar -> (0 until 4).map { m.isMuted(bar, it) } }
        val a = MuteSettings.randomBeats(0.5, 42); val b = MuteSettings.randomBeats(0.5, 42); val c = MuteSettings.randomBeats(0.5, 43)
        assertEquals(pattern(a), pattern(b)); assertNotEquals(pattern(a), pattern(c))
        assertEquals(pattern(a)[37 * 4 + 2], a.isMuted(37, 2))
        for (bar in 0 until 200) for (beat in 0 until 4) {
            assertFalse(MuteSettings.randomBeats(0.0, 1).isMuted(bar, beat))
            assertTrue(MuteSettings.randomBeats(1.0, 1).isMuted(bar, beat))
            assertTrue(MuteSettings.randomBeats(7.0, 1).isMuted(bar, beat))
            assertFalse(MuteSettings.randomBeats(-1.0, 1).isMuted(bar, beat))
        }
        val quarter = MuteSettings.randomBeats(0.25, 2024)
        val count = (0 until 2500).flatMap { bar -> (0 until 4).map { quarter.isMuted(bar, it) } }.count { it }
        assertEquals(0.25, count / 10_000.0, 0.03)
        val keep = MuteSettings.randomBeats(1.0, 9, keepsDownbeat = true)
        assertFalse(keep.isMuted(3, 0)); assertTrue(keep.isMuted(3, 1))
    }

    /** 固定种子的结果是跨平台约定：这几个值和 iOS 版（SplitMix64）逐位一致。 */
    @Test fun randomMuteMatchesTheReferenceMixFunction() {
        fun mix(x: ULong): ULong {
            var z = x + 0x9E3779B97F4A7C15uL
            z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
            z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
            return z xor (z shr 31)
        }
        val m = MuteSettings.randomBeats(0.5, 7)
        for (bar in 0 until 20) for (beat in 0 until 4) {
            val h = mix(mix(mix(7uL) xor bar.toULong()) xor beat.toULong())
            assertEquals((h shr 11).toDouble() / (1L shl 53) < 0.5, m.isMuted(bar, beat))
        }
        // SplitMix64(0) 的第一个输出是业界公认的 0xE220A8397B1DCDAF
        assertEquals(0xE220A8397B1DCDAFuL, mix(0uL))
    }

    @Test fun trainingPlan() {
        val r = RampSettings(80, 100, 2, 2)
        val mute = MuteSettings.bars(2, 1)
        assertEquals(PracticeMode.FREE, TrainingPlan(90).mode)
        assertEquals(PracticeMode.RAMP, TrainingPlan(90, ramp = r).mode)
        assertEquals(PracticeMode.MUTE, TrainingPlan(90, mute = mute).mode)
        assertEquals(PracticeMode.RAMP_AND_MUTE, TrainingPlan(90, r, mute).mode)

        val both = TrainingPlan(90, RampSettings(80, 120, 2, 4, RampSettings.EndBehavior.STOP), MuteSettings.bars(2, 1))
        assertEquals(TrainingPlan.BeatState(96, true, false), both.state(32, 1))
        assertEquals(TrainingPlan.BeatState(96, false, false), both.state(33, 1))
        assertFalse(both.state(34, 0).isMuted); assertTrue(both.state(35, 0).isMuted)
        assertTrue(both.state(84, 0).isFinished)

        val plain = TrainingPlan(100)
        assertEquals(TrainingPlan.BeatState(100, false, false), plain.state(500, 3))
        assertNull(plain.progress(5)); assertEquals(100..100, plain.bpmRange(500))
    }

    @Test fun bpmRangeForSessionRecord() {
        fun plan(b: RampSettings.EndBehavior) = TrainingPlan(80, RampSettings(80, 120, 2, 4, b))
        assertEquals(80..96, plan(RampSettings.EndBehavior.HOLD).bpmRange(32))
        assertEquals(80..120, plan(RampSettings.EndBehavior.HOLD).bpmRange(5000))
        assertEquals(80..120, plan(RampSettings.EndBehavior.STOP).bpmRange(83))
        assertEquals(80..120, plan(RampSettings.EndBehavior.LOOP).bpmRange(84))
        assertEquals(80..80, plan(RampSettings.EndBehavior.LOOP).bpmRange(0))
        assertEquals(110..120, TrainingPlan(120, RampSettings(120, 100, 5, 2)).bpmRange(4))
    }

    @Test fun timeSignatureAndRhythmSettings() {
        assertEquals(1, TimeSignature.of(0, 4).beatsPerBar); assertEquals(32, TimeSignature.of(99, 4).beatsPerBar)
        assertEquals(4, TimeSignature.of(4, 5).beatUnit); assertEquals("6/8", TimeSignature.SixEight.displayName)
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.WEAK, AccentLevel.WEAK), RhythmSettings.make(TimeSignature.ThreeFour).accents)
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.MEDIUM), RhythmSettings.make(TimeSignature.TwoFour, listOf(AccentLevel.STRONG, AccentLevel.MEDIUM, AccentLevel.WEAK)).accents)
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.WEAK, AccentLevel.WEAK, AccentLevel.WEAK), RhythmSettings.make(TimeSignature.FourFour, listOf(AccentLevel.STRONG)).accents)
        var s = RhythmSettings.make(TimeSignature.FourFour, listOf(AccentLevel.STRONG, AccentLevel.MUTED, AccentLevel.MEDIUM, AccentLevel.WEAK))
        s = s.withTimeSignature(TimeSignature.SixEight)
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.MUTED, AccentLevel.MEDIUM, AccentLevel.WEAK, AccentLevel.WEAK, AccentLevel.WEAK), s.accents)
        s = s.withTimeSignature(TimeSignature.ThreeFour)
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.MUTED, AccentLevel.MEDIUM), s.accents)
        val t = RhythmSettings.make(TimeSignature.ThreeFour)
        assertEquals(AccentLevel.STRONG, t.accent(3)); assertEquals(AccentLevel.WEAK, t.accent(-1))
        assertEquals(t, t.withAccent(AccentLevel.MUTED, 9))
        assertEquals(AccentLevel.MUTED, t.withAccent(AccentLevel.MUTED, 1).accents[1])
        assertEquals(AccentLevel.MEDIUM, AccentLevel.STRONG.cycled); assertEquals(AccentLevel.STRONG, AccentLevel.MUTED.cycled)
        assertEquals(20, Tempo.clamp(5)); assertEquals(400, Tempo.clamp(999))
    }

    @Test fun subdivisionOffsets() {
        for (s in Subdivision.entries) {
            assertEquals(0.0, s.offsets.first(), 0.0)
            assertEquals(s.offsets, s.offsets.sorted())
            assertTrue(s.offsets.all { it >= 0 && it < 1 })
        }
        assertEquals(3, Subdivision.TRIPLET.clickCount)
        assertEquals(listOf(0.0, 0.25, 0.75), Subdivision.SYNCOPATION.offsets)
    }
}

package com.example.strumcoach.metronome

import com.example.strumcoach.rhythm.MuteSettings
import com.example.strumcoach.rhythm.RampSettings
import com.example.strumcoach.rhythm.Subdivision
import com.example.strumcoach.rhythm.TimeSignature
import com.example.strumcoach.rhythm.TrainingPlan
import com.example.strumcoach.rhythm.PracticeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.roundToLong

/** 渐进提速、静音训练接到调度器上之后的采样位置。 */
class TrainingSchedulerTest {
    private val sr = 48_000.0

    private fun run(config: MetronomeConfig, samples: Long, chunk: Int = 512): Pair<List<ClickEvent>, BeatScheduler> {
        val s = BeatScheduler(sr, config)
        s.start(0)
        val out = ArrayList<ClickEvent>()
        var pos = 0L
        while (pos < samples) {
            val n = minOf(chunk.toLong(), samples - pos).toInt()
            s.generate(pos, n) { out.add(it) }
            pos += n
        }
        return out to s
    }

    /** 按训练方案逐拍累加出理论位置（连续时间，不取整）。 */
    private fun ideal(plan: TrainingPlan, beatsPerBar: Int, beats: Int): List<Double> {
        var t = 0.0
        return (0 until beats).map { n -> t.also { t += sr * 60 / plan.bpm(n / beatsPerBar) } }
    }

    @Test fun rampChangesTempoAtBarBoundaries() {
        val plan = TrainingPlan(80, RampSettings(80, 120, 2, 4, RampSettings.EndBehavior.HOLD))
        val (events, _) = run(MetronomeConfig(bpm = 200.0, training = plan), (sr * 60 * 4).toLong())
        val mains = events.filter { it.isMainBeat }
        assertEquals(96.0, mains.first { it.bar == 32 }.bpm, 0.0)
        for ((e, t) in mains.zip(ideal(plan, 4, mains.size))) {
            assertEquals("beat ${e.beatSerial}", t, e.sample.toDouble(), 0.5)
            assertEquals(plan.bpm(e.bar).toDouble(), e.bpm, 0.0)
            assertEquals(e.beatSerial.toInt() / 4, e.bar)
        }
        val first82 = mains.indexOfFirst { it.bpm == 82.0 }
        assertEquals(0, mains[first82].beatInBar)
        assertEquals(36_000L, mains[first82].sample - mains[first82 - 1].sample)
        assertEquals((sr * 60 / 82).roundToLong().toDouble(), (mains[first82 + 1].sample - mains[first82].sample).toDouble(), 1.0)
    }

    @Test fun rampWithSubdivisionsKeepsOffsetsInsideEachBeat() {
        val plan = TrainingPlan(100, RampSettings(100, 140, 5, 1))
        val (events, _) = run(MetronomeConfig(timeSignature = TimeSignature.ThreeFour, subdivision = Subdivision.TRIPLET, training = plan), (sr * 30).toLong())
        var i = 0
        while (i + 2 < events.size) {
            val beat = events[i]
            assertTrue(beat.isMainBeat)
            val length = sr * 60 / beat.bpm
            assertEquals(length / 3, (events[i + 1].sample - beat.sample).toDouble(), 1.0)
            assertEquals(length * 2 / 3, (events[i + 2].sample - beat.sample).toDouble(), 1.0)
            i += 3
        }
    }

    @Test fun rampStopEndsPlayback() {
        val ramp = RampSettings(120, 124, 2, 1, RampSettings.EndBehavior.STOP)
        assertEquals(3, ramp.cycleBars)
        val (events, s) = run(MetronomeConfig(training = TrainingPlan(120, ramp)), (sr * 20).toLong())
        assertTrue(s.isFinished); assertFalse(s.isRunning)
        val mains = events.filter { it.isMainBeat }
        assertEquals(12, mains.size)
        assertEquals(List(4) { 120.0 } + List(4) { 122.0 } + List(4) { 124.0 }, mains.map { it.bpm })
    }

    @Test fun rampLoopReturnsToStart() {
        val ramp = RampSettings(60, 64, 4, 1, RampSettings.EndBehavior.LOOP)
        val (events, _) = run(MetronomeConfig(timeSignature = TimeSignature.TwoFour, training = TrainingPlan(60, ramp)), (sr * 12).toLong())
        val perBar = events.filter { it.isMainBeat && it.beatInBar == 0 }.map { it.bpm }
        assertEquals(listOf(60.0, 64.0, 60.0, 64.0, 60.0), perBar.take(5))
    }

    @Test fun muteBarsSilenceWholeBarsButKeepTiming() {
        val plan = TrainingPlan(120, mute = MuteSettings.bars(2, 1))
        val (events, _) = run(MetronomeConfig(bpm = 120.0, subdivision = Subdivision.EIGHTH, training = plan), 24_000L * 4 * 6)
        for (e in events) {
            assertEquals("bar ${e.bar}", e.bar % 3 == 2, e.isTrainingMuted)
            if (e.isTrainingMuted) assertEquals(0f, e.gain, 0f) else assertTrue(e.gain > 0)
        }
        val mains = events.filter { it.isMainBeat }
        assertEquals((0 until mains.size).map { it * 24_000L }, mains.map { it.sample })
    }

    @Test fun randomMuteFollowsThePattern() {
        val mute = MuteSettings.randomBeats(0.4, 7, keepsDownbeat = true)
        val (events, _) = run(MetronomeConfig(bpm = 150.0, timeSignature = TimeSignature.SevenEight, training = TrainingPlan(150, mute = mute)), (sr * 30).toLong())
        var muted = 0
        for (e in events.filter { it.isMainBeat }) {
            assertEquals(mute.isMuted(e.bar, e.beatInBar), e.isTrainingMuted)
            if (e.beatInBar == 0) assertFalse(e.isTrainingMuted)
            if (e.isTrainingMuted) muted++
        }
        assertTrue(muted > 0)
    }

    @Test fun rampAndMuteTogether() {
        val ramp = RampSettings(90, 100, 5, 2)
        val plan = TrainingPlan(90, ramp, MuteSettings.bars(3, 1))
        assertEquals(PracticeMode.RAMP_AND_MUTE, plan.mode)
        val (events, _) = run(MetronomeConfig(training = plan), (sr * 40).toLong())
        val mains = events.filter { it.isMainBeat }
        for ((e, t) in mains.zip(ideal(plan, 4, mains.size))) {
            assertEquals(t, e.sample.toDouble(), 0.5)
            assertEquals(e.bar % 4 == 3, e.isTrainingMuted)
            assertEquals(ramp.bpm(e.bar).toDouble(), e.bpm, 0.0)
        }
    }

    @Test fun turningTrainingOnMidPlayAppliesAtNextBeat() {
        val s = BeatScheduler(sr, MetronomeConfig(bpm = 120.0))
        s.start(0)
        val events = ArrayList<ClickEvent>()
        s.generate(0, 30_000) { events.add(it) }
        s.update(s.config.copy(training = TrainingPlan(120, mute = MuteSettings.bars(1, 1))))
        s.generate(30_000, 24_000 * 8) { events.add(it) }
        assertEquals(listOf(false, false, false, false, true, true, true, true, false, false), events.map { it.isTrainingMuted })
        assertEquals((0 until 10).map { it * 24_000L }, events.map { it.sample })
    }

}

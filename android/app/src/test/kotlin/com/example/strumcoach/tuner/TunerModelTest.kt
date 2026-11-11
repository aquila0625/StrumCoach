package com.example.strumcoach.tuner

import com.example.strumcoach.audio.TuneChime
import com.example.strumcoach.settings.MemoryStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow

class TunerModelTest {
    private var now = 100.0
    private var chimes = 0

    private fun make(id: String = "guitar", tuning: String = "standard", chime: Boolean = true, store: MemoryStore = MemoryStore()): TunerModel {
        val m = TunerModel(InstrumentSelection(id, tuning), store = store)
        m.clock = { now }
        m.playChime = { chimes++; true }
        m.chimeDuration = TuneChime.DURATION
        m.setTuneChime(chime)
        return m
    }

    private fun feed(m: TunerModel, f: Double, frames: Int = 12) {
        for (i in 0 until frames) {
            now += 0.03
            m.ingest(Signal.make(Signal.Shape.HARMONICS, f, phase = i * 0.31), 44100.0)
        }
    }

    /** 以 30 ms 一帧喂 `seconds` 秒的稳定读数（偏差 `cents`）。 */
    private fun hold(m: TunerModel, f: Double, cents: Double = 0.0, seconds: Double) {
        val hz = f * 2.0.pow(cents / 1200)
        repeat((seconds / 0.03).toInt()) { now += 0.03; m.ingest(RawPitch(hz, 0.97)) }
    }

    @Test fun autoRecognisesStringAndTicksWhenTuned() {
        val m = make()
        feed(m, 110.0, 30)
        assertEquals(1, m.result?.stringIndex); assertEquals("A2", m.result?.target?.fullName); assertTrue(m.result?.isInTune == true)
        assertEquals(setOf(1), m.tunedStrings); assertEquals(1, m.tunedEventCount)
        now += 2
        feed(m, 110 * 2.0.pow(30.0 / 1200), 12)
        assertFalse(m.result?.isInTune ?: true); assertEquals(emptySet<Int>(), m.tunedStrings)
    }

    @Test fun lockedStringAndUnlock() {
        val m = make()
        m.lockString(0); feed(m, 110.0)
        assertEquals(0, m.result?.stringIndex); assertTrue((m.result?.cents ?: 0.0) > 400)
        m.lockString(0); assertNull(m.lockedString); assertEquals(1, m.result?.stringIndex)
    }

    @Test fun silenceClearsReading() {
        val m = make()
        feed(m, 440.0); assertNotNull(m.reading)
        repeat(20) { m.ingest(FloatArray(4096), 44100.0) }
        assertNull(m.reading); assertNull(m.result); assertNotNull(m.lastReading)
    }

    @Test fun changingInstrumentResetsState() {
        val m = make()
        feed(m, 110.0); m.lockString(2)
        m.select(InstrumentLibrary.bass)
        assertEquals("4string", m.tuning.id); assertNull(m.lockedString); assertTrue(m.tunedStrings.isEmpty())
        assertEquals(InstrumentSelection("bass", "4string"), m.selection)
    }

    @Test fun a4RangeAndEffect() {
        val m = make("auto", "chromatic")
        m.updateA4(400.0); assertEquals(415.0, m.a4, 0.0)
        m.updateA4(500.0); assertEquals(466.0, m.a4, 0.0)
        m.updateA4(442.0); assertEquals(442.0, m.a4, 0.0)
        feed(m, 442.0)
        assertEquals("A4", m.result?.target?.fullName); assertEquals(0.0, m.result?.cents ?: 99.0, 1.0)
    }

    @Test fun doesNotFireBeforeHalfASecond() {
        val m = make()
        hold(m, 110.0, seconds = 0.4)
        assertEquals(0, m.tunedEventCount); assertEquals(0, chimes)
        hold(m, 110.0, seconds = 0.3)
        assertEquals(1, m.tunedEventCount); assertEquals(1, chimes); assertEquals(setOf(1), m.tunedStrings)
        assertEquals("A2", m.lastTunedEvent?.pitch?.fullName); assertEquals(1, m.lastTunedEvent?.stringIndex)
    }

    @Test fun sweepingThroughTheTuneZoneDoesNotFire() {
        val m = make()
        for (step in 0..20) { now += 0.03; m.ingest(RawPitch(110 * 2.0.pow((step * 3 - 30) / 1200.0), 0.97)) }
        assertEquals(0, m.tunedEventCount); assertEquals(0, chimes)
    }

    @Test fun firesOnlyOnceAndAgainAfterDriftingBeyondTenCents() {
        val m = make()
        hold(m, 110.0, seconds = 3.0); assertEquals(1, m.tunedEventCount)
        hold(m, 110.0, cents = 8.0, seconds = 1.5); hold(m, 110.0, seconds = 1.5)
        assertEquals(1, chimes); assertEquals(setOf(1), m.tunedStrings)
        hold(m, 110.0, cents = 20.0, seconds = 1.5); assertEquals(emptySet<Int>(), m.tunedStrings)
        hold(m, 110.0, seconds = 1.0)
        assertEquals(2, chimes); assertEquals(2, m.tunedEventCount); assertEquals(setOf(1), m.tunedStrings)
    }

    @Test fun ignoresDetectionWhileChimePlays() {
        val m = make()
        hold(m, 110.0, seconds = 1.0); assertEquals(1, chimes)
        val before = m.reading?.frequency
        hold(m, 1318.51, seconds = 0.9)
        assertEquals(before ?: 1.0, m.reading?.frequency ?: 0.0, 0.01); assertEquals(1, m.result?.stringIndex)
        hold(m, 196.0, seconds = 0.8)
        assertEquals("G3", m.result?.target?.fullName)
    }

    @Test fun disabledChimeStillTicksButDoesNotPlayOrBlindDetection() {
        val m = make(chime = false)
        hold(m, 110.0, seconds = 1.0)
        assertEquals(1, m.tunedEventCount); assertEquals(setOf(1), m.tunedStrings); assertEquals(0, chimes)
        hold(m, 196.0, seconds = 0.5); assertEquals("G3", m.result?.target?.fullName)
    }

    @Test fun chromaticModeFiresPerNoteName() {
        val m = make("auto", "chromatic")
        hold(m, 440.0, seconds = 1.0)
        assertEquals(1, chimes); assertNull(m.lastTunedEvent?.stringIndex); assertEquals("A4", m.lastTunedEvent?.pitch?.fullName)
        assertTrue(m.tunedStrings.isEmpty())
        hold(m, 440.0, seconds = 2.0); assertEquals("同一个音只提示一次", 1, chimes)
        now += 1.5
        hold(m, 329.63, seconds = 1.2)
        assertEquals(2, chimes); assertEquals("E4", m.lastTunedEvent?.pitch?.fullName)
    }

    @Test fun switchingTargetRestartsTheHold() {
        val m = make()
        m.lockString(1); hold(m, 110.0, seconds = 0.4)
        m.lockString(3); hold(m, 110.0, seconds = 0.4)
        assertEquals(0, chimes)
    }

    @Test fun chimeSettingIsPersistedAndDefaultsToOn() {
        val store = MemoryStore()
        assertTrue(TunerModel(store = store).tuneChimeEnabled)
        TunerModel(store = store).setTuneChime(false)
        assertFalse(TunerModel(store = store).tuneChimeEnabled)
    }

    @Test fun referenceToneCallbacksAndPause() {
        val m = make()
        var played: Pitch? = null; var stopped = 0; var retuned = 0.0
        m.onPlayReference = { p, _, _, _ -> played = p }; m.onStopReference = { stopped++ }; m.onRetuneReference = { retuned = it }
        val a2 = Pitch.parse("A2")!!
        m.toggleReference(a2)
        assertEquals(a2, played); assertEquals(a2, m.playingReference)
        // 参考音响着时不处理检测结果
        hold(m, 330.0, seconds = 0.5); assertNull(m.reading)
        m.updateA4(442.0); assertEquals(a2.frequency(442.0), retuned, 1e-9)
        m.toggleReference(a2); assertNull(m.playingReference); assertEquals(1, stopped)
    }

    @Test fun chimeRendersShortAndClickFree() {
        val rate = 44_100.0
        val x = TuneChime.render(rate)
        assertEquals((TuneChime.DURATION * rate).toInt(), x.size)
        assertEquals(0.4f, x.maxOf { abs(it) }, 0.01f)
        assertEquals(0f, x.last(), 1e-4f); assertEquals(0f, x.first(), 1e-3f)
        assertTrue((1 until x.size).maxOf { abs(x[it] - x[it - 1]) } < 0.12f)
        val d = PitchDetector()
        assertEquals(TuneChime.FIRST_FREQUENCY, d.detect(x.copyOfRange((0.012 * rate).toInt(), (0.012 * rate).toInt() + 2048), rate)?.frequency ?: 0.0, 15.0)
        assertEquals(TuneChime.SECOND_FREQUENCY, d.detect(x.copyOfRange((0.3 * rate).toInt(), (0.3 * rate).toInt() + 2048), rate)?.frequency ?: 0.0, 15.0)
        assertTrue(TuneChime.DURATION < 1.0)
    }
}

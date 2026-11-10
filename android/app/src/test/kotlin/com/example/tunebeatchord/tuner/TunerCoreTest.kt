package com.example.tunebeatchord.tuner

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow

class TunerCoreTest {
    // 音高与乐器 ---------------------------------------------------------

    @Test fun pitchBasics() {
        assertEquals(69, Pitch.parse("A4")?.midi)
        assertEquals(60, Pitch.parse("C4")?.midi)
        assertEquals(39, Pitch.parse("Eb2")?.midi)
        assertEquals(54, Pitch.parse("F#3")?.midi)
        assertEquals(23, Pitch.parse("B0")?.midi)
        assertEquals(440.0, Pitch(69).frequency(), 1e-9)
        assertEquals(82.4069, Pitch(40).frequency(), 0.001)
        assertEquals("A♯", Pitch(70).name)
        assertEquals("B0", Pitch(23).fullName)
        assertNull(Pitch.parse("H4"))
    }

    @Test fun a4ShiftsFrequencies() {
        assertEquals(415.0, Pitch(69).frequency(415.0), 1e-9)
        assertEquals(466.0, Pitch(69).frequency(466.0), 1e-9)
        val (pitch, cents) = Pitch.nearest(415.0, 415.0)
        assertEquals(69, pitch.midi)
        assertEquals(0.0, cents, 1e-9)
    }

    private fun notes(id: String, tuning: String) =
        InstrumentLibrary.instrument(id)!!.tuning(tuning)!!.strings.map { it.pitch.fullName }

    @Test fun builtInTunings() {
        assertEquals(listOf("E2", "A2", "D3", "G3", "B3", "E4"), notes("guitar", "standard"))
        assertEquals(listOf("D2", "A2", "D3", "G3", "B3", "E4"), notes("guitar", "dropD"))
        assertEquals(listOf("D♯2", "G♯2", "C♯3", "F♯3", "A♯3", "D♯4"), notes("guitar", "halfDown"))
        assertEquals(listOf("D2", "A2", "D3", "G3", "A3", "D4"), notes("guitar", "dadgad"))
        assertEquals(listOf("E1", "A1", "D2", "G2"), notes("bass", "4string"))
        assertEquals(listOf("B0", "E1", "A1", "D2", "G2"), notes("bass", "5string"))
        assertEquals(listOf("G4", "C4", "E4", "A4"), notes("ukulele", "highG"))
        assertEquals(listOf("G3", "C4", "E4", "A4"), notes("ukulele", "lowG"))
        assertEquals(listOf("G3", "D4", "A4", "E5"), notes("violin", "standard"))
        assertEquals(listOf("C3", "G3", "D4", "A4"), notes("viola", "standard"))
        assertEquals(listOf("C2", "G2", "D3", "A3"), notes("cello", "standard"))
    }

    @Test fun libraryIsConsistent() {
        val ids = InstrumentLibrary.all.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(InstrumentLibrary.auto.defaultTuning.isChromatic)
        for (inst in InstrumentLibrary.all) {
            assertNotNull(inst.tuning(inst.defaultTuningID))
            for (t in inst.tunings.filter { !it.isChromatic }) {
                assertEquals((t.stringCount downTo 1).toList(), t.strings.map { it.number })
            }
        }
    }

    @Test fun selectionResolveFallsBack() {
        val r = InstrumentSelection("guitar", "nonsense").resolve()
        assertEquals("guitar", r.first.id)
        assertEquals("standard", r.second.id)
        assertEquals("auto", InstrumentSelection("zzz", "x").resolve().first.id)
    }

    // 弦匹配 -------------------------------------------------------------

    private fun reading(f: Double, a4: Double = 440.0) = PitchReading(f, 1.0, a4)

    @Test fun autoMatchPicksClosestString() {
        val guitar = InstrumentLibrary.guitar.defaultTuning
        val cases = listOf(
            82.41 to 0, 110.0 to 1, 146.83 to 2, 196.0 to 3, 246.94 to 4, 329.63 to 5,
            84.0 to 0, 108.0 to 1, 200.0 to 3, 320.0 to 5,
        )
        for ((f, idx) in cases) assertEquals("$f Hz", idx, guitar.match(reading(f)).stringIndex)
        val r = guitar.match(reading(110 * 2.0.pow(8.0 / 1200)))
        assertEquals(8.0, r.cents, 1e-6)
        assertTrue(r.isSharp)
        assertFalse(r.isInTune)
        assertTrue(guitar.match(reading(110 * 2.0.pow(-4.0 / 1200))).isInTune)
    }

    @Test fun wrongOctaveChoosesNearestByPitch() {
        assertEquals(2, InstrumentLibrary.guitar.defaultTuning.match(reading(164.81)).stringIndex)
    }

    @Test fun ukuleleReentrantTuning() {
        val high = InstrumentLibrary.ukulele.tuning("highG")!!
        val low = InstrumentLibrary.ukulele.tuning("lowG")!!
        assertEquals(0, high.match(reading(392.0)).stringIndex)
        assertEquals("G4", high.match(reading(392.0)).target.fullName)
        assertEquals(1, high.match(reading(261.63)).stringIndex)
        assertEquals(3, high.match(reading(440.0)).stringIndex)
        assertEquals(0, low.match(reading(196.0)).stringIndex)
        assertEquals("G3", low.match(reading(196.0)).target.fullName)
    }

    @Test fun lockedStringMeasuresAgainstThatString() {
        val guitar = InstrumentLibrary.guitar.defaultTuning
        val r = guitar.match(reading(110.0), lockedString = 0)
        assertEquals(0, r.stringIndex)
        assertEquals("E2", r.target.fullName)
        assertEquals(500.0, r.cents, 1.0)
        assertTrue(guitar.match(reading(82.41), lockedString = 0).isInTune)
        assertEquals(1, guitar.match(reading(110.0), lockedString = 99).stringIndex)
    }

    @Test fun chromaticMatch() {
        val auto = InstrumentLibrary.auto.defaultTuning
        val r = auto.match(reading(440.8))
        assertNull(r.stringIndex)
        assertEquals("A4", r.target.fullName)
        assertEquals(3.15, r.cents, 0.05)
        assertEquals("C4", auto.match(reading(261.63)).target.fullName)
    }

    @Test fun matchHonoursA4() {
        val r = InstrumentLibrary.guitar.defaultTuning.match(reading(103.75, a4 = 415.0))
        assertEquals(1, r.stringIndex)
        assertTrue(r.isInTune)
        assertEquals(103.75, r.targetFrequency, 0.01)
    }

    // 音名 ---------------------------------------------------------------

    @Test fun lettersMatchOriginalNames() {
        val n = NoteNaming.Letters
        for (pc in 0 until 12) {
            assertEquals(Pitch.sharpNames[pc], n.name(pc))
            assertEquals(Pitch.flatNames[pc], n.name(pc, useFlats = true))
        }
        assertEquals("C#", n.name(1, ascii = true))
        assertEquals("A4", n.fullName(Pitch.parse("A4")!!))
    }

    @Test fun solfegeSpellingPerLanguage() {
        val naturals = listOf(0, 2, 4, 5, 7, 9, 11)
        assertEquals(listOf("Do", "Re", "Mi", "Fa", "Sol", "La", "Si"),
            naturals.map { NoteNaming(NoteNaming.Style.SOLFEGE, "it").name(it) })
        assertEquals("Ré", NoteNaming(NoteNaming.Style.SOLFEGE, "fr").name(2))
        assertEquals("Lá", NoteNaming(NoteNaming.Style.SOLFEGE, "pt-BR").name(9))
        assertEquals("Соль", NoteNaming(NoteNaming.Style.SOLFEGE, "ru").name(7))
        assertEquals("Do♯", NoteNaming(NoteNaming.Style.SOLFEGE, "es").name(1))
        assertEquals("Si♭", NoteNaming(NoteNaming.Style.SOLFEGE, "es").name(10, useFlats = true))
        assertEquals("La4", NoteNaming(NoteNaming.Style.SOLFEGE, "it").fullName(Pitch.parse("A4")!!))
    }

    @Test fun germanUsesHAndB() {
        val de = NoteNaming(NoteNaming.Style.LETTERS, "de")
        assertEquals("H", de.name(11))
        assertEquals("B", de.name(10, useFlats = true))
        assertEquals("A♯", de.name(10))
        assertEquals("A", de.name(9))
        assertEquals("Si", NoteNaming(NoteNaming.Style.SOLFEGE, "de").name(11))
    }

    @Test fun defaultStylePerLanguage() {
        for (code in listOf("fr", "it", "es", "pt-BR", "ru")) assertEquals(code, NoteNaming.Style.SOLFEGE, NoteNaming.defaultStyle(code))
        for (code in listOf("en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "tr")) assertEquals(code, NoteNaming.Style.LETTERS, NoteNaming.defaultStyle(code))
    }

    // 音高检测 -----------------------------------------------------------

    private val detector = PitchDetector()
    private fun centsError(detected: Double, expected: Double) = 1200 * ln(detected / expected) / ln(2.0)

    @Test fun sineAccuracyAcrossStrings() {
        for (rate in listOf(44100.0, 48000.0)) for (f in listOf(82.41, 110.0, 146.83, 196.0, 246.94, 329.63, 440.0)) {
            val x = Signal.make(Signal.Shape.SINE, f, sampleRate = rate)
            val r = detector.detect(x, rate)
            assertNotNull("$f Hz @$rate 未检出", r)
            assertEquals("$f Hz @$rate", 0.0, centsError(r!!.frequency, f), 1.0)
            assertTrue(r.clarity > 0.95)
        }
    }

    @Test fun lowBassString() {
        val rate = 48000.0
        val n = PitchDetector.recommendedFrameLength(rate)
        val x = Signal.make(Signal.Shape.HARMONICS, 30.87, sampleRate = rate, count = n)
        assertEquals(0.0, centsError(detector.detect(x, rate)!!.frequency, 30.87), 3.0)
    }

    @Test fun sawtoothAndWeakFundamentalHaveNoOctaveError() {
        for (f in listOf(82.41, 110.0, 196.0, 329.63, 440.0, 659.26)) {
            val r = detector.detect(Signal.make(Signal.Shape.SAWTOOTH, f), 44100.0)
            assertNotNull("$f", r)
            assertEquals("锯齿波 $f Hz 出现八度误判", 0.0, centsError(r!!.frequency, f), 5.0)
        }
        for (f in listOf(82.41, 110.0, 146.83, 196.0, 246.94)) {
            val r = detector.detect(Signal.make(Signal.Shape.HARMONICS, f), 44100.0)
            assertEquals("$f", 0.0, centsError(r!!.frequency, f), 3.0)
        }
    }

    @Test fun stillCorrectWithWhiteNoise() {
        for (f in listOf(82.41, 110.0, 196.0, 329.63, 440.0)) for (shape in listOf(Signal.Shape.SINE, Signal.Shape.SAWTOOTH)) {
            val x = Signal.addNoise(Signal.make(shape, f), snrDB = 12.0)
            val r = detector.detect(x, 44100.0)
            assertNotNull("$f 噪声下未检出", r)
            assertEquals("$f 噪声下偏差过大", 0.0, centsError(r!!.frequency, f), 15.0)
        }
    }

    @Test fun smoothingAveragesOutNoise() {
        for (f in listOf(110.0, 196.0, 440.0)) {
            val smoother = PitchSmoother()
            var last: PitchReading? = null
            for (seed in 1..20) {
                val x = Signal.addNoise(Signal.make(Signal.Shape.SAWTOOTH, f, phase = seed * 0.37), 12.0, seed.toULong())
                last = smoother.process(detector.detect(x, 44100.0), 440.0)
            }
            assertEquals("$f", 0.0, centsError(last!!.frequency, f), 3.0)
        }
    }

    @Test fun silenceAndNoiseProduceNoPitch() {
        assertNull(detector.detect(FloatArray(4096), 44100.0))
        val hiss = Signal.addNoise(FloatArray(4096), snrDB = 0.0).map { it * 0.0001f }.toFloatArray()
        assertNull(detector.detect(hiss, 44100.0))
        val rng = SplitMix64(7u)
        val white = FloatArray(4096) { (rng.nextUnit() * 2 - 1).toFloat() * 0.3f }
        assertNull(detector.detect(white, 44100.0))
    }

    // 平滑 -----------------------------------------------------------------

    @Test fun singleOutlierIsIgnored() {
        val s = PitchSmoother()
        repeat(6) { s.process(RawPitch(440.0, 0.95), 440.0) }
        assertEquals(440.0, s.process(RawPitch(880.0, 0.9), 440.0)!!.frequency, 0.5)
        assertEquals(440.0, s.process(RawPitch(440.5, 0.95), 440.0)!!.frequency, 1.0)
    }

    @Test fun jitterIsReduced() {
        val s = PitchSmoother()
        val rng = SplitMix64(3u)
        var rawSpread = 0.0
        val outs = ArrayList<Double>()
        for (i in 0 until 60) {
            val jitter = (rng.nextUnit() - 0.5) * 8
            rawSpread = maxOf(rawSpread, abs(jitter))
            val r = s.process(RawPitch(220 * 2.0.pow(jitter / 1200), 0.9), 440.0)!!
            if (i > 10) outs.add(1200 * ln(r.frequency / 220) / ln(2.0))
        }
        assertTrue(outs.maxOf { abs(it) } < rawSpread * 0.6)
    }

    @Test fun realNoteChangeIsAcceptedAfterConfirmation() {
        val s = PitchSmoother()
        repeat(6) { s.process(RawPitch(110.0, 0.95), 440.0) }
        var r: PitchReading? = null
        repeat(4) { r = s.process(RawPitch(146.83, 0.95), 440.0) }
        assertEquals(146.83, r!!.frequency, 1.0)
    }

    @Test fun holdsThenClears() {
        val s = PitchSmoother().apply { holdFrames = 3 }
        s.process(RawPitch(330.0, 0.95), 440.0)
        repeat(3) { assertNotNull(s.process(null, 440.0)) }
        assertNull(s.process(null, 440.0))
        assertFalse(s.isActive)
    }

    // 调准判定 -------------------------------------------------------------

    @Test fun needsHalfASecondInsideFiveCents() {
        val c = TuneConfirmation()
        assertNull(c.update(0, 2.0, 10.0))
        assertNull(c.update(0, -4.0, 10.3))
        assertNull(c.update(0, 1.0, 10.49))
        assertEquals(TuneConfirmation.Event.Tuned(0), c.update(0, 0.0, 10.5))
    }

    @Test fun leavingTheZoneRestartsTheTimer() {
        val c = TuneConfirmation()
        c.update(0, 1.0, 0.0)
        c.update(0, 1.0, 0.4)
        assertNull(c.update(0, 7.0, 0.45))
        assertNull(c.update(0, 1.0, 0.5))
        assertNull(c.update(0, 1.0, 0.9))
        assertEquals(TuneConfirmation.Event.Tuned(0), c.update(0, 1.0, 1.0))
    }

    @Test fun noSignalRestartsTheTimerButKeepsTheLatch() {
        val c = TuneConfirmation()
        c.update(2, 0.0, 0.0)
        assertEquals(TuneConfirmation.Event.Tuned(2), c.update(2, 0.0, 0.5))
        assertNull(c.update(null, null, 0.6))
        assertNull(c.update(2, 0.0, 2.0))
        assertNull(c.update(2, 0.0, 4.0))
        assertTrue(c.isLatched(2))
    }

    @Test fun onlyOncePerKeyUntilItDriftsBeyondTenCents() {
        val c = TuneConfirmation()
        c.update(1, 0.0, 0.0)
        assertEquals(TuneConfirmation.Event.Tuned(1), c.update(1, 0.0, 0.5))
        assertNull(c.update(1, 0.0, 5.0))
        assertNull(c.update(1, 9.9, 5.1))
        assertTrue(c.isLatched(1))
        assertEquals(TuneConfirmation.Event.Drifted(1), c.update(1, 10.5, 5.2))
        assertFalse(c.isLatched(1))
        assertNull(c.update(1, 0.0, 6.0))
        assertEquals(TuneConfirmation.Event.Tuned(1), c.update(1, 0.0, 6.5))
    }

    @Test fun keysAreIndependentAndResetClears() {
        val c = TuneConfirmation()
        c.update(0, 0.0, 0.0)
        assertEquals(TuneConfirmation.Event.Tuned(0), c.update(0, 0.0, 0.5))
        c.update(1, 0.0, 1.0)
        assertNull(c.update(1, 0.0, 1.4))
        assertEquals(TuneConfirmation.Event.Tuned(1), c.update(1, 0.0, 1.5))
        assertTrue(c.isLatched(0) && c.isLatched(1))
        c.reset()
        assertFalse(c.isLatched(0))
    }
}

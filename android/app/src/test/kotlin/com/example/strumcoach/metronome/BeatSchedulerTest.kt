package com.example.strumcoach.metronome

import com.example.strumcoach.rhythm.AccentLevel
import com.example.strumcoach.rhythm.Subdivision
import com.example.strumcoach.rhythm.TimeSignature
import com.example.strumcoach.rhythm.VoiceLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.roundToLong

class BeatSchedulerTest {
    private fun events(s: BeatScheduler, from: Long = 0, count: Int, chunk: Int = 512): List<ClickEvent> {
        val out = ArrayList<ClickEvent>()
        var pos = from
        val end = from + count
        while (pos < end) {
            val n = minOf(chunk.toLong(), end - pos).toInt()
            s.generate(pos, n) { out.add(it) }
            pos += n
        }
        return out
    }

    private fun started(config: MetronomeConfig, sampleRate: Double = 48_000.0) =
        BeatScheduler(sampleRate, config).also { it.start(0) }

    private fun ts(b: Int, u: Int) = TimeSignature.of(b, u)

    @Test fun quarterBeatsAt120() {
        val e = events(started(MetronomeConfig(bpm = 120.0)), count = 24_000 * 8)
        assertEquals((0 until 8).map { it * 24_000L }, e.map { it.sample })
        assertEquals(listOf(0, 1, 2, 3, 0, 1, 2, 3), e.map { it.beatInBar })
        assertEquals((0L until 8L).toList(), e.map { it.beatSerial })
        assertTrue(e.all { it.isMainBeat })
    }

    @Test fun fractionalBeatLengthHasNoAccumulatedDrift() {
        val sr = 44_100.0; val bpm = 137.0
        val s = started(MetronomeConfig(bpm = bpm), sr)
        val length = sr * 60 / bpm
        val beats = 20_000
        val e = events(s, count = (length * beats).toInt() + 1, chunk = 4_096)
        assertEquals(beats + 1, e.size)
        for ((n, ev) in e.withIndex()) assertEquals("beat $n", (n * length).roundToLong(), ev.sample)
    }

    @Test fun startOffsetAccentsAndGains() {
        val config = MetronomeConfig(bpm = 60.0, timeSignature = ts(4, 4),
            accents = AccentPattern(listOf(AccentLevel.STRONG, AccentLevel.MEDIUM, AccentLevel.WEAK, AccentLevel.MUTED)), sound = SoundKind.COWBELL)
        val s = BeatScheduler(1_000.0, config)
        s.start(500)
        val e = events(s, from = 500, count = 4_000, chunk = 7)
        assertEquals(listOf(500L, 1_500L, 2_500L, 3_500L), e.map { it.sample })
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.MEDIUM, AccentLevel.WEAK, AccentLevel.MUTED), e.map { it.accent })
        assertEquals(listOf(VoiceLevel.STRONG, VoiceLevel.MEDIUM, VoiceLevel.WEAK, VoiceLevel.WEAK), e.map { it.level })
        assertEquals(listOf(1.0f, 0.78f, 0.6f, 0f), e.map { it.gain })
        assertTrue(e.all { it.sound == SoundKind.COWBELL })
    }

    @Test fun subdivisionOffsets() {
        val expected = mapOf(
            Subdivision.QUARTER to listOf(0L), Subdivision.EIGHTH to listOf(0L, 12_000L),
            Subdivision.TRIPLET to listOf(0L, 8_000L, 16_000L), Subdivision.SIXTEENTH to listOf(0L, 6_000L, 12_000L, 18_000L),
            Subdivision.DOTTED to listOf(0L, 18_000L), Subdivision.EIGHTH_SIXTEENTH to listOf(0L, 12_000L, 18_000L),
            Subdivision.SIXTEENTH_EIGHTH to listOf(0L, 6_000L, 12_000L), Subdivision.SYNCOPATION to listOf(0L, 6_000L, 18_000L),
        )
        assertEquals(Subdivision.entries.toSet(), expected.keys)
        for ((sub, offsets) in expected) {
            val e = events(started(MetronomeConfig(bpm = 120.0, subdivision = sub)), count = 48_000)
            assertEquals("$sub", offsets + offsets.map { it + 24_000 }, e.map { it.sample })
            assertEquals("$sub", offsets.indices.toList() + offsets.indices.toList(), e.map { it.subIndex })
        }
    }

    @Test fun subdivisionVolumeIs60PercentOfBeat() {
        val config = MetronomeConfig(bpm = 120.0, accents = AccentPattern(listOf(AccentLevel.STRONG, AccentLevel.WEAK, AccentLevel.MEDIUM, AccentLevel.MUTED)), subdivision = Subdivision.EIGHTH)
        assertEquals(0.6f, config.subdivisionVolume, 0f)
        val subs = events(started(config), count = 24_000 * 4).filter { !it.isMainBeat }
        assertEquals(4, subs.size)
        for (sub in subs) {
            assertEquals(sub.accent.gain * 0.6f, sub.gain, 1e-6f)
            assertEquals(VoiceLevel.WEAK, sub.level)
        }
        assertEquals(0f, subs.last().gain, 0f)
    }

    @Test fun tripletRoundsToNearestSample() {
        val e = events(started(MetronomeConfig(bpm = 100.0, subdivision = Subdivision.TRIPLET), 44_100.0), count = 26_460)
        assertEquals(listOf(0L, 8_820L, 17_640L), e.map { it.sample })
        val length = 48_000 * 60 / 137.0
        val e2 = events(started(MetronomeConfig(bpm = 137.0, subdivision = Subdivision.TRIPLET)), count = length.toInt() + 1)
        assertEquals(listOf(0L, (length / 3).roundToLong(), (length * 2 / 3).roundToLong()), e2.map { it.sample })
    }

    @Test fun bpmChangeTakesEffectAtNextBeat() {
        val s = started(MetronomeConfig(bpm = 120.0, subdivision = Subdivision.EIGHTH))
        var e = events(s, count = 6_000)
        assertEquals(listOf(0L), e.map { it.sample })
        s.update(s.config.copy(bpm = 60.0))
        e = e + events(s, from = 6_000, count = 200_000 - 6_000)
        assertEquals(listOf(0L, 12_000L, 24_000L, 48_000L, 72_000L, 96_000L), e.map { it.sample }.take(6))
        assertEquals(listOf(0, 1, 2, 3), e.filter { it.isMainBeat }.map { it.beatInBar }.take(4))
    }

    @Test fun changeExactlyOnBoundaryAndLastUpdateWins() {
        val s = started(MetronomeConfig(bpm = 120.0))
        var e = events(s, count = 24_000)
        s.update(s.config.copy(bpm = 200.0))
        s.update(s.config.copy(bpm = 240.0))
        e = e + events(s, from = 24_000, count = 36_001)
        assertEquals(listOf(0L, 24_000L, 36_000L, 48_000L, 60_000L), e.map { it.sample })
    }

    @Test fun timeSignatureChangeContinuesBarPosition() {
        val s = started(MetronomeConfig(bpm = 120.0, timeSignature = ts(4, 4)))
        var e = events(s, count = 24_000 * 2 - 10)
        s.update(s.config.withTimeSignature(ts(3, 4), AccentPreset.FIRST_STRONG))
        e = e + events(s, from = 24_000 * 2 - 10L, count = 24_000 * 5)
        assertEquals(listOf(0, 1, 2, 0, 1, 2, 0), e.map { it.beatInBar })
        assertEquals(listOf(4, 4, 3, 3, 3, 3, 3), e.map { it.beatsPerBar })
        assertEquals((0 until 7).map { it * 24_000L }, e.map { it.sample })
    }

    @Test fun accentAndSoundChangeAppliesNextBeatWithoutRestart() {
        val s = started(MetronomeConfig(bpm = 120.0, accents = AccentPattern(listOf(AccentLevel.STRONG, AccentLevel.WEAK, AccentLevel.WEAK, AccentLevel.WEAK))))
        var e = events(s, count = 20_000)
        val c = s.config
        s.update(c.copy(accents = c.accents.with(1, AccentLevel.MUTED).with(2, AccentLevel.STRONG), sound = SoundKind.ELECTRONIC, subdivision = Subdivision.SIXTEENTH))
        e = e + events(s, from = 20_000, count = 24_000 * 3 - 20_000)
        val mains = e.filter { it.isMainBeat }
        assertEquals(listOf(AccentLevel.STRONG, AccentLevel.MUTED, AccentLevel.STRONG), mains.map { it.accent })
        assertEquals(listOf(SoundKind.WOODBLOCK, SoundKind.ELECTRONIC, SoundKind.ELECTRONIC), mains.map { it.sound })
        assertEquals(1, e.count { it.beatSerial == 0L })
        assertEquals(4, e.count { it.beatSerial == 1L })
    }

    @Test fun chunkSizeDoesNotChangeEvents() {
        val config = MetronomeConfig(bpm = 173.0, timeSignature = ts(7, 8), subdivision = Subdivision.SYNCOPATION)
        assertEquals(events(started(config), count = 500_000, chunk = 1), events(started(config), count = 500_000, chunk = 4_096))
    }

    @Test fun updateWhileStoppedAppliesImmediatelyAndStopSilences() {
        val s = BeatScheduler(48_000.0, MetronomeConfig.Default)
        s.update(MetronomeConfig.Default.copy(bpm = 60.0))
        assertEquals(60.0, s.config.bpm, 0.0)
        s.start(0)
        assertEquals(listOf(0L, 48_000L, 96_000L), events(s, count = 96_001).map { it.sample })
        s.stop()
        assertTrue(events(s, from = 100_000, count = 100_000).isEmpty())
    }

    @Test fun copyDoesNotDisturbTheOriginal() {
        val s = started(MetronomeConfig(bpm = 120.0))
        events(s, count = 1_000)
        val peek = ArrayList<ClickEvent>()
        s.copy().generate(1_000, 100_000) { peek.add(it) }
        assertEquals(listOf(24_000L, 48_000L, 72_000L, 96_000L), peek.map { it.sample })
        assertEquals(listOf(24_000L), events(s, from = 1_000, count = 30_000).map { it.sample })
    }

    @Test fun modelBasics() {
        assertEquals(20.0, MetronomeConfig(bpm = 5.0).bpm, 0.0)
        assertEquals(400.0, MetronomeConfig(bpm = 999.0).bpm, 0.0)
        for (sub in Subdivision.entries) assertEquals(sub.offsets, (0 until sub.clickCount).map { sub.offset(it) })
        val rhythm = com.example.strumcoach.rhythm.RhythmSettings.make(TimeSignature.SevenEight, subdivision = Subdivision.SYNCOPATION, tone = SoundKind.COWBELL.tone)
            .withAccent(AccentLevel.MUTED, 3)
        val config = MetronomeConfig.from(rhythm, 133.0, 0.4f)
        assertEquals(rhythm, config.rhythm)
        assertEquals(SoundKind.COWBELL, config.sound)
        assertEquals(SoundKind.WOODBLOCK, SoundKind.fromTone("click"))
    }

    @Test fun accentPatternPacking() {
        var p = AccentPattern.repeating(AccentLevel.WEAK, 16)
        p = p.with(15, AccentLevel.MUTED).with(0, AccentLevel.STRONG).with(7, AccentLevel.MEDIUM)
        assertEquals(AccentLevel.MUTED, p[15]); assertEquals(AccentLevel.STRONG, p[0])
        assertEquals(AccentLevel.MEDIUM, p[7]); assertEquals(AccentLevel.WEAK, p[8])
        var wide = AccentPattern.repeating(AccentLevel.WEAK, 32)
        wide = wide.with(31, AccentLevel.STRONG).with(30, AccentLevel.MUTED)
        assertEquals(AccentLevel.STRONG, wide[31]); assertEquals(AccentLevel.MUTED, wide[30]); assertEquals(AccentLevel.WEAK, wide[29])
    }

    @Test fun accentPresets() {
        val s = AccentLevel.STRONG; val w = AccentLevel.WEAK; val m = AccentLevel.MEDIUM
        assertEquals(listOf(s, w, w, w), AccentPreset.FIRST_STRONG.pattern(ts(4, 4)).array)
        assertEquals(listOf(w, w, w, w), AccentPreset.ALL_EQUAL.pattern(ts(4, 4)).array)
        assertEquals(listOf(s, w, m, w), AccentPreset.GROUPED.pattern(ts(4, 4)).array)
        assertEquals(listOf(s, w, w, m, w, w), AccentPreset.GROUPED.pattern(ts(6, 8)).array)
        assertEquals(listOf(s, w, m, w, m, w, w), AccentPreset.GROUPED.pattern(ts(7, 8)).array)
        assertEquals(listOf(3, 2), AccentPreset.groups(ts(5, 4)))
        assertEquals(listOf(2, 2, 2, 2, 3), AccentPreset.groups(ts(11, 8)))
        for (beats in TimeSignature.BEATS_RANGE) for (unit in TimeSignature.ALLOWED_UNITS) {
            val t = ts(beats, unit)
            assertEquals("$t", beats, AccentPreset.groups(t).sum())
            for (preset in AccentPreset.entries) assertEquals(beats, preset.pattern(t).count)
        }
    }

    @Test fun tapTempo() {
        var t = TapTempo()
        assertEquals(null, t.tap(10.0)); assertEquals(120.0, t.tap(10.5)!!, 1e-9)
        t = TapTempo(); for (x in listOf(0.0, 1.0, 2.0, 2.5, 3.0)) t.tap(x)
        assertEquals(120.0, t.tap(3.5)!!, 1e-9); assertEquals(listOf(2.0, 2.5, 3.0, 3.5), t.taps)
        t = TapTempo(); t.tap(0.0); t.tap(0.4); t.tap(1.0); assertEquals(120.0, t.tap(1.5)!!, 1e-9)
        t = TapTempo(); t.tap(0.0); t.tap(1.0)
        assertEquals(null, t.tap(3.01)); assertEquals(listOf(3.01), t.taps); assertEquals(120.0, t.tap(3.51)!!, 1e-6)
        t = TapTempo(); t.tap(0.0); assertEquals(30.0, t.tap(2.0)!!, 1e-9)
        t = TapTempo(); t.tap(0.0); assertEquals(400.0, t.tap(0.05)!!, 0.0)
        val slow = TapTempo().apply { resetInterval = 10.0 }; slow.tap(0.0); assertEquals(20.0, slow.tap(5.0)!!, 0.0)
    }

    @Test fun tempoTerms() {
        assertEquals("Allegro", TempoTerm.italian(120.0)); assertEquals("Moderato", TempoTerm.italian(119.9))
        assertEquals("Grave", TempoTerm.italian(20.0)); assertEquals("Prestissimo", TempoTerm.italian(400.0))
        assertEquals("快板 Allegro", TempoTerm.name(120.0) { it })
        assertEquals("Allegro", TempoTerm.name(120.0) { "Allegro" })
        assertFalse(TempoTerm.localKey(60.0).isEmpty())
    }
}

package com.example.tunebeatchord.chord

import com.example.tunebeatchord.audio.Voice
import com.example.tunebeatchord.tuner.InstrumentFamily
import com.example.tunebeatchord.tuner.InstrumentLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StrumRhythmTest {
    private val guitar = InstrumentLibrary.guitar
    private val ukulele = InstrumentLibrary.ukulele

    private fun voicing(root: String, type: ChordType = ChordType.Major, inst: com.example.tunebeatchord.tuner.Instrument = guitar): Pair<Chord, ChordVoicing> {
        val c = Chord.of(root, type)!!
        return c to ChordLibrary.voicings(c, inst)[0]
    }

    private fun strings(v: ChordVoicing, c: Chord, cell: StrumCell) = RhythmStrum.strings(v, cell, c.root)

    @Test fun presetsMatchTheTrainingPageList() {
        assertEquals(listOf("folk1", "folk2", "eighths", "quarters", "waltz", "chunk", "funk", "island", "ukeBasic", "rootStrum", "country", "waltzBass"),
            StrumRhythm.allPresets.map { it.id })
        assertEquals("D.DU.UDU", StrumRhythm.folk1.code); assertEquals("D.DUDUDU", StrumRhythm.folk2.code)
        assertEquals("DUDUDUDU", StrumRhythm.eighths.code); assertEquals("D.D.D.D.", StrumRhythm.quarters.code)
        assertEquals("D.DUDU", StrumRhythm.waltz.code); assertEquals("D.XU.UXU", StrumRhythm.chunk.code)
        assertEquals("DUDUXUDUDUDUXUDU", StrumRhythm.funk.code); assertEquals("D.DU.UDU", StrumRhythm.island.code)
        assertEquals(3, StrumRhythm.waltz.beatsPerBar); assertEquals(4, StrumRhythm.folk1.beatsPerBar)
        assertEquals(4, StrumRhythm.funk.cellsPerBeat); assertEquals(4, StrumRhythm.funk.beatsPerBar)
    }

    @Test fun defaultsPerInstrument() {
        assertEquals("folk1", StrumRhythm.presets(InstrumentFamily.GUITAR).first().id)
        assertEquals("island", StrumRhythm.presets(InstrumentFamily.UKULELE).first().id)
        assertEquals(listOf("island", "ukeBasic", "eighths", "quarters", "waltz", "chunk", "funk", "rootStrum", "country", "waltzBass"),
            StrumRhythm.presets(InstrumentFamily.UKULELE).map { it.id })
        assertEquals("folk1", StrumRhythm.presets(InstrumentFamily.VIOLIN).first().id)
    }

    @Test fun initValidation() {
        assertNotNull(StrumRhythm.create("a", "D.DU.UDU"))
        assertEquals("D.DU.UDU", StrumRhythm.create("a", "D-DU-UDU")?.code)
        assertEquals("d.dU.UdU", StrumRhythm.create("a", "d.du.udu")?.code)
        assertNull(StrumRhythm.create("a", "D.D")); assertNull(StrumRhythm.create("a", "DUDUDUD", 2))
        assertNull(StrumRhythm.create("a", "DUQU")); assertNull(StrumRhythm.create("a", ""))
        assertNotNull(StrumRhythm.create("a", "DUDU", 4)); assertNull(StrumRhythm.create("a", "DUD", 4))
    }

    @Test fun timesAndCells() {
        val r = StrumRhythm.folk1
        assertEquals(0.5, StrumRhythm.beatDuration(120.0), 1e-12)
        assertEquals(0.25, r.cellDuration(120.0), 1e-12); assertEquals(2.0, r.barDuration(120.0), 1e-12)
        assertEquals(1.5, StrumRhythm.waltz.barDuration(120.0), 1e-12); assertEquals(0.125, StrumRhythm.funk.cellDuration(120.0), 1e-12)
        val strokes = r.strokes(120.0)
        assertEquals(listOf(0, 2, 3, 5, 6, 7), strokes.map { it.first })
        assertEquals(listOf(0.0, 0.5, 0.75, 1.25, 1.5, 1.75), strokes.map { it.second })
        assertEquals(listOf(StrumCell.DOWN, StrumCell.DOWN, StrumCell.UP, StrumCell.UP, StrumCell.DOWN, StrumCell.UP), strokes.map { it.third })
        assertEquals(listOf(StrumCell.DOWN, StrumCell.MUTE, StrumCell.UP, StrumCell.UP, StrumCell.MUTE, StrumCell.UP), StrumRhythm.chunk.strokes(120.0).map { it.third })
        assertEquals(0, r.cellIndex(0.0, 120.0)); assertEquals(1, r.cellIndex(0.26, 120.0)); assertEquals(7, r.cellIndex(1.999, 120.0))
        assertEquals(7, r.cellIndex(5.0, 120.0)); assertEquals(0, r.cellIndex(-1.0, 120.0))
        assertEquals(2.0, StrumRhythm.beatDuration(1.0), 1e-12); assertEquals(0.2, StrumRhythm.beatDuration(9999.0), 1e-12)
    }

    @Test fun arrowsCountLabelsAndVelocities() {
        assertEquals("↓· ↓↑ ·↑ ↓↑", StrumRhythm.folk1.arrows); assertEquals("↓· ✕↑ ·↑ ✕↑", StrumRhythm.chunk.arrows)
        assertEquals(listOf("1", "&", "2", "&", "3", "&", "4", "&"), (0 until 8).map { StrumRhythm.folk1.countLabel(it) })
        assertEquals(listOf("1", "e", "&", "a"), (0 until 4).map { StrumRhythm.funk.countLabel(it) })
        val r = StrumRhythm.folk1
        assertTrue(r.velocity(0) > r.velocity(2)); assertTrue(r.velocity(2) > r.velocity(3)); assertEquals(0f, r.velocity(1), 0f)
        assertTrue(StrumRhythm.eighths.velocity(2) > StrumRhythm.eighths.velocity(3))
    }

    @Test fun cellsAndTypedCharacters() {
        assertEquals(listOf('B', 'D', 'd', 'U', 'X', '.'), listOf(StrumCell.BASS, StrumCell.DOWN, StrumCell.DOWN_TREBLE, StrumCell.UP, StrumCell.MUTE, StrumCell.REST).map { it.ch })
        assertEquals(6, StrumCell.entries.size); assertEquals(6, StrumCell.entries.map { it.arrow }.toSet().size)
        assertEquals(StrumCell.DOWN, StrumCell.typed('D')); assertEquals(StrumCell.DOWN_TREBLE, StrumCell.typed('d'))
        assertEquals(StrumCell.UP, StrumCell.typed('u')); assertEquals(StrumCell.BASS, StrumCell.typed('b')); assertEquals(StrumCell.MUTE, StrumCell.typed('x'))
        assertEquals(StrumCell.REST, StrumCell.typed('-')); assertNull(StrumCell.typed('Q'))
    }

    @Test fun stringsPerCellOnGuitarC() {
        val (c, v) = voicing("C")
        assertEquals(1, RhythmStrum.rootString(v, c.root))
        assertEquals(listOf(1), strings(v, c, StrumCell.BASS)); assertEquals(listOf(1, 2, 3, 4, 5), strings(v, c, StrumCell.DOWN))
        assertEquals(listOf(2, 3, 4, 5), strings(v, c, StrumCell.DOWN_TREBLE)); assertEquals(listOf(5, 4, 3, 2), strings(v, c, StrumCell.UP))
        assertEquals(listOf(1, 2, 3, 4, 5), strings(v, c, StrumCell.MUTE)); assertEquals(emptyList<Int>(), strings(v, c, StrumCell.REST))
    }

    @Test fun rootStringMovesWithTheChord() {
        val (g, vg) = voicing("G")
        assertEquals(listOf(0), strings(vg, g, StrumCell.BASS)); assertEquals(listOf(0, 1, 2, 3, 4, 5), strings(vg, g, StrumCell.DOWN))
        assertEquals(listOf(2, 3, 4, 5), strings(vg, g, StrumCell.DOWN_TREBLE))
        val (d, vd) = voicing("D")
        assertEquals(listOf(2), strings(vd, d, StrumCell.BASS)); assertEquals(listOf(2, 3, 4, 5), strings(vd, d, StrumCell.DOWN))
        assertEquals(listOf(3, 4, 5), strings(vd, d, StrumCell.DOWN_TREBLE)); assertEquals(listOf(5, 4, 3), strings(vd, d, StrumCell.UP))
        val (a, va) = voicing("A")
        assertEquals(listOf(1), strings(va, a, StrumCell.BASS)); assertEquals(listOf(1, 2, 3, 4, 5), strings(va, a, StrumCell.DOWN))
    }

    @Test fun fullStrumSkipsStringsBelowTheRootString() {
        val c = Chord.of("C", ChordType.Major)!!
        val v = ChordVoicing(listOf(0, 3, 2, 0, 1, 0), listOf(0, 3, 2, 0, 1, 0), null, guitar.defaultTuning)
        assertEquals(1, RhythmStrum.rootString(v, c.root))
        assertEquals(listOf(1, 2, 3, 4, 5), strings(v, c, StrumCell.DOWN))
        assertEquals(listOf(0, 1, 2, 3, 4, 5), strings(v, c, StrumCell.MUTE))
        val (f, vf) = voicing("F")
        assertEquals(listOf(0), strings(vf, f, StrumCell.BASS)); assertEquals(listOf(0, 1, 2, 3, 4, 5), strings(vf, f, StrumCell.DOWN))
    }

    @Test fun stringsPerCellOnUkulele() {
        val (c, v) = voicing("C", inst = ukulele)
        assertEquals(1, RhythmStrum.rootString(v, c.root))
        assertEquals(listOf(1), strings(v, c, StrumCell.BASS)); assertEquals(listOf(0, 1, 2, 3), strings(v, c, StrumCell.DOWN))
        assertEquals(listOf(1, 2, 3), strings(v, c, StrumCell.DOWN_TREBLE)); assertEquals(listOf(3, 2, 1), strings(v, c, StrumCell.UP))
    }

    @Test fun playbackTimingsGainsAndMute() {
        val (c, v) = voicing("C")
        fun play(cell: StrumCell, velocity: Float = 1f) = RhythmStrum.playback(v, cell, c.root, velocity, Voice.GUITAR)
        val bass = play(StrumCell.BASS)
        assertEquals(1, bass.events.size); assertEquals("C3", bass.events[0].pitch.fullName); assertEquals(0.0, bass.events[0].time, 0.0)
        assertTrue(bass.events[0].gain > play(StrumCell.DOWN).events[0].gain); assertNull(bass.events[0].hold)
        for (cell in listOf(StrumCell.DOWN, StrumCell.DOWN_TREBLE, StrumCell.UP)) {
            val t = play(cell).events.map { it.time }
            for ((a, b) in t.zip(t.drop(1))) assertTrue("$cell", b - a in 0.008..0.015)
        }
        assertEquals(0, play(StrumCell.REST).events.size)
        assertTrue(play(StrumCell.MUTE).events.all { it.hold != null })
        assertEquals(RhythmStrum.MUTED_TAIL, play(StrumCell.MUTE).tail, 0.0)
        val soft = play(StrumCell.DOWN, 0.5f).events[0].gain; val normal = play(StrumCell.DOWN).events[0].gain
        assertEquals(2.0, normal / soft.toDouble(), 0.01)
        assertEquals(1.6, play(StrumCell.DOWN, 99f).events[0].gain / normal.toDouble(), 0.01)
        assertTrue(play(StrumCell.DOWN, -3f).events[0].gain > 0)
        assertTrue(play(StrumCell.UP).events[0].gain < normal)
        // 上扫音高从高到低
        val up = play(StrumCell.UP).events.map { it.pitch.midi }
        assertEquals(up.sortedDescending(), up)
    }

    @Test fun customInputParsing() {
        for (text in listOf("D.DU.UDU", "D . D U . U D U", "B.D.B.D.", "dUdU")) assertTrue(text, StrumInput.parse(text, 2).isValid)
        assertEquals("D.DU.UDU", StrumInput.parse("D-DU-UDU", 2).normalized)
        // 智能标点替换后的写法
        assertEquals(listOf(StrumCell.DOWN, StrumCell.REST, StrumCell.REST, StrumCell.UP), StrumInput.parse("D–U", 2).cells)
        assertEquals(listOf(StrumCell.DOWN, StrumCell.REST, StrumCell.REST, StrumCell.REST), StrumInput.parse("D…", 2).cells)
        assertEquals(StrumParse.Failure.EMPTY, StrumInput.parse("   ", 2).failure)
        assertEquals(StrumParse.Failure.INVALID_CHARACTERS, StrumInput.parse("DQU", 2).failure)
        assertEquals(StrumParse.Failure.NOT_WHOLE_BEATS, StrumInput.parse("DUD", 2).failure)
        assertEquals(StrumParse.Failure.TOO_LONG, StrumInput.parse("D".repeat(18), 2).failure)
        assertTrue(StrumInput.parse("D".repeat(16), 2).isValid)
        assertFalse(StrumInput.parse("D".repeat(33), 4).isValid)
    }
}

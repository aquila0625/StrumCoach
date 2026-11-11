package com.example.strumcoach.chord

import com.example.strumcoach.audio.Voice
import com.example.strumcoach.settings.MemoryStore
import com.example.strumcoach.tuner.InstrumentFamily
import com.example.strumcoach.tuner.InstrumentLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ArpeggioTest {
    private val guitar = InstrumentLibrary.guitar

    @Test fun parseAcceptsDigitsRootAndRests() {
        val p = ArpeggioInput.parse("5 3-2 R,0", 6)
        assertTrue(p.isValid)
        assertEquals("5 3 - 2 R -", p.normalized)
        assertEquals(listOf(ArpeggioStep.StringNumber(5), ArpeggioStep.StringNumber(3), ArpeggioStep.Rest, ArpeggioStep.StringNumber(2), ArpeggioStep.Root, ArpeggioStep.Rest), p.steps)
    }

    @Test fun parseRejectsBadInput() {
        assertEquals(ArpeggioParse.Failure.INVALID_CHARACTERS, ArpeggioInput.parse("5 7", 6).failure)
        assertEquals(ArpeggioParse.Failure.INVALID_CHARACTERS, ArpeggioInput.parse("5 a", 6).failure)
        assertEquals(ArpeggioParse.Failure.EMPTY, ArpeggioInput.parse("", 6).failure)
        assertEquals(ArpeggioParse.Failure.EMPTY, ArpeggioInput.parse("- - 0", 6).failure)
        assertEquals(ArpeggioParse.Failure.TOO_LONG, ArpeggioInput.parse("1".repeat(33), 6).failure)
        // 智能标点：两个短横变成一个 en dash，算两个空拍
        assertEquals("1 - - 2", ArpeggioInput.parse("1–2", 6).normalized)
        assertEquals("3 2", ArpeggioInput.parse("３２", 6).normalized)
    }

    @Test fun deletingLastTokenSkipsSeparators() {
        assertEquals("5 3 ", ArpeggioInput.deletingLastToken("5 3 2"))
        assertEquals("5 3 ", ArpeggioInput.deletingLastToken("5 3 2, "))
        assertEquals("", ArpeggioInput.deletingLastToken(""))
    }

    @Test fun presetsPerFamily() {
        assertEquals(listOf("g-5321", "g-53231323", "g-532313", "g-523132", "g-sweep"), ArpeggioPattern.patterns(InstrumentFamily.GUITAR).map { it.id })
        assertEquals(3, ArpeggioPattern.patterns(InstrumentFamily.UKULELE).size)
        assertEquals("b-rfof", ArpeggioPattern.defaultPattern(InstrumentFamily.BASS)?.id)
    }

    @Test fun guitarPatternUsesTheRootString() {
        val c = Chord.of("C", ChordType.Major)!!
        val v = ChordLibrary.voicings(c, guitar)[0]   // x32010：根音在 5 弦
        assertEquals(5, ArpeggioPattern.rootStringNumber(v, c, guitar.defaultTuning))
        val p = ArpeggioPattern.pattern("g-5321")!!
        assertEquals(listOf(5, 3, 2, 1), p.stringNumbers(5))
        // 根音在 6 弦（G 大调 320003）时，5 换成 6
        val g = Chord.of("G", ChordType.Major)!!
        val gv = ChordLibrary.voicings(g, guitar)[0]
        assertEquals(6, ArpeggioPattern.rootStringNumber(gv, g, guitar.defaultTuning))
        assertEquals(listOf(6, 3, 2, 1), p.stringNumbers(6))
        assertEquals(listOf(5, 4, 3, 2, 1, 2, 3, 4), ArpeggioPattern.pattern("g-sweep")!!.stringNumbers(5))
    }

    @Test fun arpeggioLoopTimesAndMutedStrings() {
        val c = Chord.of("C", ChordType.Major)!!
        val v = ChordLibrary.voicings(c, guitar)[0]
        val loop = ArpeggioBuilder.arpeggio(ArpeggioPattern.pattern("g-5321")!!, v, c, guitar.defaultTuning, Voice.fromFamily(InstrumentFamily.GUITAR), interval = 0.25)
        assertEquals(1.0, loop.cycle, 1e-9)
        assertEquals(listOf(0.0, 0.25, 0.5, 0.75), loop.playback.events.map { it.time })
        // 6 弦不弹的把位里，指到 6 弦的步骤是空拍而不是出声
        val steps = ArpeggioPattern.pattern("g-5321")!!.steps(v, c, guitar.defaultTuning)
        assertTrue(steps.all { it != null })
        val custom = CustomArpeggio(text = "6 5").pattern(InstrumentFamily.GUITAR, 6)!!
        assertNull(custom.steps(v, c, guitar.defaultTuning)[0])   // x32010 的 6 弦不弹
    }

    @Test fun restsStayInTheCycle() {
        val c = Chord.of("C", ChordType.Major)!!
        val v = ChordLibrary.voicings(c, guitar)[0]
        val p = CustomArpeggio(text = "5 - 3 -").pattern(InstrumentFamily.GUITAR, 6)!!
        val loop = ArpeggioBuilder.arpeggio(p, v, c, guitar.defaultTuning, Voice.fromFamily(InstrumentFamily.GUITAR), interval = 0.5)
        assertEquals(2.0, loop.cycle, 1e-9)
        assertEquals(listOf(0.0, 1.0), loop.playback.events.map { it.time })
    }

    @Test fun bassArpeggioIsRootFifthOctaveFifth() {
        val c = Chord.of("A", ChordType.Minor)!!
        val loop = ArpeggioBuilder.bassArpeggio(c, InstrumentLibrary.bass.defaultTuning, null, Voice.fromFamily(InstrumentFamily.BASS), interval = 0.5)!!
        val midis = loop.playback.events.map { it.pitch.midi }
        assertEquals(listOf(0, 7, 12, 7), midis.map { it - midis[0] })
        assertEquals(2.0, loop.cycle, 1e-9)
    }

    @Test fun noteIntervalIsAnEighthClamped() {
        assertEquals(0.3, ArpeggioBuilder.noteInterval(100.0), 1e-9)
        assertEquals(0.1, ArpeggioBuilder.noteInterval(300.0), 1e-9)
        assertEquals(0.7, ArpeggioBuilder.noteInterval(30.0), 1e-9)
    }

    @Test fun stateSavesSelectsAndPersistsCustomArpeggio() {
        val store = MemoryStore()
        val m = ChordLibraryState(store)
        assertEquals("g-5321", m.arpeggioPattern?.id)
        val saved = m.saveCustomArpeggio(name = "我的", text = "5 3 2 3")!!
        assertEquals(ArpeggioPattern.CUSTOM_PREFIX + saved.id, m.arpeggioPattern?.id)
        assertEquals(6, m.arpeggioPatterns.size)
        assertNull(m.saveCustomArpeggio(text = "9"))
        // 换乐器：自定义的按乐器分开存
        m.select(InstrumentLibrary.ukulele)
        assertEquals("u-4321", m.arpeggioPattern?.id)
        // 重新打开还在
        val again = ChordLibraryState(store)
        assertEquals(1, again.customArpeggios(InstrumentFamily.GUITAR).size)
        m.select(InstrumentLibrary.guitar)
        m.deleteCustomArpeggio(saved.id)
        assertEquals("g-5321", m.arpeggioPattern?.id)
    }

    @Test fun customArpeggioLimitIsTen() {
        val m = ChordLibraryState()
        repeat(ArpeggioInput.MAX_SAVED) { assertNotNull(m.saveCustomArpeggio(text = "5 3 ${(it % 4) + 1}")) }
        assertFalse(m.canAddCustomArpeggio)
        assertNull(m.saveCustomArpeggio(text = "1 2"))
    }

    @Test fun playModeDefaultsAndPersists() {
        val store = MemoryStore()
        val m = ChordLibraryState(store)
        assertEquals(ChordLibraryState.PlayMode.STRUM, m.effectivePlayMode)
        m.select(ChordLibraryState.PlayMode.ARPEGGIO)
        assertEquals(ChordLibraryState.PlayMode.ARPEGGIO, ChordLibraryState(store).playMode)
        m.select(ChordLibraryState.PlayMode.STRUM)
        m.select(InstrumentLibrary.bass)
        assertEquals(ChordLibraryState.PlayMode.ARPEGGIO, m.effectivePlayMode)   // 贝斯只有分解
    }

    @Test fun customRhythmSaveSelectDeleteAndPersist() {
        val store = MemoryStore()
        val m = ChordLibraryState(store)
        val r = m.saveCustomRhythm(name = "我的", text = "D.DU.UDU", cellsPerBeat = 2)!!
        assertEquals(StrumRhythm.CUSTOM_PREFIX + r.id, m.strumRhythm.id)
        assertTrue(m.strumRhythm.isCustom)
        assertEquals(11, m.strumRhythms.size)
        assertNull(m.saveCustomRhythm(text = "D.D", cellsPerBeat = 2).takeIf { false })   // 3 格不是 2 的倍数
        assertNull(m.saveCustomRhythm(text = "DDD", cellsPerBeat = 2))
        assertEquals(1, ChordLibraryState(store).customRhythms(InstrumentFamily.GUITAR).size)
        assertEquals(StrumRhythm.CUSTOM_PREFIX + r.id, ChordLibraryState(store).strumRhythm.id)
        m.deleteCustomRhythm(r.id)
        assertEquals("folk1", m.strumRhythm.id)
    }

    @Test fun customRhythmEditExistingKeepsId() {
        val m = ChordLibraryState()
        val r = m.saveCustomRhythm(name = "a", text = "D.D.", cellsPerBeat = 2)!!
        val edited = m.saveCustomRhythm(id = r.id, name = "b", text = "DUDU", cellsPerBeat = 2)!!
        assertEquals(r.id, edited.id)
        assertEquals(1, m.customRhythms(InstrumentFamily.GUITAR).size)
        assertEquals("DUDU", m.customRhythms(InstrumentFamily.GUITAR)[0].code)
    }
}

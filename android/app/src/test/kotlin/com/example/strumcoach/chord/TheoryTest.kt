package com.example.strumcoach.chord

import com.example.strumcoach.tuner.NoteNaming
import com.example.strumcoach.tuner.Pitch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TheoryTest {
    private val letters = NoteNaming.Letters

    private fun tones(root: String, type: ChordType) = Chord.of(root, type)!!.toneNames

    @Test fun twelveRootsAndTenTypes() {
        assertEquals(listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"), ChordRoot.names)
        assertEquals(
            listOf("major", "minor", "dom7", "maj7", "m7", "sus2", "sus4", "dim", "aug", "add9"),
            ChordType.builtins.map { it.id },
        )
    }

    @Test fun toneSpelling() {
        assertEquals(listOf("C", "E", "G"), tones("C", ChordType.Major))
        assertEquals(listOf("C", "D#", "G"), tones("C", ChordType.Minor))
        assertEquals(listOf("C", "E", "G", "A#"), tones("C", ChordType.Dominant7))
        assertEquals(listOf("C", "E", "G", "B"), tones("C", ChordType.Major7))
        assertEquals(listOf("A", "C", "E", "G"), tones("A", ChordType.Minor7))
        assertEquals(listOf("D", "E", "A"), tones("D", ChordType.Sus2))
        assertEquals(listOf("D", "G", "A"), tones("D", ChordType.Sus4))
        assertEquals(listOf("B", "D", "F"), tones("B", ChordType.Diminished))
        assertEquals(listOf("C", "E", "G#"), tones("C", ChordType.Augmented))
        assertEquals(listOf("C", "E", "G", "D"), tones("C", ChordType.Add9))
        assertEquals(listOf("A#", "D", "F"), tones("A#", ChordType.Major))
    }

    @Test fun namesAndParsing() {
        assertEquals("F#m7", Chord.of("F#", ChordType.Minor7)?.name)
        assertEquals("C", Chord.of("C", ChordType.Major)?.name)
        assertEquals("C#", Chord.of("Db", ChordType.Major)?.rootName)
        assertEquals("A#", Chord.of("B♭", ChordType.Minor)?.rootName)
        assertNull(Chord.of("H", ChordType.Major))
        assertEquals("B", Chord(-1, ChordType.Major).rootName)
    }

    @Test fun everyTypeStartsAtRootAndIsConsistent() {
        for (t in ChordType.builtins) {
            assertEquals(0, t.intervals.first())
            assertEquals(t.intervals.size, t.degrees.size)
            assertEquals("${t.id} 有重复音", t.intervals.size, t.intervals.map { it % 12 }.toSet().size)
            assertTrue(t.optionalIntervals.all { it in t.intervals })
        }
        assertEquals(ChordType.Major7, ChordType.byId("maj7"))
    }

    // 拼法 ------------------------------------------------------------

    @Test fun chordNamesFollowNoteNaming() {
        val italian = NoteNaming(NoteNaming.Style.SOLFEGE, "it")
        assertEquals("Rem", italian.chordName(Chord.of("D", ChordType.Minor)!!))
        assertEquals("Sol7", italian.chordName(Chord.of("G", ChordType.Dominant7)!!))
        assertEquals("Do", italian.chordName(Chord.of("C", ChordType.Major)!!))
        assertEquals(listOf("Do", "Mi", "Sol", "Si"), italian.toneNames(Chord.of("C", ChordType.Major7)!!))
        assertEquals("C♯m7", letters.chordName(Chord.of("C#", ChordType.Minor7)!!))
        val de = NoteNaming(NoteNaming.Style.LETTERS, "de")
        assertEquals("Hm", de.chordName(Chord.of("B", ChordType.Minor)!!))
        assertEquals(listOf("G", "H", "D"), de.toneNames(Chord.of("G", ChordType.Major)!!))
    }

    @Test fun typeButtonsUseStandardSymbolsWithTheRoot() {
        assertEquals(
            listOf("C", "Cm", "C7", "Cmaj7", "Cm7", "Csus2", "Csus4", "Cdim", "Caug", "Cadd9"),
            ChordType.builtins.map { letters.chordName(0, it) },
        )
        assertEquals(
            listOf("E♭", "E♭m", "E♭7", "E♭maj7", "E♭m7", "E♭sus2", "E♭sus4", "E♭dim", "E♭aug", "E♭add9"),
            ChordType.builtins.map { letters.chordName(3, it) },
        )
        assertEquals("F♯m", letters.chordName(6, ChordType.Minor))
        assertEquals("Rém", NoteNaming(NoteNaming.Style.SOLFEGE, "fr").chordName(2, ChordType.Minor))
        assertEquals("Do♯maj7", NoteNaming(NoteNaming.Style.SOLFEGE, "it").chordName(1, ChordType.Major7))
        assertEquals("B", NoteNaming(NoteNaming.Style.LETTERS, "de").chordName(10, ChordType.Major))
        assertEquals("Hm", NoteNaming(NoteNaming.Style.LETTERS, "de").chordName(11, ChordType.Minor))
    }

    @Test fun rootsUseOneCommonSpelling() {
        assertEquals(
            listOf("C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"),
            ChordRoot.all.map { letters.rootName(it) },
        )
        val italian = NoteNaming(NoteNaming.Style.SOLFEGE, "it")
        assertEquals(
            listOf("Do", "Do♯", "Re", "Mi♭", "Mi", "Fa", "Fa♯", "Sol", "La♭", "La", "Si♭", "Si"),
            ChordRoot.all.map { pc -> italian.rootName(pc) },
        )
        val de = NoteNaming(NoteNaming.Style.LETTERS, "de")
        assertEquals("B", de.rootButtonName(10))
        assertEquals("H", de.rootButtonName(11))
        assertEquals(listOf("C♯", "E♭", "F♯", "A♭"), listOf(1, 3, 6, 8).map { de.rootName(it) })
    }

    @Test fun blackKeyChordsUseTheSameSpellingEverywhere() {
        val cases = listOf(
            Triple(3, ChordType.Major, listOf("E♭", "G", "B♭")), Triple(8, ChordType.Major, listOf("A♭", "C", "E♭")),
            Triple(10, ChordType.Major, listOf("B♭", "D", "F")), Triple(6, ChordType.Major, listOf("F♯", "A♯", "C♯")),
            Triple(1, ChordType.Minor, listOf("C♯", "E", "G♯")), Triple(8, ChordType.Minor, listOf("A♭", "B", "E♭")),
        )
        for ((root, type, tones) in cases) {
            val chord = Chord(root, type)
            assertEquals(chord.name, tones, letters.toneNames(chord))
            assertEquals(tones[0], letters.rootName(chord))
            assertEquals(tones[0] + type.symbol, letters.chordName(chord))
            for ((pc, name) in chord.pitchClasses.zip(tones)) assertEquals(name, letters.toneName(pc, chord))
        }
    }

    @Test fun toneSpellingMatchesTheRoot() {
        fun t(root: String, type: ChordType) = letters.toneNames(Chord.of(root, type)!!)
        assertEquals(listOf("E♭", "G", "B♭"), t("Eb", ChordType.Major))
        assertEquals(listOf("E♭", "G", "B♭", "D♭"), t("Eb", ChordType.Dominant7))
        assertEquals(listOf("B♭", "D", "F", "A"), t("Bb", ChordType.Major7))
        assertEquals(listOf("A♭", "B", "E♭"), t("Ab", ChordType.Minor))          // 不写 C♭
        assertEquals(listOf("F♯", "A♯", "C♯"), t("F#", ChordType.Major))
        assertEquals(listOf("F♯", "A", "C♯", "E"), t("F#", ChordType.Minor7))
        assertEquals(listOf("F", "A♭", "C"), t("F", ChordType.Minor))
        assertEquals(listOf("D", "F", "A"), t("D", ChordType.Minor))
        assertEquals(listOf("G", "B", "D", "F"), t("G", ChordType.Dominant7))
        // 少见写法（E♯、F♭）退回统一的升号或降号
        assertEquals(listOf("C♯", "F", "G♯"), t("C#", ChordType.Major))
        assertEquals(listOf("B♭", "D♭", "E"), t("Bb", ChordType.Diminished))
    }

    @Test fun spellingIsConsistentForEveryChord() {
        for (root in ChordRoot.all) for (type in ChordType.builtins) {
            val chord = Chord(root, type)
            assertEquals(type.intervals.size, ChordSpelling.flats(chord).size)
            val names = letters.toneNames(chord)
            for ((name, pc) in names.zip(chord.pitchClasses)) {
                assertEquals("${chord.name} 的 $name 音级不对", pc, Pitch.parse(name + "4")?.pitchClass)
                assertFalse(name.contains("♯♯") || name.contains("♭♭"))
            }
            val marks = names.flatMap { n -> n.filter { it == '♯' || it == '♭' }.toList() }.toSet()
            if (type.id != ChordType.Augmented.id) {
                assertTrue("${chord.name} 同时有升号和降号：$names", marks.size <= 1)
            }
            assertEquals(letters.rootName(chord), names[0])
        }
    }

    @Test fun solfegeAndGermanToneNames() {
        assertEquals(
            listOf("Mi♭", "Sol", "Si♭"),
            NoteNaming(NoteNaming.Style.SOLFEGE, "fr").toneNames(Chord.of("Eb", ChordType.Major)!!),
        )
        val de = NoteNaming(NoteNaming.Style.LETTERS, "de")
        assertEquals(listOf("B", "D", "F"), de.toneNames(Chord.of("Bb", ChordType.Major)!!))
        assertEquals(listOf("G", "B", "D"), de.toneNames(Chord.of("G", ChordType.Minor)!!))
    }

    // 收藏 -------------------------------------------------------------

    @Test fun favoritesToggleAndOrder() {
        val f = ChordFavorite("guitar", "standard", 0, "maj7", 1)
        val g = ChordFavorite("ukulele", "highG", 9, "minor", 0)
        var favs = ChordFavorites().toggle(f)
        favs = favs.add(g).add(g)
        assertEquals(listOf(g, f), favs.items)
        assertEquals("Cmaj7", favs.items[1].chord?.name)
        val removed = favs.toggle(f)
        assertFalse(f in removed)
        assertNotNull(favs.items[0].chord)
    }
}

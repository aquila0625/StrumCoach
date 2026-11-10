package com.example.tunebeatchord.chord

import com.example.tunebeatchord.tuner.Instrument
import com.example.tunebeatchord.tuner.InstrumentLibrary
import com.example.tunebeatchord.tuner.Pitch
import com.example.tunebeatchord.tuner.Tuning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoicingTest {
    private val guitar = InstrumentLibrary.guitar
    private val ukulele = InstrumentLibrary.ukulele

    private fun first(root: String, type: ChordType, inst: Instrument) =
        ChordLibrary.voicings(Chord.of(root, type)!!, inst)[0]

    @Test fun standardGuitarShapes() {
        val expected = listOf(
            Triple("C", ChordType.Major, listOf("x32010")), Triple("G", ChordType.Major, listOf("320003", "320033")),
            Triple("D", ChordType.Major, listOf("xx0232")), Triple("A", ChordType.Major, listOf("x02220")),
            Triple("E", ChordType.Major, listOf("022100")), Triple("A", ChordType.Minor, listOf("x02210")),
            Triple("E", ChordType.Minor, listOf("022000")), Triple("D", ChordType.Minor, listOf("xx0231")),
            Triple("F", ChordType.Major, listOf("133211")), Triple("C", ChordType.Major7, listOf("x32000")),
            Triple("G", ChordType.Dominant7, listOf("320001")), Triple("B", ChordType.Minor, listOf("x24432")),
            Triple("F#", ChordType.Minor, listOf("244222")), Triple("B", ChordType.Major, listOf("x24442")),
            Triple("D", ChordType.Dominant7, listOf("xx0212")), Triple("E", ChordType.Dominant7, listOf("020100")),
            Triple("A", ChordType.Dominant7, listOf("x02020")), Triple("A", ChordType.Minor7, listOf("x02010")),
            Triple("D", ChordType.Minor7, listOf("xx0211")),
        )
        for ((root, type, shapes) in expected) {
            val v = first(root, type, guitar)
            assertTrue("吉他 $root${type.symbol} 第一个把位是 ${v.shorthand}，应为 $shapes", v.shorthand in shapes)
        }
    }

    @Test fun standardUkuleleShapes() {
        val expected = listOf(
            Triple("C", ChordType.Major, "0003"), Triple("G", ChordType.Major, "0232"),
            Triple("A", ChordType.Minor, "2000"), Triple("F", ChordType.Major, "2010"),
            Triple("D", ChordType.Major, "2220"), Triple("E", ChordType.Minor, "0432"),
            Triple("D", ChordType.Minor, "2210"), Triple("G", ChordType.Dominant7, "0212"),
            Triple("C", ChordType.Dominant7, "0001"), Triple("A", ChordType.Dominant7, "0100"),
        )
        for ((root, type, shape) in expected) assertEquals("尤克里里 $root${type.symbol}", shape, first(root, type, ukulele).shorthand)
    }

    @Test fun standardFingerings() {
        assertEquals(listOf(0, 3, 2, 0, 1, 0), first("C", ChordType.Major, guitar).fingers)
        assertEquals(listOf(2, 1, 0, 0, 0, 3), first("G", ChordType.Major, guitar).fingers)
        assertEquals(listOf(0, 0, 2, 3, 1, 0), first("A", ChordType.Minor, guitar).fingers)
        assertEquals(listOf(0, 2, 3, 1, 0, 0), first("E", ChordType.Major, guitar).fingers)
        assertEquals(listOf(0, 0, 0, 1, 3, 2), first("D", ChordType.Major, guitar).fingers)
        assertEquals(listOf(0, 3, 2, 0, 0, 0), first("C", ChordType.Major7, guitar).fingers)
        assertEquals(listOf(0, 2, 3, 0, 0, 0), first("E", ChordType.Minor, guitar).fingers)
        assertEquals(listOf(0, 0, 0, 3), first("C", ChordType.Major, ukulele).fingers)
        assertEquals(listOf(2, 0, 0, 0), first("A", ChordType.Minor, ukulele).fingers)
        assertEquals(listOf(2, 0, 1, 0), first("F", ChordType.Major, ukulele).fingers)
    }

    @Test fun fMajorIsABarreChord() {
        val f = first("F", ChordType.Major, guitar)
        assertEquals("133211", f.shorthand)
        val b = f.barre!!
        assertEquals(1, b.fret)
        assertEquals(0, b.fromString)
        assertEquals(5, b.toString)
        assertEquals(listOf(1, 3, 4, 2, 1, 1), f.fingers)
        assertEquals(listOf("F", "C", "F", "A", "C", "F"), f.noteNames)
        assertTrue(f.showsNut)
        assertEquals(4, f.fingerCount)
    }

    @Test fun noteNamesPerString() {
        assertEquals(listOf("", "C", "E", "G", "B", "E"), first("C", ChordType.Major7, guitar).noteNames)
        assertEquals(listOf("G", "C", "E", "C"), first("C", ChordType.Major, ukulele).noteNames)
        assertEquals(listOf("", "A", "E", "A", "C", "E"), first("A", ChordType.Minor, guitar).noteNames)
    }

    @Test fun highPositionShowsFretNumber() {
        val list = ChordLibrary.voicings(Chord.of("F#", ChordType.Major)!!, guitar)
        val high = list.first { it.minFret >= 6 }
        assertEquals(high.minFret, high.baseFret)
        assertFalse(high.showsNut)
    }

    /** 独立于生成器的校验：规则写在这里再核对一遍。 */
    private fun assertValid(v: ChordVoicing, chord: Chord, tuning: Tuning, minSounding: Int) {
        val label = "${tuning.id} ${chord.name} ${v.shorthand}"
        assertEquals(label, tuning.stringCount, v.frets.size)
        assertTrue("$label 跨度过大", v.span <= 3)
        assertTrue("$label 手指超过 4 根", v.fingerCount <= 4)
        for ((fret, finger) in v.frets.zip(v.fingers)) {
            if (fret > 0) assertTrue("$label 按弦没有手指", finger in 1..4) else assertEquals("$label 空弦不该有手指", 0, finger)
        }
        for (finger in 1..4) {
            val idx = v.fingers.indices.filter { v.fingers[it] == finger }
            assertTrue("$label 一根手指按了两个品", idx.map { v.frets[it] }.toSet().size <= 1)
            if (idx.size > 1) {
                val b = v.barre
                assertEquals("$label 一根手指按多根弦但没有横按", finger, b?.finger)
                assertTrue(label, idx.all { it >= b!!.fromString && it <= b.toString })
            }
        }
        v.barre?.let { b ->
            assertEquals(label, v.minFret, b.fret)
            for (s in b.fromString..b.toString) assertTrue("$label 横按下有空弦", v.frets[s] >= b.fret)
        }
        val sounding = v.soundingStrings
        assertFalse(label, sounding.isEmpty())
        assertEquals("$label 中间有不弹的弦", sounding.size, sounding.last() - sounding.first() + 1)
        assertTrue(label, sounding.size >= minSounding)
        val allowed = chord.pitchClasses.toSet()
        val heard = HashSet<Int>()
        for ((i, p) in v.pitches.withIndex()) {
            if (v.frets[i] < 0) {
                assertNull(label, p); continue
            }
            val pitch = tuning.strings[i].pitch.transposed(v.frets[i])
            assertEquals(label, pitch, p)
            assertTrue("$label 第 $i 弦的 ${pitch.name} 不是和弦音", pitch.pitchClass in allowed)
            heard.add(pitch.pitchClass)
            assertEquals(label, ChordRoot.name(pitch.pitchClass), v.noteNames[i])
        }
        assertTrue("$label 没有根音", chord.root in heard)
        val optional = chord.type.optionalIntervals.map { (chord.root + it) % 12 }.toSet()
        for (pc in allowed) if (pc !in heard) assertTrue("$label 缺少 ${ChordRoot.name(pc)}", pc in optional)
    }

    @Test fun everyVoicingOnEveryInstrumentIsValid() {
        var total = 0
        for (inst in listOf(guitar, ukulele)) {
            val tuning = inst.defaultTuning
            val rules = VoicingRules.forFamily(inst.family)!!
            for (root in ChordRoot.all) for (type in ChordType.builtins) {
                val chord = Chord(root, type)
                val list = ChordLibrary.voicings(chord, inst)
                assertFalse("${inst.id} ${chord.name} 没有生成任何按法", list.isEmpty())
                for (v in list) {
                    assertValid(v, chord, tuning, rules.minSounding); total++
                }
                assertEquals("${inst.id} ${chord.name} 有重复按法", list.size, list.map { it.frets }.toSet().size)
                assertTrue(list.size <= ChordLibrary.MAX_VOICINGS)
            }
        }
        assertTrue(total > 1500)
    }

    @Test fun everyCombinationAlsoWorksInOtherTunings() {
        for (inst in listOf(guitar, ukulele)) {
            val rules = VoicingRules.forFamily(inst.family)!!
            for (tuning in inst.tunings) for (root in ChordRoot.all) for (type in ChordType.builtins) {
                val chord = Chord(root, type)
                val list = ChordLibrary.voicings(chord, inst, tuning)
                assertFalse("${inst.id}/${tuning.id} ${chord.name}", list.isEmpty())
                for (v in list) assertValid(v, chord, tuning, rules.minSounding)
            }
        }
    }

    @Test fun guitarRootInBassFirst() {
        for (root in ChordRoot.all) for (type in ChordType.builtins) {
            val chord = Chord(root, type)
            val list = ChordLibrary.voicings(chord, guitar)
            assertTrue("吉他 ${chord.name} 第一个把位 ${list[0].shorthand} 的最低音不是根音", VoicingGenerator.rootInBass(list[0], chord))
        }
    }

    @Test fun generatedPartIsSortedByTheKey() {
        for (inst in listOf(guitar, ukulele)) {
            val rules = VoicingRules.forFamily(inst.family)!!
            for (root in ChordRoot.all) for (type in ChordType.builtins) {
                val chord = Chord(root, type)
                val list = ChordLibrary.voicings(chord, inst)
                val curated = CuratedShapes.shapes(inst.id, inst.defaultTuningID, chord).size
                val keys = list.drop(curated).map { VoicingGenerator.sortKey(it, chord, rules) }
                for ((a, b) in keys.zip(keys.drop(1))) {
                    val cmp = a.zip(b).firstOrNull { it.first != it.second }?.let { it.first.compareTo(it.second) } ?: 0
                    assertTrue("${inst.id} ${chord.name} 排序不对", cmp <= 0)
                }
            }
        }
    }

    @Test fun openPositionComesFirstForCommonChords() {
        for ((chord, inst) in listOf(
            Chord.of("C", ChordType.Major)!! to guitar, Chord.of("G", ChordType.Major)!! to ukulele,
            Chord.of("E", ChordType.Minor)!! to guitar,
        )) assertTrue("${chord.name} 第一个应是开放把位", ChordLibrary.voicings(chord, inst)[0].isOpenPosition)
    }

    @Test fun curatedShapesAreAllAccepted() {
        val tables = mapOf(
            "guitar/standard" to Pair(guitar, guitar.tuning("standard")!!),
            "ukulele/highG" to Pair(ukulele, ukulele.tuning("highG")!!),
        )
        var checked = 0
        for ((_, pair) in tables) {
            val (inst, tuning) = pair
            val rules = VoicingRules.forFamily(inst.family)!!
            for (type in ChordType.builtins) for (root in ChordRoot.names) {
                val chord = Chord.of(root, type)!!
                for (text in CuratedShapes.shapes(inst.id, tuning.id, chord)) {
                    val frets = CuratedShapes.parse(text)
                    assertNotNull("${inst.id} ${chord.name} $text 无法解析", frets)
                    assertNotNull("${inst.id} ${chord.name} 的人工按法 $text 不合格",
                        VoicingGenerator.makeVoicing(frets!!, chord, tuning, rules))
                    checked++
                }
                // 人工按法排在最前面，且顺序保持
                val shapes = CuratedShapes.shapes(inst.id, tuning.id, chord)
                if (shapes.isNotEmpty()) {
                    assertEquals(shapes, ChordLibrary.voicings(chord, inst, tuning).take(shapes.size).map { it.shorthand })
                }
            }
        }
        assertTrue(checked > 100)
    }

    @Test fun ukuleleMayDropTheFifthButPrefersComplete() {
        for (root in ChordRoot.all) for (type in listOf(ChordType.Dominant7, ChordType.Major7, ChordType.Minor7)) {
            val chord = Chord(root, type)
            val flags = ChordLibrary.voicings(chord, ukulele).map { VoicingGenerator.omitsOptional(it, chord) }
            val firstOmit = flags.indexOf(true)
            if (firstOmit >= 0) assertFalse("${chord.name} 完整按法排在了省略五度的后面", flags.drop(firstOmit).contains(false))
        }
    }

    @Test fun unsupportedInstrumentsReturnNothing() {
        val c = Chord.of("C", ChordType.Major)!!
        assertTrue(ChordLibrary.voicings(c, InstrumentLibrary.violin).isEmpty())
        assertTrue(ChordLibrary.voicings(c, InstrumentLibrary.bass).isEmpty())
        assertFalse(ChordLibrary.supportsFingering(InstrumentLibrary.bass))
        assertTrue(ChordLibrary.supportsFingering(guitar))
        assertEquals(listOf("guitar", "ukulele"), ChordLibrary.strummableInstruments.map { it.id })
    }

    @Test fun barreFingerAssigner() {
        assertNull(FingerAssigner.assign(listOf(-1, 3, 2, 0, 1, 0))!!.barre)
        assertNotNull(FingerAssigner.assign(listOf(1, 3, 3, 2, 1, 1))?.barre)
        assertNull(FingerAssigner.assign(listOf(1, 0, 3, 2, 1, 1)))
        assertNull(FingerAssigner.assign(listOf(1, 2, 3, 4, 5, 0)))
    }

    // 贝斯 -------------------------------------------------------------

    private val bass4 = InstrumentLibrary.bass.defaultTuning
    private val bass5 = InstrumentLibrary.bass.tunings[1]

    @Test fun bassCMajorPositions() {
        val p = BassPositions.make(Chord.of("C", ChordType.Major)!!, bass4)!!
        val anchor = p.anchor!!
        assertEquals(1, anchor.string)
        assertEquals(3, anchor.fret)
        assertEquals(Pitch.parse("C2"), anchor.pitch)
        assertEquals(2, p.startFret)
        assertFalse(p.showsNut)
        assertEquals(5, p.fretCount)
        assertTrue(p.markers(BassPositions.Role.THIRD).any { it.pitch.pitchClass == 4 })
        assertTrue(p.markers(BassPositions.Role.FIFTH).any { it.pitch.pitchClass == 7 })
        assertTrue(p.markers.any { it.role == BassPositions.Role.OCTAVE && it.string == 3 && it.fret == 5 && it.pitch == Pitch.parse("C3") })
    }

    @Test fun bassOpenStringRootShowsNut() {
        val p = BassPositions.make(Chord.of("E", ChordType.Minor)!!, bass4)!!
        assertTrue(p.showsNut)
        assertEquals(0, p.anchor?.fret)
        assertTrue(p.markers.any { it.fret == 0 && it.role == BassPositions.Role.ROOT && it.string == 0 })
        assertTrue(p.markers.any { it.role == BassPositions.Role.FIFTH && it.string == 1 && it.fret == 2 })
    }

    @Test fun everyBassMarkerIsAChordToneInsideTheFrame() {
        for (tuning in listOf(bass4, bass5)) for (root in ChordRoot.all) for (type in ChordType.builtins) {
            val chord = Chord(root, type)
            val p = BassPositions.make(chord, tuning)!!
            assertNotNull(chord.name, p.anchor)
            assertEquals(BassPositions.Role.ROOT, p.anchor?.role)
            assertEquals(tuning.stringCount, p.stringCount)
            val lo = if (p.showsNut) 0 else p.firstRow
            val hi = p.firstRow + p.fretCount - 1
            val tones = chord.pitchClasses.toSet()
            for (m in p.markers) {
                assertTrue("${chord.name} 标记超出把位框", m.fret in lo..hi)
                assertTrue(m.pitch.pitchClass in tones)
                assertEquals(tuning.strings[m.string].pitch.transposed(m.fret), m.pitch)
            }
            for (role in listOf(BassPositions.Role.ROOT, BassPositions.Role.THIRD, BassPositions.Role.FIFTH, BassPositions.Role.OCTAVE)) {
                assertFalse("${chord.name} 框里没有 $role", p.markers(role).isEmpty())
            }
        }
    }

    @Test fun chromaticTuningHasNoBassPositions() {
        assertNull(BassPositions.make(Chord.of("C", ChordType.Major)!!, InstrumentLibrary.auto.defaultTuning))
    }
}

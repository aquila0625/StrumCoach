package com.example.strumcoach.chord

import com.example.strumcoach.tuner.InstrumentLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 全量审核和弦库的按法：吉他、尤克里里的每种定弦 × 12 个根音 × 10 种类型。
 * 1. 品位和顺序与 iOS 版（ChordKit）逐条一致：基准文件 resources/chord/ios_voicing_frets.txt 由 iOS 的 ChordLibrary 导出；
 * 2. 乐理：只含和弦音，根音、三度都在；
 * 3. 按法：跨度不超过 3 品、中间不夹不弹的弦、每个按弦的音都有手指、同一根手指不按两个品、
 *    低品用的手指号不大于高品、横按范围里没有比横按品更低的弦。
 */
class VoicingAuditTest {
    private val instruments = listOf(InstrumentLibrary.guitar, InstrumentLibrary.ukulele)

    private fun all() = sequence {
        for (inst in instruments) for (tuning in inst.tunings) for (root in 0 until 12) for (type in ChordType.builtins) {
            val chord = Chord(root, type)
            yield(Triple("${inst.id}/${tuning.id}/$root/${type.id}", chord, ChordLibrary.voicings(chord, inst, tuning)))
        }
    }

    @Test fun fretsAndOrderMatchIos() {
        val expected = javaClass.getResource("/chord/ios_voicing_frets.txt")!!.readText().trim().lines()
        val actual = ArrayList<String>()
        for ((key, _, list) in all()) {
            list.forEachIndexed { i, v -> actual.add("$key#$i ${v.frets.joinToString(",")}") }
            if (list.isEmpty()) actual.add("$key EMPTY")
        }
        assertEquals(expected.size, actual.size)
        val firstDiff = expected.indices.firstOrNull { expected[it] != actual[it] }
        assertEquals("第一处不同", firstDiff?.let { expected[it] }, firstDiff?.let { actual[it] })
    }

    @Test fun everyVoicingIsMusicallyAndPhysicallyValid() {
        val issues = ArrayList<String>()
        for ((key, chord, list) in all()) {
            if (list.isEmpty()) issues.add("$key 没有按法")
            val tones = chord.pitchClasses.toSet()
            val third = chord.type.intervals.firstOrNull { it == 3 || it == 4 }?.let { (chord.root + it) % 12 }
            list.forEachIndexed { k, v ->
                val id = "$key#$k ${v.frets} 指=${v.fingers}"
                val pcs = v.pitches.filterNotNull().map { it.pitchClass }
                if (pcs.any { it !in tones }) issues.add("$id 有和弦外音")
                if (chord.root !in pcs) issues.add("$id 缺根音")
                if (third != null && third !in pcs) issues.add("$id 缺三度")
                val sounding = v.soundingStrings
                for (i in sounding.first()..sounding.last()) if (v.frets[i] < 0) issues.add("$id 中间夹着不弹的弦")
                val fretted = v.frets.indices.filter { v.frets[it] > 0 }
                if (fretted.isNotEmpty()) {
                    if (fretted.maxOf { v.frets[it] } - fretted.minOf { v.frets[it] } > 3) issues.add("$id 跨度超过 3 品")
                    if (fretted.any { v.fingers[it] !in 1..4 }) issues.add("$id 有按弦的音没分配手指")
                    for ((f, strs) in fretted.groupBy { v.fingers[it] }) if (strs.map { v.frets[it] }.toSet().size > 1) issues.add("$id 手指 $f 按了两个品")
                    for (a in fretted) for (b in fretted) if (v.frets[a] < v.frets[b] && v.fingers[a] > v.fingers[b]) issues.add("$id 手指顺序反了")
                }
                v.barre?.let { b -> for (i in b.fromString..b.toString) if (v.frets[i] < b.fret) issues.add("$id 横按范围里有更低的弦") }
            }
        }
        assertTrue(issues.distinct().take(20).joinToString("\n"), issues.isEmpty())
    }

    @Test fun allOpenVoicingsAreKeptInEveryTuning() {
        // 移植时把“b = 0 只保留全空弦”的条件写反了，全空弦按法在非标准定弦里全丢了
        val lowG = InstrumentLibrary.ukulele.tunings.first { it.id == "lowG" }
        assertEquals(listOf(0, 0, 0, 0), ChordLibrary.voicings(Chord.of("A", ChordType.Minor7)!!, InstrumentLibrary.ukulele, lowG)[0].frets)
        val dadgad = InstrumentLibrary.guitar.tunings.first { it.id == "dadgad" }
        assertTrue(ChordLibrary.voicings(Chord.of("D", ChordType.Sus4)!!, InstrumentLibrary.guitar, dadgad).any { v -> v.frets.all { it == 0 } })
    }

    private fun first(inst: com.example.strumcoach.tuner.Instrument, name: String, type: ChordType) = ChordLibrary.voicings(Chord.of(name, type)!!, inst)[0]

    @Test fun smallBarresFollowStandardCharts() {
        val uke = InstrumentLibrary.ukulele
        val guitar = InstrumentLibrary.guitar
        fun check(v: ChordVoicing, frets: String, fingers: String, barre: Boolean) {
            assertEquals(frets, v.shorthand)
            assertEquals(fingers, v.fingers.joinToString(""))
            assertEquals(barre, v.barre != null)
        }
        check(first(uke, "B", ChordType.Minor7), "2222", "1111", true)
        check(first(uke, "D", ChordType.Dominant7), "2223", "1112", true)
        check(first(uke, "A#", ChordType.Major), "3211", "3211", true)
        check(first(uke, "B", ChordType.Major), "4322", "3211", true)
        check(first(uke, "G", ChordType.Minor7), "0211", "0211", true)
        check(first(uke, "D", ChordType.Major), "2220", "1230", false)          // 只有同品的三个音：仍是 1、2、3 指
        check(first(guitar, "D", ChordType.Minor7), "xx0211", "000211", true)
        check(first(guitar, "C", ChordType.Sus4), "x33011", "034011", true)
        check(first(guitar, "A", ChordType.Major), "x02220", "001230", false)
        // 小横按不改变“开放把位”的判定
        assertTrue(first(guitar, "D", ChordType.Minor7).isOpenPosition)
        assertFalse(first(uke, "B", ChordType.Minor7).isOpenPosition)
    }
}

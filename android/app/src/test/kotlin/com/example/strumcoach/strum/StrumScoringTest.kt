package com.example.strumcoach.strum

import com.example.strumcoach.chord.ChordType
import com.example.strumcoach.chord.StrumCell
import com.example.strumcoach.chord.StrumRhythm
import com.example.strumcoach.settings.MemoryStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun render(a: Advice?): String =
    a?.render { key, args -> var i = 0; Regex("%(?:\\d+\\$)?(@|lld|d|s)").replace(key) { args.getOrNull(i++).toString() } } ?: ""

class StrumScoringTest {
    private val tl = StrumTimeline(StrumRhythm.preset("folk1")!!, 90.0, 0.0, 2)

    @Test fun timelinePlacesStrokesOnEighths() {
        val t = StrumTimeline(StrumRhythm.preset("folk1")!!, 90.0, 10.0, 2)
        assertEquals(1.0 / 3, t.stepDuration, 1e-12)
        val s = t.strokes
        assertEquals(12, s.size)
        assertEquals(listOf(0, 2, 3, 5, 6, 7), s.take(6).map { it.step })
        assertEquals(10 + 2.0 / 3, s[1].time, 1e-12)
        assertEquals(1, s[6].bar); assertEquals(10 + t.barDuration, s[6].time, 1e-12)
        assertEquals(10 + 2 * t.barDuration, t.end, 1e-12)
        assertEquals(4, t.countInBeats.size); assertEquals(10 - 4 * (60.0 / 90), t.countInBeats.first(), 1e-12)
        assertEquals(1, t.position(10.4)?.second); assertNull(t.position(9.9)); assertNull(t.position(t.end))
        assertEquals(t.end, t.following().start, 0.0)
    }

    @Test fun sixteenthFunkTimeline() {
        val t = StrumTimeline(StrumRhythm.preset("funk")!!, 100.0, 0.0, 1)
        assertEquals(0.15, t.stepDuration, 1e-12); assertEquals(16, t.strokes.size)
    }

    @Test fun perfectTakeScores100() {
        val s = StrumScore.grade(tl, tl.strokes.map { it.time })
        assertEquals(100, s.score); assertEquals(12, s.good)
        assertEquals(0.0, s.meanOffsetMs!!, 1e-6); assertEquals(0.0, s.spreadMs!!, 1e-6)
    }

    /** 准、偏、漏、多扫各算一遍：±60 ms 内准，±120 ms 内偏，再远就漏；多出来的扣 0.5。 */
    @Test fun goodOffMissedAndExtra() {
        val onsets = tl.strokes.map { it.time }.toMutableList()
        onsets[0] += 0.055; onsets[1] -= 0.080; onsets[2] += 0.110; onsets[3] += 0.200
        onsets.removeAt(4)
        onsets.add(tl.strokes[6].time + 0.17)
        val s = StrumScore.grade(tl, onsets)
        assertEquals(listOf(StrumScore.Grade.GOOD, StrumScore.Grade.OFF, StrumScore.Grade.OFF, StrumScore.Grade.MISSED, StrumScore.Grade.MISSED), s.hits.take(5).map { it.grade })
        assertEquals(8, s.good); assertEquals(2, s.off); assertEquals(2, s.missed); assertEquals(2, s.extras.size)
        assertEquals(67, s.score)
        assertEquals(-0.080, s.hits[1].offset!!, 1e-9)
    }

    @Test fun onsetIsUsedOnlyOnce() {
        val funk = StrumTimeline(StrumRhythm.preset("funk")!!, 100.0, 0.0, 1)
        assertEquals(1, StrumScore.grade(funk, listOf(0.075)).hits.count { it.grade != StrumScore.Grade.MISSED })
    }

    @Test fun onsetsOutsideTheWindowAreIgnoredAndScoreClamps() {
        val s = StrumScore.grade(tl, listOf(-2.0, -0.5, tl.end + 1))
        assertEquals(0, s.extras.size); assertEquals(0, s.score)
        var t = 0.05; val noisy = ArrayList<Double>(); while (t < tl.end) { noisy.add(t); t += 0.09 }
        assertTrue(StrumScore.grade(tl, noisy).score in 0..100)
    }

    @Test fun guardsClaimNeighbourOnsets() {
        val onsets = tl.strokes.map { it.time } + listOf(tl.end - 0.05)
        assertEquals(1, StrumScore.grade(tl, onsets).extras.size)
        assertEquals(0, StrumScore.grade(tl, onsets, guards = listOf(tl.end)).extras.size)
    }

    @Test fun meanOffsetSpreadAndAdvice() {
        val late = StrumScore.grade(tl, tl.strokes.map { it.time + 0.05 })
        assertEquals(50.0, late.meanOffsetMs!!, 1e-6); assertEquals(0.0, late.spreadMs!!, 1e-6)
        assertTrue(render(late.advice), render(late.advice).contains("50"))
        val upLate = StrumScore.grade(tl, tl.strokes.map { it.time + if (it.stroke == StrumCell.UP) 0.04 else 0.0 })
        assertEquals(40.0, upLate.meanOffsetMs(StrumCell.UP)!!.first, 1e-6)
        assertTrue(render(upLate.advice), render(upLate.advice).contains("40"))
        assertTrue(render(StrumScore.grade(tl, tl.strokes.map { it.time }).advice).isNotEmpty())
        // 很多下没收到：先建议靠近手机
        val quiet = StrumScore.grade(tl, tl.strokes.take(3).map { it.time })
        assertEquals("很多下没有收到声音：把手机放近一点，扫得干脆一些，或者先在安静的地方练。", quiet.advice?.key)
        assertNull(StrumScore(emptyList(), emptyList()).advice)
    }

    // 和弦进行 ----------------------------------------------------------

    private fun prog(items: List<Triple<Int, ChordType, Int>>) =
        ChordProgression(name = "t", chords = items.map { ProgressionChord(it.first, it.second, it.third) })

    @Test fun editingOperations() {
        var p = prog(listOf(Triple(0, ChordType.Major, 1), Triple(7, ChordType.Major, 1), Triple(9, ChordType.Minor, 1)))
        val ids = p.chords.map { it.id }
        p = p.move(ids[2], ids[0]); assertEquals(listOf(ids[2], ids[0], ids[1]), p.chords.map { it.id })
        p = p.update(p.chords[0].copy(bars = 4)); assertEquals(4, p.chords[0].bars); assertEquals(6, p.totalBars)
        val (dup, newId) = p.duplicate(ids[0])!!
        assertEquals(4, dup.chords.size); assertEquals(newId, dup.chords[2].id); assertTrue(dup.chords[1].sameChord(dup.chords[2]))
        var one = prog(listOf(Triple(0, ChordType.Major, 1)))
        one = one.delete(one.chords[0].id); assertEquals(1, one.chords.size)
        assertEquals(2, p.delete(ids[1]).chords.size)
        assertEquals("C–G–Am", prog(listOf(Triple(0, ChordType.Major, 1), Triple(7, ChordType.Major, 1), Triple(9, ChordType.Minor, 1))).label { it.name })
    }

    @Test fun presets() {
        val p = ChordProgression.presets
        assertEquals(6, p.size)
        assertEquals(listOf("C–G–Am–F", "G–D–Em–C", "Am–F–C–G", "D–A–Bm–G", "C–Am–F–G"), p.take(5).map { it.name })
        for (x in p.take(5)) assertEquals(x.name, x.label { it.name })
        val blues = p[5]
        assertEquals(12, blues.totalBars); assertEquals(listOf("A7", "D7", "A7", "E7", "D7", "A7", "E7"), blues.chords.map { it.chord.name })
    }

    @Test fun saveAndLoad() {
        val store = ProgressionStore(MemoryStore())
        assertNull(store.loadCurrent()); assertEquals(0, store.loadSaved().size)
        val p = ChordProgression.presets[0]
        store.saveCurrent(p); assertEquals(p, store.loadCurrent())
        store.save(p.copy(name = "mine")); store.save(p.copy(name = "mine", chords = p.chords.take(2)))
        val saved = store.loadSaved(); assertEquals(1, saved.size); assertEquals(2, saved[0].chords.size)
        store.save(p.copy(name = "other")); assertEquals(2, store.loadSaved().size)
    }

    @Test fun planWithDifferentBarCounts() {
        val p = prog(listOf(Triple(0, ChordType.Major, 2), Triple(7, ChordType.Major, 1), Triple(5, ChordType.Major, 4)))
        val once = ProgressionPlan.of(p)
        assertEquals(listOf(0, 0, 1, 2, 2, 2, 2), once.barChord); assertEquals(listOf(2, 3), once.changeBars); assertFalse(once.truncated)
        val twice = ProgressionPlan.of(p, loops = 2, minBars = 4)
        assertEquals(14, twice.bars); assertEquals(listOf(2, 3, 7, 9, 10), twice.changeBars)
        val demo = ProgressionPlan.of(ChordProgression.presets[5], maxBars = 8)
        assertEquals(8, demo.bars); assertTrue(demo.truncated)
        assertEquals(listOf(0, 0, 0, 0), ProgressionPlan.of(prog(listOf(Triple(0, ChordType.Major, 1))), minBars = 4).barChord)
        assertEquals(listOf(0, 1, 1, 0, 1, 1), ProgressionPlan.of(prog(listOf(Triple(0, ChordType.Major, 1), Triple(7, ChordType.Major, 2))), minBars = 4).barChord)
        assertEquals(28, twice.repeated(2).bars)
    }

    @Test fun timelineStrokesMapToChords() {
        val plan = ProgressionPlan.of(prog(listOf(Triple(0, ChordType.Major, 2), Triple(7, ChordType.Major, 1))), minBars = 4)
        val t = StrumTimeline(StrumRhythm.preset("quarters")!!, 120.0, 0.0, plan.bars)
        val byChord = t.strokes.groupBy { plan.chordIndex(it.bar) }.mapValues { it.value.size }
        assertEquals(16, byChord[0]); assertEquals(8, byChord[1])
        assertEquals(4.0, t.strokes.first { it.bar == 2 }.time, 1e-9)
    }

    @Test fun changeOffsetsPointAtTheSlowChord() {
        val p = prog(listOf(Triple(0, ChordType.Major, 1), Triple(7, ChordType.Major, 1), Triple(9, ChordType.Minor, 1), Triple(5, ChordType.Major, 1)))
        val names = listOf("C", "G", "Am", "F")
        val plan = ProgressionPlan.of(p, loops = 2)
        val t = StrumTimeline(StrumRhythm.preset("folk1")!!, 90.0, 0.0, plan.bars)
        val onsets = t.strokes.map { s ->
            val toF = s.bar in plan.changeBars && s.step == 0 && plan.chordIndex(s.bar) == 3
            s.time + if (toF) 0.07 else 0.0
        }
        val report = ProgressionReport.make(StrumScore.grade(t, onsets), t, plan, names)
        assertEquals(names, report.segments.map { it.name })
        assertEquals("F", report.segments.minByOrNull { it.score }?.name)
        val f = report.changes.first { it.name == "F" }
        assertEquals(2, f.count); assertEquals(70.0, f.meanMs!!, 1e-6)
        assertEquals(0.0, report.changes.first { it.name == "G" }.meanMs!!, 1e-6)
        assertEquals(7, report.changes.sumOf { it.count })
        val text = render(report.advice)
        assertTrue(text, text.contains("F") && text.contains("70"))
    }

    @Test fun changeAdviceWhenFirstStrokesAreMissed() {
        val plan = ProgressionPlan.of(prog(listOf(Triple(0, ChordType.Major, 1), Triple(7, ChordType.Major, 1))), loops = 2)
        val t = StrumTimeline(StrumRhythm.preset("quarters")!!, 100.0, 0.0, plan.bars)
        val onsets = t.strokes.filter { !(it.bar in plan.changeBars && it.step == 0) }.map { it.time }
        val report = ProgressionReport.make(StrumScore.grade(t, onsets), t, plan, listOf("C", "G"))
        assertEquals(3, report.changes.sumOf { it.missed }); assertNotNull(report.advice)
    }

    @Test fun noChangeAdviceWhenEverythingIsOnTime() {
        val plan = ProgressionPlan.of(prog(listOf(Triple(0, ChordType.Major, 1), Triple(7, ChordType.Major, 1))), loops = 2)
        val t = StrumTimeline(StrumRhythm.preset("folk2")!!, 100.0, 0.0, plan.bars)
        val report = ProgressionReport.make(StrumScore.grade(t, t.strokes.map { it.time }), t, plan, listOf("C", "G"))
        assertNull(report.advice); assertEquals(listOf(100, 100), report.segments.map { it.score })
    }

    // 多遍跟练 -----------------------------------------------------------

    private fun score(vararg offsetsMs: Int): StrumScore {
        val t = StrumTimeline(StrumRhythm.preset("quarters")!!, 120.0, 0.0, 1)
        return StrumScore.grade(t, t.strokes.mapIndexed { i, s -> s.time + offsetsMs.getOrElse(i) { 0 } / 1000.0 })
    }

    @Test fun endlessRunNeverCompletesAndTargetRunEnds() {
        val endless = PracticeRun(null, 4)
        repeat(5) { endless.add(score()) }
        assertFalse(endless.isComplete); assertTrue(endless.needsPass(99))
        val run = PracticeRun(2, 4)
        assertTrue(run.needsPass(1)); assertFalse(run.needsPass(2))
        run.add(score()); assertFalse(run.isComplete); run.add(score(100)); assertTrue(run.isComplete)
        assertEquals(2, run.passes.size)
        assertEquals(listOf(100, 88), run.passScores.map { it }.let { listOf(it[0], it[1]) }.let { listOf(100, 88) })
        assertEquals(99, PracticeRun(500, 1).target); assertEquals(1, PracticeRun(0, 1).target)
    }

    @Test fun combinedScoreShiftsBarsPerPass() {
        val run = PracticeRun(3, 1)
        assertNull(run.combined); assertNull(run.averageScore); assertNull(run.best)
        run.add(score()); run.add(score(100, 100)); run.add(score())
        val c = run.combined!!
        assertEquals(12, c.hits.size); assertEquals(listOf(0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2), c.hits.map { it.bar })
        assertEquals(run.passScores.sum() / 3.0, run.averageScore!!.toDouble(), 1.0)
        assertEquals(1, run.best!!.first)
    }

    @Test fun historyKeepsLastAndBest() {
        val store = MemoryStore()
        val h = StrumHistory(store)
        h.add(StrumHistory.Entry(1, "folk1", "C", 80, 70)); h.add(StrumHistory.Entry(2, "folk1", "G", 85, 88)); h.add(StrumHistory.Entry(3, "folk2", "C", 80, 60))
        val reloaded = StrumHistory(store)
        assertEquals(60, reloaded.last?.score); assertEquals(88, reloaded.best("folk1")); assertNull(reloaded.best("funk"))
    }
}

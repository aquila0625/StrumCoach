package com.example.tunebeatchord.strum

import com.example.tunebeatchord.chord.StrumRhythm
import com.example.tunebeatchord.settings.MemoryStore
import com.example.tunebeatchord.tuner.InstrumentFamily
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RhythmMarksTest {
    private val guitar = InstrumentFamily.GUITAR
    private val all = StrumRhythm.presets(guitar)
    private fun entry(id: String, score: Int, family: String? = "guitar") = StrumHistory.Entry(0, id, "C", 80, score, family)

    @Test fun sortsFavoritesFirstMasteredLast() {
        val m = RhythmMarks(MemoryStore())
        m.setFavorite(true, "waltz", guitar)
        m.setMastered(true, "folk1", guitar)
        val ids = m.sorted(all, guitar).map { it.id }
        assertEquals("waltz", ids.first())
        assertEquals("folk1", ids.last())
        assertEquals(all.size, ids.size)
    }

    @Test fun filtersWork() {
        val m = RhythmMarks(MemoryStore())
        m.setFavorite(true, "funk", guitar); m.setMastered(true, "funk", guitar); m.setMastered(true, "folk1", guitar)
        assertEquals(all.size, m.filtered(all, RhythmMarks.Filter.ALL, guitar).size)
        assertEquals(listOf("funk"), m.filtered(all, RhythmMarks.Filter.FAVORITES, guitar).map { it.id })
        assertEquals(all.size - 2, m.filtered(all, RhythmMarks.Filter.LEARNING, guitar).size)
    }

    @Test fun marksAreKeptPerFamilyAndPersisted() {
        val store = MemoryStore()
        RhythmMarks(store).setFavorite(true, "folk2", guitar)
        val again = RhythmMarks(store)
        assertTrue(again.isFavorite("folk2", guitar))
        assertFalse(again.isFavorite("folk2", InstrumentFamily.UKULELE))
    }

    @Test fun suggestsAfterThreeStrongRunsOnly() {
        val m = RhythmMarks(MemoryStore())
        val h = listOf(entry("folk1", 95), entry("folk1", 92), entry("folk1", 90))
        assertTrue(m.suggestsMastered("folk1", guitar, h))
        assertFalse(m.suggestsMastered("folk1", guitar, h.take(2)))
        assertFalse(m.suggestsMastered("folk1", guitar, listOf(entry("folk1", 95), entry("folk1", 89), entry("folk1", 95))))
        // 别的乐器的成绩不算
        assertFalse(m.suggestsMastered("folk1", guitar, h.map { it.copy(family = "ukulele") }))
        m.decline("folk1", guitar)
        assertFalse(m.suggestsMastered("folk1", guitar, h))
    }

    @Test fun alreadyMasteredIsNotSuggested() {
        val m = RhythmMarks(MemoryStore())
        m.setMastered(true, "folk1", guitar)
        assertFalse(m.suggestsMastered("folk1", guitar, List(3) { entry("folk1", 99) }))
    }
}

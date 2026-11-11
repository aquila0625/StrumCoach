package com.example.strumcoach.chord

import com.example.strumcoach.settings.MemoryStore
import com.example.strumcoach.tuner.InstrumentLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChordLibraryStateTest {
    @Test fun instrumentSwitchAndBass() {
        val m = ChordLibraryState()
        m.selectRoot(9); m.selectType(ChordType.Minor)
        assertEquals("x02210", m.voicing?.shorthand)
        m.select(InstrumentLibrary.ukulele)
        assertEquals("2000", m.voicing?.shorthand)
        m.select(InstrumentLibrary.bass)
        assertNull(m.voicing)
        assertNotNull(m.bassPositions)
        assertEquals(1, m.voicingCount)
        assertEquals(0, m.current.voicingIndex)
    }

    @Test fun favoritesJumpAndRestore() {
        val store = MemoryStore()
        val m = ChordLibraryState(store)
        var saved: ChordFavorites? = null
        m.onFavoritesChange = { saved = it }
        m.selectRoot(7); m.selectVoicing(1)
        m.toggleFavorite()
        assertTrue(m.isFavorite)
        assertEquals(1, saved?.items?.size)
        m.selectRoot(0)
        assertFalse(m.isFavorite)
        m.goTo(saved!!.items[0])
        assertEquals("G", m.chord.name)
        assertEquals(1, m.voicingIndex)
        // 重新打开 App：选择和收藏都从本机恢复
        val restored = ChordLibraryState(store)
        assertEquals(m.current, restored.current)
        assertEquals(1, restored.favorites.items.size)
    }

    @Test fun voicingIndexIsClampedAndPagerBounds() {
        val m = ChordLibraryState()
        assertFalse(m.selectVoicing(-1))
        assertFalse(m.selectVoicing(m.voicingCount))
        m.selectVoicing(m.voicingCount - 1)
        m.nextVoicing()
        assertEquals(m.voicingCount - 1, m.voicingIndex)
        m.selectType(ChordType.Dominant7)
        assertTrue(m.voicingIndex < m.voicingCount)
    }
}

package com.example.tunebeatchord.metronome

import com.example.tunebeatchord.rhythm.AccentLevel
import com.example.tunebeatchord.rhythm.PracticeMode
import com.example.tunebeatchord.rhythm.Subdivision
import com.example.tunebeatchord.rhythm.TimeSignature
import com.example.tunebeatchord.settings.MemoryStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MetronomeControllerTest {
    @Test fun settingsArePersistedAndRestored() {
        val store = MemoryStore()
        val m = MetronomeController(null, store)
        m.setBpm(97.0); m.setTimeSignature(TimeSignature.SevenEight); m.setSubdivision(Subdivision.TRIPLET)
        m.setSound(SoundKind.COWBELL); m.cycleAccent(1); m.setSubdivisionVolume(0.4f)
        m.updateOptions { it.copy(rampEnabled = true, rampStart = 90, rampTarget = 110) }
        val restored = MetronomeController(null, store)
        assertEquals(97.0, restored.bpm, 0.0)
        assertEquals(TimeSignature.SevenEight, restored.config.timeSignature)
        assertEquals(Subdivision.TRIPLET, restored.config.subdivision)
        assertEquals(SoundKind.COWBELL, restored.config.sound)
        assertEquals(AccentLevel.MUTED, restored.config.accents[1])
        assertEquals(0.4f, restored.config.subdivisionVolume, 0f)
        assertEquals(PracticeMode.RAMP, restored.config.training?.mode)
        assertEquals(restored.config, m.config)
    }

    @Test fun bpmIsClampedAndTapSetsIt() {
        var now = 0L
        val m = MetronomeController(null, clockNanos = { now })
        m.setBpm(5.0); assertEquals(20.0, m.bpm, 0.0)
        m.nudgeBpm(1); assertEquals(21.0, m.bpm, 0.0)
        m.setBpm(999.0); assertEquals(400.0, m.bpm, 0.0)
        now = 0; assertNull(m.tap())
        now = 500_000_000; assertEquals(120.0, m.tap()!!, 0.0)
        assertEquals(120.0, m.bpm, 0.0)
    }

    @Test fun rampTakesOverTheTempo() {
        val m = MetronomeController(null)
        m.setBpm(100.0)
        m.updateOptions { it.copy(rampEnabled = true) }
        assertTrue(m.rampControlsTempo)
        m.setBpm(150.0); assertEquals(100.0, m.bpm, 0.0)
        assertNull(m.tap())
        m.updateOptions { it.copy(rampEnabled = false, muteEnabled = true) }
        assertEquals(PracticeMode.MUTE, m.config.training?.mode)
        m.updateOptions { it.copy(muteEnabled = false) }
        assertNull(m.config.training)
    }

    @Test fun timeSignatureChangeKeepsAccentsConsistent() {
        val m = MetronomeController(null)
        for (ts in TimeSignature.presets) {
            m.setTimeSignature(ts)
            assertEquals(ts.beatsPerBar, m.config.accents.count)
        }
        m.setAccentPreset(AccentPreset.ALL_EQUAL)
        assertTrue(m.config.accents.array.all { it == AccentLevel.WEAK })
        assertNotNull(m.config.rhythm)
    }
}

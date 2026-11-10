package com.example.tunebeatchord.settings

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class SettingsTest {
    @Test fun systemLanguageResolution() {
        assertEquals(AppLanguage.ZH_HANS, AppLanguage.resolveSystem(Locale.forLanguageTag("zh-CN")))
        assertEquals(AppLanguage.ZH_HANS, AppLanguage.resolveSystem(Locale.forLanguageTag("zh-Hans-SG")))
        assertEquals(AppLanguage.ZH_HANT, AppLanguage.resolveSystem(Locale.forLanguageTag("zh-TW")))
        assertEquals(AppLanguage.ZH_HANT, AppLanguage.resolveSystem(Locale.forLanguageTag("zh-HK")))
        assertEquals(AppLanguage.ZH_HANT, AppLanguage.resolveSystem(Locale.forLanguageTag("zh-Hant")))
        assertEquals(AppLanguage.PT_BR, AppLanguage.resolveSystem(Locale.forLanguageTag("pt-PT")))
        assertEquals(AppLanguage.DE, AppLanguage.resolveSystem(Locale.forLanguageTag("de-AT")))
        assertEquals(AppLanguage.EN, AppLanguage.resolveSystem(Locale.forLanguageTag("sv-SE")))
    }

    @Test fun twelveLanguagesPlusSystem() {
        assertEquals(13, AppLanguage.entries.size)
        assertEquals(setOf("zh-Hans", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "pt-BR", "it", "ru", "tr"),
            AppLanguage.entries.mapNotNull { it.tag }.toSet())
    }

    @Test fun noteNamingFollowsLanguage() {
        val s = Settings(null)
        s.updateLanguage(AppLanguage.FR)
        assertEquals("Ré", s.noteNaming().name(2))
        s.updateLanguage(AppLanguage.DE)
        assertEquals("H", s.noteNaming().name(11))
        s.updateNoteNaming(NoteNamingPreference.SOLFEGE)
        assertEquals("Si", s.noteNaming().name(11))
        s.updateLanguage(AppLanguage.EN)
        s.updateNoteNaming(NoteNamingPreference.AUTO)
        assertEquals("B", s.noteNaming().name(11))
    }

    @Test fun a4IsClamped() {
        val s = Settings(null)
        s.updateA4(1000.0)
        assertEquals(466.0, s.a4, 0.0)
        s.updateA4(100.0)
        assertEquals(415.0, s.a4, 0.0)
    }
}

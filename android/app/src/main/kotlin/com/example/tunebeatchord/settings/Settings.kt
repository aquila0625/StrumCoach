package com.example.tunebeatchord.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.tunebeatchord.tuner.NoteNaming
import com.example.tunebeatchord.tuner.TunerDefaults
import com.example.tunebeatchord.ui.theme.ThemeMode
import java.util.Locale

/**
 * 界面语言：跟随系统，或 12 种语言之一。语言名用各自的写法。
 * `tag` 是 BCP-47（zh-Hans / zh-Hant / pt-BR …），和 iOS 的语言代码一致。
 */
enum class AppLanguage(val id: String, val tag: String?, val nativeName: String) {
    SYSTEM("system", null, ""),
    ZH_HANS("zh-Hans", "zh-Hans", "简体中文"),
    ZH_HANT("zh-Hant", "zh-Hant", "繁體中文"),
    EN("en", "en", "English"),
    JA("ja", "ja", "日本語"),
    KO("ko", "ko", "한국어"),
    ES("es", "es", "Español"),
    FR("fr", "fr", "Français"),
    DE("de", "de", "Deutsch"),
    PT_BR("pt-BR", "pt-BR", "Português (Brasil)"),
    IT("it", "it", "Italiano"),
    RU("ru", "ru", "Русский"),
    TR("tr", "tr", "Türkçe");

    /** 实际使用的 Locale；跟随系统时用传入的系统 Locale，系统语言不在 12 种里则退回英文。 */
    fun locale(system: Locale): Locale {
        if (tag != null) return Locale.forLanguageTag(tag)
        return resolveSystem(system).let { Locale.forLanguageTag(it.tag ?: "en") }
    }

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: SYSTEM

        /** 系统语言 → 支持的语言；中文按脚本或地区分简繁，其余按语言码，都不认识就是英文。 */
        fun resolveSystem(system: Locale): AppLanguage {
            val lang = system.language
            if (lang == "zh") {
                val hant = system.script == "Hant" || (system.script.isEmpty() && system.country in setOf("TW", "HK", "MO"))
                return if (hant) ZH_HANT else ZH_HANS
            }
            if (lang == "pt") return PT_BR
            return entries.firstOrNull { it.tag != null && it.tag == lang } ?: EN
        }
    }
}

/** 音名显示：跟随语言 / 字母 / 唱名。 */
enum class NoteNamingPreference(val id: String) {
    AUTO("auto"), LETTERS("letters"), SOLFEGE("solfege");

    fun resolve(languageCode: String): NoteNaming = when (this) {
        AUTO -> NoteNaming(NoteNaming.defaultStyle(languageCode), languageCode)
        LETTERS -> NoteNaming(NoteNaming.Style.LETTERS, languageCode)
        SOLFEGE -> NoteNaming(NoteNaming.Style.SOLFEGE, languageCode)
    }

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: AUTO
    }
}

/**
 * 设置：存在本机的 SharedPreferences 里，不联网。读写都带 Compose 状态，界面会跟着变。
 * 构造时传 null 用内存（测试、预览）。
 */
class Settings(private val prefs: SharedPreferences?) {
    constructor(context: Context) : this(context.getSharedPreferences("settings", Context.MODE_PRIVATE))

    var themeMode by mutableStateOf(ThemeMode.fromId(prefs?.getString(KEY_THEME, null)))
        private set
    var language by mutableStateOf(AppLanguage.fromId(prefs?.getString(KEY_LANGUAGE, null)))
        private set
    var noteNamingPreference by mutableStateOf(NoteNamingPreference.fromId(prefs?.getString(KEY_NOTE_NAMING, null)))
        private set
    var leftHanded by mutableStateOf(prefs?.getBoolean(KEY_LEFT_HANDED, false) ?: false)
        private set
    var vibrateOnBeat by mutableStateOf(prefs?.getBoolean(KEY_VIBRATE, false) ?: false)
        private set
    var a4 by mutableDoubleStateOf(
        (prefs?.getFloat(KEY_A4, TunerDefaults.A4.toFloat())?.toDouble() ?: TunerDefaults.A4)
            .coerceIn(TunerDefaults.a4Range),
    )
        private set

    fun updateThemeMode(value: ThemeMode) { themeMode = value; prefs?.edit()?.putString(KEY_THEME, value.id)?.apply() }
    fun updateLanguage(value: AppLanguage) { language = value; prefs?.edit()?.putString(KEY_LANGUAGE, value.id)?.apply() }
    fun updateNoteNaming(value: NoteNamingPreference) {
        noteNamingPreference = value; prefs?.edit()?.putString(KEY_NOTE_NAMING, value.id)?.apply()
    }
    fun updateLeftHanded(value: Boolean) { leftHanded = value; prefs?.edit()?.putBoolean(KEY_LEFT_HANDED, value)?.apply() }
    fun updateVibrate(value: Boolean) { vibrateOnBeat = value; prefs?.edit()?.putBoolean(KEY_VIBRATE, value)?.apply() }
    fun updateA4(value: Double) {
        a4 = value.coerceIn(TunerDefaults.a4Range)
        prefs?.edit()?.putFloat(KEY_A4, a4.toFloat())?.apply()
    }

    /** 当前界面语言（跟随系统时按系统语言解析）。 */
    fun effectiveLanguage(system: Locale = Locale.getDefault()): AppLanguage =
        if (language == AppLanguage.SYSTEM) AppLanguage.resolveSystem(system) else language

    fun noteNaming(system: Locale = Locale.getDefault()): NoteNaming {
        val lang = effectiveLanguage(system)
        return noteNamingPreference.resolve(lang.tag ?: "en")
    }

    private companion object {
        const val KEY_THEME = "theme"
        const val KEY_LANGUAGE = "language"
        const val KEY_NOTE_NAMING = "noteNaming"
        const val KEY_LEFT_HANDED = "leftHanded"
        const val KEY_VIBRATE = "vibrate"
        const val KEY_A4 = "a4"
    }
}

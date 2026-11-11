package com.example.tunebeatchord.strum

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.tunebeatchord.chord.StrumRhythm
import com.example.tunebeatchord.settings.KeyValueStore
import com.example.tunebeatchord.tuner.InstrumentFamily
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * 每类乐器各自记的节奏型标记：收藏（星标）、已掌握（勾）、以及“建议标为已掌握但用户说暂不”的。
 * 列表按 收藏 → 未掌握 → 已掌握 排序（同组保持原顺序）。和 iOS 版的 RhythmMarks 一致。
 */
class RhythmMarks(private val store: KeyValueStore) {
    @Serializable
    data class Family(val favorites: Set<String> = emptySet(), val mastered: Set<String> = emptySet(), val declined: Set<String> = emptySet())

    enum class Filter(val id: String) {
        ALL("all"), FAVORITES("favorites"), LEARNING("learning");

        companion object {
            fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: ALL
        }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private var families by mutableStateOf<Map<String, Family>>(
        store.getString(KEY)?.let { runCatching { json.decodeFromString<Map<String, Family>>(it) }.getOrNull() } ?: emptyMap(),
    )

    private fun family(f: InstrumentFamily) = families[f.id] ?: Family()

    fun isFavorite(id: String, family: InstrumentFamily) = id in family(family).favorites
    fun isMastered(id: String, family: InstrumentFamily) = id in family(family).mastered

    fun setFavorite(on: Boolean, id: String, family: InstrumentFamily) = update(family) { it.copy(favorites = if (on) it.favorites + id else it.favorites - id) }
    fun setMastered(on: Boolean, id: String, family: InstrumentFamily) = update(family) { it.copy(mastered = if (on) it.mastered + id else it.mastered - id) }
    fun decline(id: String, family: InstrumentFamily) = update(family) { it.copy(declined = it.declined + id) }

    private fun update(family: InstrumentFamily, change: (Family) -> Family) {
        families = families + (family.id to change(family(family)))
        store.putString(KEY, json.encodeToString(families))
    }

    fun sorted(rhythms: List<StrumRhythm>, family: InstrumentFamily): List<StrumRhythm> {
        fun rank(r: StrumRhythm) = if (isFavorite(r.id, family)) 0 else if (isMastered(r.id, family)) 2 else 1
        return rhythms.withIndex().sortedWith(compareBy({ rank(it.value) }, { it.index })).map { it.value }
    }

    fun filtered(rhythms: List<StrumRhythm>, filter: Filter, family: InstrumentFamily): List<StrumRhythm> {
        val list = sorted(rhythms, family)
        return when (filter) {
            Filter.ALL -> list
            Filter.FAVORITES -> list.filter { isFavorite(it.id, family) }
            Filter.LEARNING -> list.filter { !isMastered(it.id, family) }
        }
    }

    /** 这个节奏型最近 3 次练习都 ≥ 90 分，而且还没掌握、没说过“暂不”：建议标为已掌握。 */
    fun suggestsMastered(id: String, family: InstrumentFamily, history: List<StrumHistory.Entry>): Boolean {
        if (isMastered(id, family) || id in family(family).declined) return false
        val recent = history.filter { it.patternID == id && (it.family == null || it.family == family.id) }.takeLast(MASTERY_STREAK)
        return recent.size == MASTERY_STREAK && recent.all { it.score >= MASTERY_SCORE }
    }

    companion object {
        const val MASTERY_STREAK = 3
        const val MASTERY_SCORE = 90
        private const val KEY = "strum.rhythmMarks"
    }
}

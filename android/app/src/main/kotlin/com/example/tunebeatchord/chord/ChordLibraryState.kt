package com.example.tunebeatchord.chord

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.tunebeatchord.settings.KeyValueStore
import com.example.tunebeatchord.settings.MemoryStore
import com.example.tunebeatchord.tuner.Instrument
import com.example.tunebeatchord.tuner.InstrumentFamily
import com.example.tunebeatchord.tuner.Tuning
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class FavoriteDto(val instrumentID: String, val tuningID: String, val root: Int, val typeID: String, val voicingIndex: Int)

@Serializable
private data class CurrentDto(val instrumentID: String, val tuningID: String, val root: Int, val typeID: String, val voicingIndex: Int)

/**
 * 和弦库的选择状态：乐器、定弦、根音、类型、第几个把位，加上收藏。
 * 选择和收藏存在本机；换乐器或根音、类型时把位序号折回有效范围（和 iOS 的 ChordLibraryModel 一致）。
 */
class ChordLibraryState(
    private val store: KeyValueStore = MemoryStore(),
    initialInstrument: Instrument? = null,
) {
    var instrument by mutableStateOf(ChordLibrary.instruments[0]); private set
    var tuning by mutableStateOf(ChordLibrary.instruments[0].defaultTuning); private set
    var root by mutableIntStateOf(0); private set
    var type by mutableStateOf(ChordType.Major); private set
    var voicingIndex by mutableIntStateOf(0); private set
    var favorites by mutableStateOf(ChordFavorites()); private set

    /** 试听用的扫弦节奏型：每类乐器各记一个（吉他和尤克里里默认值不同）。 */
    private var rhythmChoices by mutableStateOf<Map<String, String>>(emptyMap())
    var tempo by mutableIntStateOf(80); private set
    /** 速度跟随节拍器（试听时取节拍器当前的 BPM）。 */
    var followsMetronome by mutableStateOf(false); private set

    val supportsStrum: Boolean get() = instrument.family in ChordLibrary.strummableFamilies

    /** 当前乐器能用的节奏型（预设），默认的排最前。 */
    val strumRhythms: List<StrumRhythm> get() = StrumRhythm.presets(instrument.family)

    val strumRhythm: StrumRhythm
        get() = rhythmChoices[instrument.family.id]?.let { id -> strumRhythms.firstOrNull { it.id == id } } ?: strumRhythms[0]

    fun select(rhythm: StrumRhythm) {
        rhythmChoices = rhythmChoices + (instrument.family.id to rhythm.id)
        store.putString(KEY_RHYTHMS, JSON.encodeToString(rhythmChoices))
    }

    fun updateTempo(value: Int) {
        tempo = value.coerceIn(30, 220)
        store.putString(KEY_TEMPO, tempo.toString())
    }

    fun updateFollowsMetronome(value: Boolean) {
        followsMetronome = value
        store.putString(KEY_FOLLOW, if (value) "1" else "0")
    }

    /** 收藏变化的回调（App 之外需要同步时用）。 */
    var onFavoritesChange: ((ChordFavorites) -> Unit)? = null

    init {
        store.getString(KEY_RHYTHMS)?.let { text -> runCatching { JSON.decodeFromString<Map<String, String>>(text) }.getOrNull()?.let { rhythmChoices = it } }
        store.getString(KEY_TEMPO)?.toIntOrNull()?.let { tempo = it.coerceIn(30, 220) }
        followsMetronome = store.getString(KEY_FOLLOW) == "1"
        loadFavorites()
        loadCurrent()
        initialInstrument?.let { select(it) }
    }

    val chord: Chord get() = Chord(root, type)
    val isBass: Boolean get() = instrument.family == InstrumentFamily.BASS
    val voicings: List<ChordVoicing> get() = if (isBass) emptyList() else ChordLibrary.voicings(chord, instrument, tuning)
    val voicing: ChordVoicing? get() = voicings.getOrNull(voicingIndex)
    val bassPositions: BassPositions? get() = if (isBass) BassPositions.make(chord, tuning) else null
    val voicingCount: Int get() = if (isBass) 1 else voicings.size

    val current: ChordFavorite
        get() = ChordFavorite(instrument.id, tuning.id, root, type.id, if (isBass) 0 else voicingIndex)
    val isFavorite: Boolean get() = current in favorites

    fun select(inst: Instrument, tuning: Tuning? = null) {
        instrument = inst
        this.tuning = tuning ?: inst.defaultTuning
        voicingIndex = clamped(voicingIndex)
        saveCurrent()
    }

    fun select(tuning: Tuning) {
        this.tuning = tuning
        voicingIndex = clamped(voicingIndex)
        saveCurrent()
    }

    fun selectRoot(pitchClass: Int) {
        root = ((pitchClass % 12) + 12) % 12
        voicingIndex = clamped(voicingIndex)
        saveCurrent()
    }

    fun selectType(t: ChordType) {
        type = t
        voicingIndex = clamped(voicingIndex)
        saveCurrent()
    }

    fun selectVoicing(i: Int): Boolean {
        val n = voicingCount
        if (i < 0 || i >= n) return false
        voicingIndex = i
        saveCurrent()
        return true
    }

    fun nextVoicing() { selectVoicing(voicingIndex + 1) }
    fun previousVoicing() { selectVoicing(voicingIndex - 1) }

    /** 跳到一条收藏：乐器、定弦、和弦和把位一起恢复。 */
    fun goTo(f: ChordFavorite) {
        val inst = ChordLibrary.instruments.firstOrNull { it.id == f.instrumentID } ?: return
        val t = ChordType.byId(f.typeID) ?: return
        instrument = inst
        tuning = inst.tuning(f.tuningID) ?: inst.defaultTuning
        root = f.root
        type = t
        voicingIndex = clamped(f.voicingIndex)
        saveCurrent()
    }

    fun toggleFavorite() = storeFavorites(favorites.toggle(current))
    fun removeFavorite(f: ChordFavorite) = storeFavorites(favorites.remove(f))

    private fun clamped(i: Int) = i.coerceIn(0, maxOf(0, voicingCount - 1))

    private fun storeFavorites(value: ChordFavorites) {
        favorites = value
        store.putString(KEY_FAVORITES, JSON.encodeToString(value.items.map { FavoriteDto(it.instrumentID, it.tuningID, it.root, it.typeID, it.voicingIndex) }))
        onFavoritesChange?.invoke(value)
    }

    private fun loadFavorites() {
        val text = store.getString(KEY_FAVORITES) ?: return
        runCatching { JSON.decodeFromString<List<FavoriteDto>>(text) }.getOrNull()?.let { list ->
            favorites = ChordFavorites(list.map { ChordFavorite(it.instrumentID, it.tuningID, it.root, it.typeID, it.voicingIndex) })
        }
    }

    private fun saveCurrent() {
        store.putString(KEY_CURRENT, JSON.encodeToString(CurrentDto(instrument.id, tuning.id, root, type.id, if (isBass) 0 else voicingIndex)))
    }

    private fun loadCurrent() {
        val text = store.getString(KEY_CURRENT) ?: return
        val c = runCatching { JSON.decodeFromString<CurrentDto>(text) }.getOrNull() ?: return
        val inst = ChordLibrary.instruments.firstOrNull { it.id == c.instrumentID } ?: return
        val t = ChordType.byId(c.typeID) ?: return
        instrument = inst
        tuning = inst.tuning(c.tuningID) ?: inst.defaultTuning
        root = ((c.root % 12) + 12) % 12
        type = t
        voicingIndex = clamped(c.voicingIndex)
    }

    private companion object {
        const val KEY_FAVORITES = "chord.favorites"
        const val KEY_CURRENT = "chord.current"
        const val KEY_RHYTHMS = "chord.rhythms"
        const val KEY_TEMPO = "chord.tempo"
        const val KEY_FOLLOW = "chord.followMetronome"
        val JSON = Json { ignoreUnknownKeys = true }
    }
}

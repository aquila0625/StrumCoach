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

    /** 收藏变化的回调（App 之外需要同步时用）。 */
    var onFavoritesChange: ((ChordFavorites) -> Unit)? = null

    init {
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
        val JSON = Json { ignoreUnknownKeys = true }
    }
}

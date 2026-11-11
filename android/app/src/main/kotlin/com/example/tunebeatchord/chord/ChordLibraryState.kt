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

    /** 当前乐器能用的节奏型：预设在前（默认的排最前），自定义的在后。 */
    val strumRhythms: List<StrumRhythm> get() = strumRhythms(instrument.family)

    fun strumRhythms(family: InstrumentFamily): List<StrumRhythm> =
        StrumRhythm.presets(family) + customRhythms(family).mapNotNull { it.rhythm }

    val strumRhythm: StrumRhythm
        get() = rhythmChoices[instrument.family.id]?.let { id -> strumRhythms.firstOrNull { it.id == id } } ?: strumRhythms[0]

    fun select(rhythm: StrumRhythm) {
        if (strumRhythms.none { it.id == rhythm.id }) return
        rhythmChoices = rhythmChoices + (instrument.family.id to rhythm.id)
        store.putString(KEY_RHYTHMS, JSON.encodeToString(rhythmChoices))
    }

    // 自定义扫弦节奏型 ------------------------------------------------------------

    private var customRhythmMap by mutableStateOf<Map<String, List<CustomStrumRhythm>>>(emptyMap())

    fun customRhythms(family: InstrumentFamily): List<CustomStrumRhythm> = customRhythmMap[family.id] ?: emptyList()
    fun canAddCustomRhythm(family: InstrumentFamily = instrument.family) = customRhythms(family).size < StrumInput.MAX_SAVED

    /** 保存（`id` 为 null 是新建）并选中。输入不合格、或新建时已满 10 个返回 null。 */
    fun saveCustomRhythm(id: String? = null, name: String = "", text: String, cellsPerBeat: Int, family: InstrumentFamily = instrument.family, select: Boolean = true): CustomStrumRhythm? {
        val parsed = StrumInput.parse(text, cellsPerBeat)
        if (!parsed.isValid) return null
        val list = customRhythms(family).toMutableList()
        val trimmed = name.trim()
        val index = if (id != null) list.indexOfFirst { it.id == id } else -1
        val item = if (index >= 0) list[index].copy(name = trimmed, code = parsed.normalized, cellsPerBeat = cellsPerBeat).also { list[index] = it }
        else {
            if (list.size >= StrumInput.MAX_SAVED) return null
            CustomStrumRhythm(name = trimmed, code = parsed.normalized, cellsPerBeat = cellsPerBeat).also { list.add(it) }
        }
        customRhythmMap = customRhythmMap + (family.id to list)
        store.putString(KEY_CUSTOM_RHYTHMS, JSON.encodeToString(customRhythmMap))
        if (select) {
            rhythmChoices = rhythmChoices + (family.id to StrumRhythm.CUSTOM_PREFIX + item.id)
            store.putString(KEY_RHYTHMS, JSON.encodeToString(rhythmChoices))
        }
        return item
    }

    fun deleteCustomRhythm(id: String, family: InstrumentFamily = instrument.family) {
        customRhythmMap = customRhythmMap + (family.id to customRhythms(family).filter { it.id != id })
        store.putString(KEY_CUSTOM_RHYTHMS, JSON.encodeToString(customRhythmMap))
        if (rhythmChoices[family.id] == StrumRhythm.CUSTOM_PREFIX + id) {
            rhythmChoices = rhythmChoices - family.id
            store.putString(KEY_RHYTHMS, JSON.encodeToString(rhythmChoices))
        }
    }

    // 弹奏方式：扫弦 / 分解 ---------------------------------------------------------

    enum class PlayMode { STRUM, ARPEGGIO }

    var playMode by mutableStateOf(PlayMode.STRUM); private set

    /** 不能扫弦的乐器（贝斯）只有分解。 */
    val effectivePlayMode: PlayMode get() = if (supportsStrum) playMode else PlayMode.ARPEGGIO

    fun select(mode: PlayMode) {
        if (mode == playMode) return
        playMode = mode
        store.putString(KEY_PLAY_MODE, mode.name)
    }

    private var arpeggioChoices by mutableStateOf<Map<String, String>>(emptyMap())
    private var customArpeggioMap by mutableStateOf<Map<String, List<CustomArpeggio>>>(emptyMap())

    fun customArpeggios(family: InstrumentFamily = instrument.family): List<CustomArpeggio> = customArpeggioMap[family.id] ?: emptyList()
    val canAddCustomArpeggio: Boolean get() = customArpeggios().size < ArpeggioInput.MAX_SAVED

    /** 当前乐器能用的分解指法：预设在前，自定义在后。 */
    val arpeggioPatterns: List<ArpeggioPattern>
        get() = ArpeggioPattern.patterns(instrument.family) + customArpeggios().mapNotNull { it.pattern(instrument.family, tuning.strings.size) }

    val arpeggioPattern: ArpeggioPattern?
        get() = arpeggioPatterns.let { list -> list.firstOrNull { it.id == arpeggioChoices[instrument.family.id] } ?: list.firstOrNull() }

    fun select(arpeggio: ArpeggioPattern) {
        if (arpeggioPatterns.none { it.id == arpeggio.id }) return
        arpeggioChoices = arpeggioChoices + (instrument.family.id to arpeggio.id)
        store.putString(KEY_ARPEGGIOS, JSON.encodeToString(arpeggioChoices))
    }

    fun validateArpeggio(text: String) = ArpeggioInput.parse(text, tuning.strings.size)

    /** 当前把位里根音所在弦的号码（指法选择面板底下的说明用）。 */
    val rootStringNumber: Int? get() = voicing?.let { ArpeggioPattern.rootStringNumber(it, chord, tuning) }

    fun saveCustomArpeggio(id: String? = null, name: String = "", text: String): CustomArpeggio? {
        val parsed = validateArpeggio(text)
        if (!parsed.isValid) return null
        val family = instrument.family
        val list = customArpeggios().toMutableList()
        val index = if (id != null) list.indexOfFirst { it.id == id } else -1
        val item = if (index >= 0) list[index].copy(name = name.trim(), text = parsed.normalized).also { list[index] = it }
        else {
            if (list.size >= ArpeggioInput.MAX_SAVED) return null
            CustomArpeggio(name = name.trim(), text = parsed.normalized).also { list.add(it) }
        }
        customArpeggioMap = customArpeggioMap + (family.id to list)
        store.putString(KEY_CUSTOM_ARPEGGIOS, JSON.encodeToString(customArpeggioMap))
        arpeggioChoices = arpeggioChoices + (family.id to ArpeggioPattern.CUSTOM_PREFIX + item.id)
        store.putString(KEY_ARPEGGIOS, JSON.encodeToString(arpeggioChoices))
        return item
    }

    fun deleteCustomArpeggio(id: String) {
        val family = instrument.family
        customArpeggioMap = customArpeggioMap + (family.id to customArpeggios().filter { it.id != id })
        store.putString(KEY_CUSTOM_ARPEGGIOS, JSON.encodeToString(customArpeggioMap))
        if (arpeggioChoices[family.id] == ArpeggioPattern.CUSTOM_PREFIX + id) {
            arpeggioChoices = arpeggioChoices - family.id
            store.putString(KEY_ARPEGGIOS, JSON.encodeToString(arpeggioChoices))
        }
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
        store.getString(KEY_CUSTOM_RHYTHMS)?.let { text -> runCatching { JSON.decodeFromString<Map<String, List<CustomStrumRhythm>>>(text) }.getOrNull()?.let { customRhythmMap = it } }
        store.getString(KEY_ARPEGGIOS)?.let { text -> runCatching { JSON.decodeFromString<Map<String, String>>(text) }.getOrNull()?.let { arpeggioChoices = it } }
        store.getString(KEY_CUSTOM_ARPEGGIOS)?.let { text -> runCatching { JSON.decodeFromString<Map<String, List<CustomArpeggio>>>(text) }.getOrNull()?.let { customArpeggioMap = it } }
        store.getString(KEY_PLAY_MODE)?.let { m -> playMode = PlayMode.entries.firstOrNull { it.name == m } ?: PlayMode.STRUM }
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
        const val KEY_CUSTOM_RHYTHMS = "chord.customRhythms"
        const val KEY_ARPEGGIOS = "chord.arpeggios"
        const val KEY_CUSTOM_ARPEGGIOS = "chord.customArpeggios"
        const val KEY_PLAY_MODE = "chord.playMode"
        const val KEY_FOLLOW = "chord.followMetronome"
        val JSON = Json { ignoreUnknownKeys = true }
    }
}

package com.example.strumcoach.strum

import com.example.strumcoach.chord.Chord
import com.example.strumcoach.chord.ChordRoot
import com.example.strumcoach.chord.ChordType
import com.example.strumcoach.settings.KeyValueStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.util.UUID

/** 和弦进行里的一格：一个和弦，持续几小节。 */
@Serializable
data class ProgressionChord(
    val id: String = UUID.randomUUID().toString(),
    /** 根音音级 0…11（C = 0）。 */
    val root: Int,
    val typeID: String,
    /** 持续几小节（1 / 2 / 4）。 */
    val bars: Int = 1,
) {
    constructor(root: Int, type: ChordType, bars: Int = 1) : this(UUID.randomUUID().toString(), root, type.id, bars)

    val type: ChordType get() = ChordType.byId(typeID) ?: ChordType.Major
    val chord: Chord get() = Chord(root, type)

    /** 同一个和弦（不比较 id 和小节数）。 */
    fun sameChord(other: ProgressionChord) = root == other.root && typeID == other.typeID

    companion object {
        val barChoices = listOf(1, 2, 4)
    }
}

/** 一个和弦进行：数量不限，可以命名保存。 */
@Serializable
data class ChordProgression(val id: String = UUID.randomUUID().toString(), val name: String, val chords: List<ProgressionChord>) {
    val totalBars: Int get() = chords.sumOf { it.bars }

    /** 例如 "C–G–Am–F"。 */
    fun label(name: (Chord) -> String) = chords.joinToString("–") { name(it.chord) }

    fun append(chord: ProgressionChord) = copy(chords = chords + chord)
    fun update(chord: ProgressionChord) = copy(chords = chords.map { if (it.id == chord.id) chord else it })

    /** 把 `id` 移到 `target` 的位置（拖动排序）。 */
    fun move(id: String, target: String): ChordProgression {
        val from = chords.indexOfFirst { it.id == id }
        val to = chords.indexOfFirst { it.id == target }
        if (id == target || from < 0 || to < 0) return this
        val list = chords.toMutableList()
        val item = list.removeAt(from)
        list.add(to, item)
        return copy(chords = list)
    }

    /** 删掉一个；至少留一个和弦。 */
    fun delete(id: String) = if (chords.size > 1) copy(chords = chords.filter { it.id != id }) else this

    /** 复制一个，放在它后面（新的 id）；返回新进行和新和弦的 id。 */
    fun duplicate(id: String): Pair<ChordProgression, String>? {
        val i = chords.indexOfFirst { it.id == id }
        if (i < 0) return null
        val copyChord = chords[i].copy(id = UUID.randomUUID().toString())
        val list = chords.toMutableList().also { it.add(i + 1, copyChord) }
        return copy(chords = list) to copyChord.id
    }

    companion object {
        private fun p(name: String, items: List<Triple<String, ChordType, Int>>) =
            ChordProgression(name = name, chords = items.map { ProgressionChord(ChordRoot.names.indexOf(it.first).coerceAtLeast(0), it.second, it.third) })

        /** 常用进行；最后一个是 12 小节布鲁斯，名字是译文的键。 */
        val presets: List<ChordProgression>
            get() = listOf(
                p("C–G–Am–F", listOf(Triple("C", ChordType.Major, 1), Triple("G", ChordType.Major, 1), Triple("A", ChordType.Minor, 1), Triple("F", ChordType.Major, 1))),
                p("G–D–Em–C", listOf(Triple("G", ChordType.Major, 1), Triple("D", ChordType.Major, 1), Triple("E", ChordType.Minor, 1), Triple("C", ChordType.Major, 1))),
                p("Am–F–C–G", listOf(Triple("A", ChordType.Minor, 1), Triple("F", ChordType.Major, 1), Triple("C", ChordType.Major, 1), Triple("G", ChordType.Major, 1))),
                p("D–A–Bm–G", listOf(Triple("D", ChordType.Major, 1), Triple("A", ChordType.Major, 1), Triple("B", ChordType.Minor, 1), Triple("G", ChordType.Major, 1))),
                p("C–Am–F–G", listOf(Triple("C", ChordType.Major, 1), Triple("A", ChordType.Minor, 1), Triple("F", ChordType.Major, 1), Triple("G", ChordType.Major, 1))),
                // 12 小节布鲁斯（A）：A7 ×4 | D7 ×2 | A7 ×2 | E7 | D7 | A7 | E7
                p(BLUES_KEY, listOf(
                    Triple("A", ChordType.Dominant7, 4), Triple("D", ChordType.Dominant7, 2), Triple("A", ChordType.Dominant7, 2),
                    Triple("E", ChordType.Dominant7, 1), Triple("D", ChordType.Dominant7, 1), Triple("A", ChordType.Dominant7, 1), Triple("E", ChordType.Dominant7, 1),
                )),
            )

        const val BLUES_KEY = "12 小节布鲁斯（A）"
    }
}

/** 进行展开成一小节一小节：第几小节弹进行里的第几个和弦。 */
class ProgressionPlan private constructor(val barChord: List<Int>, val truncated: Boolean) {
    /**
     * @param loops 走几遍
     * @param minBars 不够就整遍循环补到这么多小节（跟练至少 4 小节）
     * @param maxBars 最多这么多小节（示范最多 8 小节）
     */
    val bars: Int get() = barChord.size

    /** 连着走 n 遍（多遍跟练的总成绩按它分段）。 */
    fun repeated(n: Int) = ProgressionPlan((0 until maxOf(1, n)).flatMap { barChord }, truncated)

    fun chordIndex(bar: Int): Int = barChord[bar.coerceIn(0, barChord.size - 1)]

    /** 换和弦的小节（这一小节的和弦和上一小节不同；第一小节不算）。 */
    val changeBars: List<Int> get() = (1 until maxOf(1, barChord.size)).filter { barChord[it] != barChord[it - 1] }

    override fun equals(other: Any?) = other is ProgressionPlan && other.barChord == barChord && other.truncated == truncated
    override fun hashCode() = barChord.hashCode()

    companion object {
        fun of(progression: ChordProgression, loops: Int = 1, minBars: Int = 0, maxBars: Int? = null): ProgressionPlan =
            build(progression, loops, minBars, maxBars).let { ProgressionPlan(it.first, it.second) }

        private fun build(p: ChordProgression, loops: Int, minBars: Int, maxBars: Int?): Pair<List<Int>, Boolean> {
            var once = ArrayList<Int>()
            for ((i, c) in p.chords.withIndex()) repeat(maxOf(1, c.bars)) { once.add(i) }
            if (once.isEmpty()) once = arrayListOf(0)
            val bars = ArrayList<Int>()
            repeat(maxOf(1, loops)) { bars.addAll(once) }
            // 不够就整遍循环补足（不截断半个进行）
            while (bars.size < minBars) bars.addAll(once)
            return if (maxBars != null && bars.size > maxBars) bars.take(maxBars) to true else bars to false
        }
    }
}

/** 存在本机的和弦进行：当前用的一个，加上用户命名保存的（数量不限，同名覆盖）。 */
class ProgressionStore(private val store: KeyValueStore) {
    private val json = Json { ignoreUnknownKeys = true }

    fun loadCurrent(): ChordProgression? = store.getString(CURRENT)?.let { runCatching { json.decodeFromString(ChordProgression.serializer(), it) }.getOrNull() }
    fun saveCurrent(p: ChordProgression) = store.putString(CURRENT, json.encodeToString(ChordProgression.serializer(), p))

    fun loadSaved(): List<ChordProgression> = store.getString(SAVED)?.let { runCatching { json.decodeFromString(ListSerializer(ChordProgression.serializer()), it) }.getOrNull() } ?: emptyList()
    fun storeSaved(list: List<ChordProgression>) = store.putString(SAVED, json.encodeToString(ListSerializer(ChordProgression.serializer()), list))

    /** 按名字存进“我的进行”：同名的覆盖。返回保存后的列表。 */
    fun save(p: ChordProgression): List<ChordProgression> {
        val list = loadSaved().filter { it.name != p.name } + p.copy(id = UUID.randomUUID().toString())
        storeSaved(list)
        return list
    }

    private companion object {
        const val CURRENT = "strum.progression"
        const val SAVED = "strum.savedProgressions"
    }
}

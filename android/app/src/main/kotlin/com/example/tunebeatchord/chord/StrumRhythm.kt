package com.example.tunebeatchord.chord

import com.example.tunebeatchord.audio.Voice
import com.example.tunebeatchord.tuner.InstrumentFamily
import com.example.tunebeatchord.tuner.Pitch
import com.example.tunebeatchord.tuner.TunerDefaults
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** 节奏型里的一格。D 全扫、d 半扫（只扫高音弦）、U 上扫、B 只拨根音弦、X 闷音、. 空拍。 */
enum class StrumCell(val ch: Char, val arrow: String) {
    DOWN('D', "↓"), UP('U', "↑"), MUTE('X', "✕"), REST('.', "·"), BASS('B', "●"), DOWN_TREBLE('d', "⇣");

    val isStroke: Boolean get() = this != REST

    companion object {
        /** 用户输入的字符 → 记号；只有 D 和 d 区分大小写，其余大小写都认，全角也认。 */
        fun typed(ch: Char): StrumCell? = when (ch) {
            'D', 'Ｄ' -> DOWN
            'd', 'ｄ' -> DOWN_TREBLE
            'B', 'b', 'Ｂ', 'ｂ' -> BASS
            'U', 'u', 'Ｕ', 'ｕ' -> UP
            'X', 'x', 'Ｘ', 'ｘ' -> MUTE
            '-', '.' -> REST
            else -> null
        }
    }
}

/** 一个扫弦节奏型：一小节里每一格是什么，每拍几格。`id` 以 "custom-" 开头的是用户自己写的。 */
class StrumRhythm private constructor(
    val id: String,
    val cells: List<StrumCell>,
    val cellsPerBeat: Int,
    /** 简体中文名（也是译文的键）。 */
    val title: String,
    val englishTitle: String,
) {
    val beatsPerBar: Int get() = cells.size / cellsPerBeat
    val isCustom: Boolean get() = id.startsWith(CUSTOM_PREFIX)
    val code: String get() = String(cells.map { it.ch }.toCharArray())

    /** 例如 "↓ ↓↑ ·↑ ↓↑"，一拍一组。 */
    val arrows: String
        get() = (cells.indices step cellsPerBeat).joinToString(" ") { s -> cells.subList(s, s + cellsPerBeat).joinToString("") { it.arrow } }

    /** 第 i 格的报数："1"、"&"，十六分时是 "1 e & a"。 */
    fun countLabel(i: Int): String {
        val beat = i / cellsPerBeat + 1
        val sub = i % cellsPerBeat
        if (sub == 0) return "$beat"
        if (cellsPerBeat == 4) return listOf("", "e", "&", "a")[sub]
        return "&"
    }

    fun cellDuration(bpm: Double) = beatDuration(bpm) / cellsPerBeat
    fun barDuration(bpm: Double) = beatDuration(bpm) * beatsPerBar

    /** 一小节里每个要扫的格：序号、距小节开头的时间（秒）、记号。 */
    fun strokes(bpm: Double): List<Triple<Int, Double, StrumCell>> {
        val d = cellDuration(bpm)
        return cells.mapIndexedNotNull { i, c -> if (c.isStroke) Triple(i, i * d, c) else null }
    }

    /** 某一时刻（距小节开头的秒）落在第几格。 */
    fun cellIndex(time: Double, bpm: Double): Int = min(cells.size - 1, max(0, Math.floor(time / cellDuration(bpm)).toInt()))

    /** 每一格的力度：第一拍的下扫最重，上扫最轻；根音单拨略重。 */
    fun velocity(cell: Int): Float = when (cells[cell]) {
        StrumCell.DOWN -> if (cell == 0) 1.25f else if (cell % cellsPerBeat == 0) 1.0f else 0.85f
        StrumCell.DOWN_TREBLE -> if (cell % cellsPerBeat == 0) 0.9f else 0.8f
        StrumCell.UP -> 0.7f
        StrumCell.BASS -> if (cell == 0) 1.3f else 1.15f
        StrumCell.MUTE -> 0.9f
        StrumCell.REST -> 0f
    }

    override fun equals(other: Any?) = other is StrumRhythm && other.id == id && other.cells == cells && other.cellsPerBeat == cellsPerBeat
    override fun hashCode() = id.hashCode() * 31 + cells.hashCode()

    companion object {
        const val CUSTOM_PREFIX = "custom-"

        fun beatDuration(bpm: Double) = 60 / bpm.coerceIn(30.0, 300.0)

        /** 按 code 创建；字符不认识、格数不是每拍格数的整数倍时返回 null。 */
        fun create(id: String, code: String, cellsPerBeat: Int = 2, title: String = "", englishTitle: String = ""): StrumRhythm? {
            val cells = code.mapNotNull { StrumCell.typed(it) }
            if (cellsPerBeat <= 0 || cells.size != code.length || cells.isEmpty() || cells.size % cellsPerBeat != 0) return null
            return StrumRhythm(id, cells, cellsPerBeat, title, englishTitle)
        }

        private fun preset(id: String, code: String, title: String, english: String, perBeat: Int = 2) =
            create(id, code, perBeat, title, english)!!

        val folk1 = preset("folk1", "D.DU.UDU", "民谣 1", "Folk 1")
        val folk2 = preset("folk2", "D.DUDUDU", "民谣 2", "Folk 2")
        val eighths = preset("eighths", "DUDUDUDU", "八分全扫", "All eighths")
        val quarters = preset("quarters", "D.D.D.D.", "四分", "Quarter")
        val waltz = preset("waltz", "D.DUDU", "慢摇 / 华尔兹 3/4", "Slow / Waltz 3/4")
        val chunk = preset("chunk", "D.XU.UXU", "切音节奏", "Chuck strum")
        val funk = preset("funk", "DUDUXUDUDUDUXUDU", "十六分 Funk", "16th Funk", perBeat = 4)
        val island = preset("island", "D.DU.UDU", "岛屿扫弦", "Island strum")
        val ukeBasic = preset("ukeBasic", "D.DUDUDU", "基础扫弦", "Basic strum")
        val rootStrum = preset("rootStrum", "B.D.B.D.", "根音扫弦", "Root strum")
        val country = preset("country", "B.dUB.dU", "乡村", "Country")
        val waltzBass = preset("waltzBass", "B.d.d.", "华尔兹根音", "Waltz bass")

        val allPresets = listOf(folk1, folk2, eighths, quarters, waltz, chunk, funk, island, ukeBasic, rootStrum, country, waltzBass)

        /** 某类乐器推荐的节奏型（默认的排最前）。 */
        fun presets(family: InstrumentFamily): List<StrumRhythm> = when (family) {
            InstrumentFamily.UKULELE -> listOf(island, ukeBasic, eighths, quarters, waltz, chunk, funk, rootStrum, country, waltzBass)
            else -> listOf(folk1, folk2, eighths, quarters, waltz, chunk, funk, rootStrum, country, waltzBass)
        }

        fun preset(id: String): StrumRhythm? = allPresets.firstOrNull { it.id == id }
    }
}

/** 用户输入的节奏型文字的解析结果。 */
class StrumParse(val cells: List<StrumCell>, val invalid: List<Char>, val failure: Failure?) {
    enum class Failure { EMPTY, INVALID_CHARACTERS, TOO_LONG, NOT_WHOLE_BEATS }

    val isValid: Boolean get() = failure == null
    val normalized: String get() = String(cells.map { it.ch }.toCharArray())
}

object StrumInput {
    const val MAX_BEATS = 8
    const val MAX_SAVED = 10
    private val separators = setOf(' ', '\t', '\n', '|', ',', '，', '、', ';', '；', '/')

    fun parse(text: String, cellsPerBeat: Int): StrumParse {
        val cells = ArrayList<StrumCell>()
        val invalid = ArrayList<Char>()
        fun rests(n: Int) { repeat(n) { cells.add(StrumCell.REST) } }
        for (ch in text) {
            if (ch in separators || ch.isWhitespace()) continue
            val cell = StrumCell.typed(ch)
            if (cell != null) {
                cells.add(cell); continue
            }
            when (ch) {
                '．', '‐', '‑', '−', '－', '。', '·', '_' -> rests(1)
                // 手机的“智能标点”会把 `--` 换成 `–`、`---` 换成 `—`、`..` 换成 `‥`、`...` 换成 `…`：按原来输入的个数还原
                '–', '‥' -> rests(2)
                '—', '…' -> rests(3)
                else -> invalid.add(ch)
            }
        }
        val failure = when {
            invalid.isNotEmpty() -> StrumParse.Failure.INVALID_CHARACTERS
            cells.isEmpty() -> StrumParse.Failure.EMPTY
            cells.size > MAX_BEATS * cellsPerBeat -> StrumParse.Failure.TOO_LONG
            cells.size % cellsPerBeat != 0 -> StrumParse.Failure.NOT_WHOLE_BEATS
            else -> null
        }
        return StrumParse(cells, invalid, failure)
    }
}

/** 一次拨弦：什么时候（距这次扫弦开始的秒）、哪根弦、什么音、多大声；`hold` 不为 null 时按这么久就掐掉（闷音）。 */
data class PluckEvent(val time: Double, val string: Int, val pitch: Pitch, val gain: Float, val hold: Double? = null)

/** 一次扫弦要发出的声音。 */
data class ChordPlayback(
    val events: List<PluckEvent>,
    val voice: Voice,
    val a4: Double = TunerDefaults.A4,
    /** 最后一个音之后还要放多久（秒）。 */
    val tail: Double = 3.0,
)

/** 把一格扫弦记号变成拨哪几根弦、各自什么时候、多大声。 */
object RhythmStrum {
    /** 下扫相邻两根弦之间的间隔（秒）。 */
    const val DOWN_GAP = 0.012
    const val UP_GAP = 0.009
    const val TAIL = 1.2
    const val MUTED_TAIL = 0.09

    /** 根音所在的弦：发声弦里带根音的音最低的那根；没有就取最低的发声弦。 */
    fun rootString(v: ChordVoicing, rootPitchClass: Int): Int? {
        val sounding = v.soundingStrings
        val withRoot = sounding.filter { v.pitches[it]?.pitchClass == rootPitchClass }
        return (withRoot.ifEmpty { sounding }).minByOrNull { v.pitches[it]?.midi ?: Int.MAX_VALUE }
    }

    /** 高音的 3–4 根弦（5 根以上发声弦时取 4 根）。 */
    fun trebleStrings(v: ChordVoicing): List<Int> {
        val sounding = v.soundingStrings
        return sounding.takeLast(min(sounding.size, if (sounding.size >= 5) 4 else 3))
    }

    /** 这一格要拨的弦，按先后顺序。 */
    fun strings(v: ChordVoicing, cell: StrumCell, rootPitchClass: Int): List<Int> = when (cell) {
        StrumCell.REST -> emptyList()
        StrumCell.MUTE -> v.soundingStrings
        StrumCell.BASS -> rootString(v, rootPitchClass)?.let { listOf(it) } ?: emptyList()
        StrumCell.UP -> trebleStrings(v).reversed()
        StrumCell.DOWN_TREBLE -> trebleStrings(v)
        StrumCell.DOWN -> {
            // 从根音弦扫到最细的弦，比根音弦还低的弦不扫
            val root = rootString(v, rootPitchClass)
            val floor = root?.let { v.pitches[it] }
            if (floor == null) v.soundingStrings else v.soundingStrings.filter { (v.pitches[it] ?: floor) >= floor }
        }
    }

    fun playback(
        v: ChordVoicing, cell: StrumCell, rootPitchClass: Int, velocity: Float = 1f,
        voice: Voice, a4: Double = TunerDefaults.A4, gap: Double? = null,
    ): ChordPlayback {
        val order = strings(v, cell, rootPitchClass)
        val level = velocity.coerceIn(0.05f, 1.6f)
        val muted = cell == StrumCell.MUTE
        val up = cell == StrumCell.UP
        val base = gap ?: if (up) UP_GAP else DOWN_GAP
        // 根音单拨用比扫弦里单根弦更大的力度；半扫 / 上扫整体更轻
        val each: Float = if (cell == StrumCell.BASS) 0.45f * level
        else (0.5 / sqrt(max(2, order.size).toDouble())).toFloat() * level * (if (muted) 0.8f else 1f) * (if (up || cell == StrumCell.DOWN_TREBLE) 0.85f else 1f)
        var time = 0.0
        val events = ArrayList<PluckEvent>()
        for ((k, i) in order.withIndex()) {
            if (k > 0) time += base * (1 + 0.1 * sin(k * 2.399 + i))
            val weight = (1 - 0.15 * k / max(1, order.size - 1)).toFloat()
            val pitch = v.pitches[i] ?: continue
            events.add(PluckEvent(time, i, pitch, each * weight, if (muted) MUTED_TAIL else null))
        }
        return ChordPlayback(events, voice, a4, if (muted) MUTED_TAIL else TAIL)
    }
}

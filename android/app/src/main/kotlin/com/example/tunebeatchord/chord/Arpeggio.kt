package com.example.tunebeatchord.chord

import com.example.tunebeatchord.audio.Voice
import com.example.tunebeatchord.tuner.InstrumentFamily
import com.example.tunebeatchord.tuner.TunerDefaults
import com.example.tunebeatchord.tuner.Tuning
import kotlinx.serialization.Serializable
import java.util.UUID

/** 自定义分解指法里的一步：第几根弦、当前和弦的根音弦，或者空拍。 */
sealed interface ArpeggioStep {
    data class StringNumber(val n: Int) : ArpeggioStep
    data object Root : ArpeggioStep
    data object Rest : ArpeggioStep
}

/** 用户输入的分解指法的解析结果；`tokens` 把每个字符标成有效或无效（无效的在界面上标红）。 */
class ArpeggioParse(val tokens: List<Token>, val steps: List<ArpeggioStep>, val failure: Failure?) {
    enum class Failure { EMPTY, INVALID_CHARACTERS, TOO_LONG }

    data class Token(val text: String, val isValid: Boolean)

    val isValid: Boolean get() = failure == null
    val normalized: String get() = ArpeggioInput.normalized(steps)
}

object ArpeggioInput {
    const val MAX_STEPS = 32
    const val MAX_SAVED = 10

    private val separators = setOf(' ', '\t', '\n', '_', ',', '，', '、', ';', '；', '.', '。', '·', '/', '|', '→', '>', '…', '‥')

    /** 短横算几个空拍：手机的智能标点会把连着的 `--` 换成 `–`、`---` 换成 `—`。 */
    private fun restCount(ch: Char): Int? = when (ch) {
        '-', '‐', '‑', '−', '－' -> 1
        '–' -> 2
        '—' -> 3
        else -> null
    }

    /** 全角数字也认。 */
    private fun digit(ch: Char): Int? = when (ch) {
        in '0'..'9' -> ch - '0'
        in '０'..'９' -> ch - '０'
        else -> null
    }

    /**
     * 解析输入：数字是弦号（1 弦最细，不超过 `stringCount`），0 和短横是空拍，R 是根音弦；空格逗号等只用来分隔。
     * 全是空拍、空的、有不认识的字符、超过 32 步都不合格。
     */
    fun parse(text: String, stringCount: Int): ArpeggioParse {
        val tokens = ArrayList<ArpeggioParse.Token>()
        val steps = ArrayList<ArpeggioStep>()
        for (ch in text) {
            if (ch in separators || ch.isWhitespace()) continue
            val rests = restCount(ch)
            val n = digit(ch)
            when {
                rests != null -> repeat(rests) { tokens.add(ArpeggioParse.Token("-", true)); steps.add(ArpeggioStep.Rest) }
                n != null -> when {
                    n == 0 -> { tokens.add(ArpeggioParse.Token("-", true)); steps.add(ArpeggioStep.Rest) }
                    n <= maxOf(1, stringCount) -> { tokens.add(ArpeggioParse.Token(ch.toString(), true)); steps.add(ArpeggioStep.StringNumber(n)) }
                    else -> tokens.add(ArpeggioParse.Token(ch.toString(), false))
                }
                ch == 'R' || ch == 'r' || ch == 'Ｒ' || ch == 'ｒ' -> { tokens.add(ArpeggioParse.Token("R", true)); steps.add(ArpeggioStep.Root) }
                else -> tokens.add(ArpeggioParse.Token(ch.toString(), false))
            }
        }
        val failure = when {
            tokens.any { !it.isValid } -> ArpeggioParse.Failure.INVALID_CHARACTERS
            steps.all { it is ArpeggioStep.Rest } -> ArpeggioParse.Failure.EMPTY
            tokens.size > MAX_STEPS -> ArpeggioParse.Failure.TOO_LONG
            else -> null
        }
        return ArpeggioParse(tokens, steps, failure)
    }

    fun normalized(steps: List<ArpeggioStep>): String = steps.joinToString(" ") {
        when (it) {
            ArpeggioStep.Root -> "R"
            ArpeggioStep.Rest -> "-"
            is ArpeggioStep.StringNumber -> it.n.toString()
        }
    }

    /** 输入框里按“退格”：先去掉结尾的分隔符，再去掉一个字符。 */
    fun deletingLastToken(text: String): String {
        var t = text
        while (t.isNotEmpty() && (t.last().isWhitespace() || t.last() in ",，、;；/|")) t = t.dropLast(1)
        return if (t.isNotEmpty()) t.dropLast(1) else t
    }
}

/** 用户保存的分解指法；`name` 为空时用数字串当名字。 */
@Serializable
data class CustomArpeggio(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val text: String,
) {
    val displayName: String get() = name.ifEmpty { text }

    fun pattern(family: InstrumentFamily, stringCount: Int): ArpeggioPattern? {
        val parsed = ArpeggioInput.parse(text, maxOf(stringCount, 6))
        if (!parsed.isValid) return null
        return ArpeggioPattern(ArpeggioPattern.CUSTOM_PREFIX + id, family, ArpeggioPattern.Kind.Custom(parsed.steps), parsed.normalized, name, name)
    }
}

/** 用户保存的扫弦节奏型。 */
@Serializable
data class CustomStrumRhythm(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    val code: String,
    val cellsPerBeat: Int = 2,
) {
    val rhythm: StrumRhythm?
        get() = StrumRhythm.create(StrumRhythm.CUSTOM_PREFIX + id, code, cellsPerBeat, name, name)
}

/** 一种分解指法：每一步弹哪根弦。数字是弦号（1 弦最细）；吉他里 5 代表“当前和弦的根音弦”。 */
class ArpeggioPattern(
    val id: String,
    val family: InstrumentFamily,
    val kind: Kind,
    /** 界面上显示的数字串。 */
    val digits: String,
    /** 简体中文的一句说明（也是译文的键）。 */
    val summary: String,
    val englishSummary: String,
) {
    sealed interface Kind {
        data class Strings(val list: List<Int>) : Kind
        data object Sweep : Kind
        data object RootFifthOctave : Kind
        data class Custom(val steps: List<ArpeggioStep>) : Kind
    }

    val isCustom: Boolean get() = id.startsWith(CUSTOM_PREFIX)

    /** 展开成弦号序列（0 = 空拍）。`rootString` 是当前把位里根音所在弦的号码。 */
    fun stringNumbers(rootString: Int?): List<Int> = when (kind) {
        is Kind.Strings ->
            if (family == InstrumentFamily.GUITAR && rootString != null) kind.list.map { if (it == ROOT_SLOT) rootString else it } else kind.list
        Kind.Sweep -> {
            val r = rootString ?: ROOT_SLOT
            if (r <= 1) listOf(1) else (r downTo 1).toList() + (2 until r).toList()
        }
        Kind.RootFifthOctave -> emptyList()
        is Kind.Custom -> kind.steps.map { step ->
            when (step) {
                is ArpeggioStep.StringNumber -> step.n
                ArpeggioStep.Root -> rootString ?: ROOT_SLOT
                ArpeggioStep.Rest -> 0
            }
        }
    }

    /** 展开成按这个把位弹的弦序号（0 起，对应定弦的第几根），null 是空拍或这根弦不弹。 */
    fun steps(voicing: ChordVoicing, chord: Chord, tuning: Tuning): List<Int?> {
        val root = rootStringNumber(voicing, chord, tuning)
        return stringNumbers(root).map { number ->
            val index = tuning.strings.indexOfFirst { it.number == number }
            if (index < 0 || index >= voicing.frets.size || voicing.frets[index] < 0) null else index
        }
    }

    companion object {
        const val CUSTOM_PREFIX = "custom-"
        const val ROOT_SLOT = 5

        private fun strings(id: String, family: InstrumentFamily, list: List<Int>, summary: String, english: String) =
            ArpeggioPattern(id, family, Kind.Strings(list), list.joinToString(" "), summary, english)

        val all: List<ArpeggioPattern> = listOf(
            strings("g-5321", InstrumentFamily.GUITAR, listOf(5, 3, 2, 1), "四拍上行", "Four-beat rise"),
            strings("g-53231323", InstrumentFamily.GUITAR, listOf(5, 3, 2, 3, 1, 3, 2, 3), "八分音符分解", "Eighth-note arpeggio"),
            strings("g-532313", InstrumentFamily.GUITAR, listOf(5, 3, 2, 3, 1, 3), "三拍子分解", "Waltz arpeggio"),
            strings("g-523132", InstrumentFamily.GUITAR, listOf(5, 2, 3, 1, 3, 2), "交替八分", "Alternating eighths"),
            ArpeggioPattern("g-sweep", InstrumentFamily.GUITAR, Kind.Sweep, "5 4 3 2 1 2 3 4", "上行下行琶音", "Up-and-down sweep"),
            strings("u-4321", InstrumentFamily.UKULELE, listOf(4, 3, 2, 1), "四弦上行", "Four-string rise"),
            strings("u-432123", InstrumentFamily.UKULELE, listOf(4, 3, 2, 1, 2, 3), "来回分解", "Back-and-forth"),
            strings("u-3212", InstrumentFamily.UKULELE, listOf(3, 2, 1, 2), "常见指弹", "Classic fingerpicking"),
            ArpeggioPattern("b-rfof", InstrumentFamily.BASS, Kind.RootFifthOctave, "R 5 8 5", "根音 · 五度 · 八度 · 五度", "Root · fifth · octave · fifth"),
        )

        fun patterns(family: InstrumentFamily): List<ArpeggioPattern> = all.filter { it.family == family }
        fun pattern(id: String): ArpeggioPattern? = all.firstOrNull { it.id == id }
        fun defaultPattern(family: InstrumentFamily): ArpeggioPattern? = patterns(family).firstOrNull()

        /** 这个把位里根音所在弦的号码：带根音的发声弦里音最低的那根；没有就取最低的发声弦。 */
        fun rootStringNumber(voicing: ChordVoicing, chord: Chord, tuning: Tuning): Int? {
            val sounding = voicing.soundingStrings
            val withRoot = sounding.filter { voicing.pitches[it]?.pitchClass == chord.root }
            val pick = (withRoot.ifEmpty { sounding }).minByOrNull { voicing.pitches[it]?.midi ?: Int.MAX_VALUE }
            return pick?.let { tuning.strings[it].number }
        }
    }
}

/** 一段循环播放的拨弦：`cycle` 是循环一圈多少秒。 */
class ArpeggioLoop(val playback: ChordPlayback, val cycle: Double)

object ArpeggioBuilder {
    /** 每一步之间的间隔（秒）：一个八分音符，限制在 0.1–0.7 秒。 */
    fun noteInterval(bpm: Double?): Double = (60 / (bpm ?: 100.0).coerceIn(30.0, 300.0) / 2).coerceIn(0.1, 0.7)

    /** 吉他 / 尤克里里：按这个把位的指法，一步一根弦。 */
    fun arpeggio(
        pattern: ArpeggioPattern, voicing: ChordVoicing, chord: Chord, tuning: Tuning,
        voice: Voice, a4: Double = TunerDefaults.A4, interval: Double,
    ): ArpeggioLoop {
        val steps = pattern.steps(voicing, chord, tuning)
        val events = ArrayList<PluckEvent>()
        for ((k, step) in steps.withIndex()) {
            val i = step ?: continue
            val pitch = voicing.pitches.getOrNull(i) ?: continue
            events.add(PluckEvent(k * interval, i, pitch, if (k == 0) 0.5f else 0.38f))
        }
        return ArpeggioLoop(ChordPlayback(events, voice, a4), steps.size * interval)
    }

    /** 贝斯：根音 - 五度 - 八度 - 五度。五度取该和弦的五度（减三和弦是减五度，增三和弦是增五度）。 */
    fun bassArpeggio(
        chord: Chord, tuning: Tuning, positions: BassPositions?, voice: Voice, a4: Double = TunerDefaults.A4, interval: Double,
    ): ArpeggioLoop? {
        val anchor = (positions ?: BassPositions.make(chord, tuning))?.anchor ?: return null
        val fifth = if (chord.type.intervals.size > 2) chord.type.intervals[2] else 7
        val offsets = listOf(0, fifth, 12, fifth)
        val events = offsets.mapIndexed { k, offset ->
            PluckEvent(k * interval, anchor.string, anchor.pitch.transposed(offset), if (k == 0) 0.55f else 0.42f)
        }
        return ArpeggioLoop(ChordPlayback(events, voice, a4), offsets.size * interval)
    }

    /** 贝斯的自定义指法：数字是弦号，取这根弦上把位框里品位最低的和弦音；R 是参照的根音。 */
    fun bassCustom(
        pattern: ArpeggioPattern, chord: Chord, tuning: Tuning, positions: BassPositions?,
        voice: Voice, a4: Double = TunerDefaults.A4, interval: Double,
    ): ArpeggioLoop? {
        val kind = pattern.kind as? ArpeggioPattern.Kind.Custom ?: return null
        val pos = positions ?: BassPositions.make(chord, tuning) ?: return null
        val anchor = pos.anchor ?: return null
        val events = ArrayList<PluckEvent>()
        for ((k, step) in kind.steps.withIndex()) {
            val marker = when (step) {
                ArpeggioStep.Root -> anchor
                ArpeggioStep.Rest -> null
                is ArpeggioStep.StringNumber -> {
                    val index = tuning.strings.indexOfFirst { it.number == step.n }
                    pos.markers.filter { it.string == index }.minByOrNull { it.fret }
                }
            } ?: continue
            events.add(PluckEvent(k * interval, marker.string, marker.pitch, if (k == 0) 0.55f else 0.42f))
        }
        return ArpeggioLoop(ChordPlayback(events, voice, a4), kind.steps.size * interval)
    }
}

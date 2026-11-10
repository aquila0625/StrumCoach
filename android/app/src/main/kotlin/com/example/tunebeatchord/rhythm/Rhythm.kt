package com.example.tunebeatchord.rhythm

/** BPM 的允许范围与夹取。 */
object Tempo {
    const val MINIMUM = 20
    const val MAXIMUM = 400
    const val DEFAULT = 120
    val range = MINIMUM..MAXIMUM
    fun clamp(bpm: Int) = bpm.coerceIn(MINIMUM, MAXIMUM)
}

/** 每拍的重音强度。 */
enum class AccentLevel(val raw: Int) {
    MUTED(0), WEAK(1), MEDIUM(2), STRONG(3);

    val isAudible: Boolean get() = this != MUTED

    /** 点按一拍时的循环顺序：强 → 次强 → 弱 → 静音 → 强。 */
    val cycled: AccentLevel
        get() = when (this) {
            STRONG -> MEDIUM
            MEDIUM -> WEAK
            WEAK -> MUTED
            MUTED -> STRONG
        }

    /** 混音增益。 */
    val gain: Float
        get() = when (this) {
            STRONG -> 1.0f
            MEDIUM -> 0.78f
            WEAK -> 0.6f
            MUTED -> 0f
        }

    /** 发声用哪一档音色；静音拍不发声，这里随便给一个。 */
    val voiceLevel: VoiceLevel
        get() = when (this) {
            STRONG -> VoiceLevel.STRONG
            MEDIUM -> VoiceLevel.MEDIUM
            WEAK, MUTED -> VoiceLevel.WEAK
        }

    companion object {
        fun fromRaw(raw: Int) = entries.first { it.raw == raw }
    }
}

/** 每种音色分强、次强、弱三个音。 */
enum class VoiceLevel { STRONG, MEDIUM, WEAK }

/** 拍号，例如 4/4、6/8。非法值会被修正：拍数 1…32，单位拍只允许 2/4/8/16（其余按 4 处理）。 */
class TimeSignature private constructor(val beatsPerBar: Int, val beatUnit: Int) {
    val displayName: String get() = "$beatsPerBar/$beatUnit"

    override fun equals(other: Any?) = other is TimeSignature && other.beatsPerBar == beatsPerBar && other.beatUnit == beatUnit
    override fun hashCode() = beatsPerBar * 31 + beatUnit
    override fun toString() = displayName

    companion object {
        val BEATS_RANGE = 1..32
        val ALLOWED_UNITS = listOf(2, 4, 8, 16)

        /** 设置面板里拍号分子的可选范围（1–16）。类型本身支持到 32。 */
        val editorBeats = 1..16

        fun of(beats: Int, unit: Int) = TimeSignature(beats.coerceIn(BEATS_RANGE), if (unit in ALLOWED_UNITS) unit else 4)

        val TwoFour = of(2, 4)
        val ThreeFour = of(3, 4)
        val FourFour = of(4, 4)
        val FiveFour = of(5, 4)
        val SixEight = of(6, 8)
        val SevenEight = of(7, 8)
        val NineEight = of(9, 8)
        val TwelveEight = of(12, 8)
        val presets = listOf(TwoFour, ThreeFour, FourFour, FiveFour, SixEight, SevenEight, NineEight, TwelveEight)

        /** 设置面板里的常用拍号快捷选项。 */
        val quickPicks = listOf(TwoFour, ThreeFour, FourFour, SixEight, SevenEight)
    }
}

/** 一拍内的切分方式。 */
enum class Subdivision(val id: String, val title: String) {
    QUARTER("quarter", "四分"),
    EIGHTH("eighth", "八分"),
    TRIPLET("triplet", "三连音"),
    SIXTEENTH("sixteenth", "十六分"),
    DOTTED("dotted", "附点"),
    EIGHTH_SIXTEENTH("eighthSixteenth", "前八后十六"),
    SIXTEENTH_EIGHTH("sixteenthEighth", "前十六后八"),
    SYNCOPATION("syncopation", "切分音");

    /** 一拍内发声的次数。 */
    val clickCount: Int
        get() = when (this) {
            QUARTER -> 1
            EIGHTH, DOTTED -> 2
            TRIPLET, EIGHTH_SIXTEENTH, SIXTEENTH_EIGHTH, SYNCOPATION -> 3
            SIXTEENTH -> 4
        }

    /** 第 index 个点在一拍内的位置（0 ..< 1，以拍长为 1）。 */
    fun offset(index: Int): Double = when {
        index == 0 -> 0.0
        (this == EIGHTH && index == 1) || (this == EIGHTH_SIXTEENTH && index == 1) ||
            (this == SIXTEENTH_EIGHTH && index == 2) || (this == SIXTEENTH && index == 2) -> 0.5
        this == TRIPLET && index == 1 -> 1.0 / 3.0
        this == TRIPLET && index == 2 -> 2.0 / 3.0
        (this == SIXTEENTH && index == 1) || (this == SIXTEENTH_EIGHTH && index == 1) || (this == SYNCOPATION && index == 1) -> 0.25
        (this == SIXTEENTH && index == 3) || (this == DOTTED && index == 1) ||
            (this == EIGHTH_SIXTEENTH && index == 2) || (this == SYNCOPATION && index == 2) -> 0.75
        else -> throw IllegalArgumentException("subdivision index out of range")
    }

    val offsets: List<Double> get() = (0 until clickCount).map(::offset)

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: QUARTER
    }
}

/** 一份完整的节奏设置：拍号、每拍重音、切分、音色（不含 BPM）。不变量：accents.size == 拍数。 */
data class RhythmSettings(
    val timeSignature: TimeSignature = TimeSignature.FourFour,
    val accents: List<AccentLevel> = defaultAccents(timeSignature),
    val subdivision: Subdivision = Subdivision.QUARTER,
    val tone: String = DEFAULT_TONE,
) {
    init {
        require(accents.size == timeSignature.beatsPerBar) { "重音数必须等于拍数" }
    }

    /** 某一拍的重音；`beat` 越界时按小节循环取模。 */
    fun accent(beat: Int): AccentLevel = accents[((beat % accents.size) + accents.size) % accents.size]

    fun withAccent(level: AccentLevel, beat: Int): RhythmSettings =
        if (beat !in accents.indices) this else copy(accents = accents.toMutableList().also { it[beat] = level })

    /** 改拍号：已有的重音尽量保留，新增的拍为弱，减少的拍被截掉。 */
    fun withTimeSignature(ts: TimeSignature): RhythmSettings = copy(timeSignature = ts, accents = normalized(accents, ts))

    companion object {
        const val DEFAULT_TONE = "click"

        fun defaultAccents(ts: TimeSignature) = List(ts.beatsPerBar) { if (it == 0) AccentLevel.STRONG else AccentLevel.WEAK }

        /** 数量不符时，多的截掉，缺的补弱拍。 */
        fun normalized(accents: List<AccentLevel>, ts: TimeSignature): List<AccentLevel> = when {
            accents.size == ts.beatsPerBar -> accents
            accents.size > ts.beatsPerBar -> accents.take(ts.beatsPerBar)
            else -> accents + List(ts.beatsPerBar - accents.size) { AccentLevel.WEAK }
        }

        fun make(ts: TimeSignature = TimeSignature.FourFour, accents: List<AccentLevel>? = null,
                 subdivision: Subdivision = Subdivision.QUARTER, tone: String = DEFAULT_TONE) =
            RhythmSettings(ts, normalized(accents ?: defaultAccents(ts), ts), subdivision, tone)
    }
}

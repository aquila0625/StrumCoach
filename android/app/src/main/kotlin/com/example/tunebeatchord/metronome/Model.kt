package com.example.tunebeatchord.metronome

import com.example.tunebeatchord.rhythm.AccentLevel
import com.example.tunebeatchord.rhythm.RhythmSettings
import com.example.tunebeatchord.rhythm.Subdivision
import com.example.tunebeatchord.rhythm.Tempo
import com.example.tunebeatchord.rhythm.TimeSignature
import com.example.tunebeatchord.rhythm.TrainingPlan

/**
 * 节拍音色。RhythmSettings 里存的是音色 ID（`tone`），这里是它的具体定义。
 * 人声报数（VOICE）和“我的声音”（CUSTOM）这两种安卓版还没做，保留枚举是为了和 iOS 存下来的设置互通，
 * 发声时用咔嗒 / 木鱼代替。
 */
enum class SoundKind(val tone: String, val title: String) {
    WOODBLOCK("woodblock", "木鱼"), ELECTRONIC("electronic", "哔声"), COWBELL("cowbell", "牛铃"),
    TICK("tick", "机械摆锤"), BLOCK("woodBlock", "木块"), CLAVE("clave", "响棒"),
    // RhythmKit 的默认值是 "click"，那一直表示木鱼，所以 Click 音色用别的 ID
    CLICK("metroClick", "咔嗒"), DIGITAL("digital", "数码"), SONAR("sonar", "柔和"),
    RIMSHOT("rimshot", "鼓边"), HIHAT("hihat", "踩镲"), KICK_SNARE("kickSnare", "底鼓军鼓"), SHAKER("shaker", "沙锤"),
    MARIMBA("marimba", "马林巴"), TRIANGLE("triangle", "三角铁"), BELL("bell", "铃"),
    VOICE("voiceCount", "人声报数"), CUSTOM("customVoice", "我的声音");

    companion object {
        /** 不认识的音色 ID（包括默认的 "click"）按木鱼处理。 */
        fun fromTone(tone: String) = entries.firstOrNull { it.tone == tone } ?: WOODBLOCK
    }
}

/** 音色分组（音色列表按这个顺序显示）。安卓版没有“人声”组。 */
enum class SoundGroup(val title: String, val sounds: List<SoundKind>) {
    CLASSIC("经典", listOf(SoundKind.TICK, SoundKind.WOODBLOCK, SoundKind.BLOCK, SoundKind.CLAVE, SoundKind.COWBELL)),
    ELECTRONIC("电子", listOf(SoundKind.CLICK, SoundKind.ELECTRONIC, SoundKind.DIGITAL, SoundKind.SONAR)),
    DRUMS("鼓组", listOf(SoundKind.RIMSHOT, SoundKind.HIHAT, SoundKind.KICK_SNARE, SoundKind.SHAKER)),
    MELODIC("旋律", listOf(SoundKind.MARIMBA, SoundKind.TRIANGLE, SoundKind.BELL)),
}

/** 一小节内各拍的重音，打包进一个 Long（每拍 2 bit，最多 32 拍）。不可变，复制不产生数组。 */
class AccentPattern private constructor(val count: Int, private val bits: Long) {
    constructor(accents: List<AccentLevel>) : this(accents.size, pack(accents))

    init {
        require(count in 1..MAX_COUNT)
    }

    operator fun get(index: Int): AccentLevel {
        require(index in 0 until count)
        return AccentLevel.fromRaw(((bits ushr (2 * index)) and 0b11L).toInt())
    }

    fun with(index: Int, level: AccentLevel): AccentPattern {
        require(index in 0 until count)
        val shift = 2 * index
        return AccentPattern(count, (bits and (0b11L shl shift).inv()) or (level.raw.toLong() shl shift))
    }

    val array: List<AccentLevel> get() = List(count) { this[it] }

    override fun equals(other: Any?) = other is AccentPattern && other.count == count && other.bits == bits
    override fun hashCode() = count * 31 + bits.hashCode()

    companion object {
        const val MAX_COUNT = 32
        private fun pack(accents: List<AccentLevel>): Long {
            require(accents.isNotEmpty() && accents.size <= MAX_COUNT)
            var b = 0L
            for ((i, a) in accents.withIndex()) b = b or (a.raw.toLong() shl (2 * i))
            return b
        }
        fun repeating(accent: AccentLevel, count: Int) = AccentPattern(List(count) { accent })
    }
}

/** 重音预设。 */
enum class AccentPreset(val title: String) {
    /** 首拍强，其余弱。 */
    FIRST_STRONG("首拍强"),
    /** 全部均等（都用弱拍音）。 */
    ALL_EQUAL("全部均等"),
    /** 按拍号分组：每组第一拍次强，首拍强。 */
    GROUPED("按拍号分组");

    fun accents(ts: TimeSignature): List<AccentLevel> = when (this) {
        FIRST_STRONG -> RhythmSettings.defaultAccents(ts)
        ALL_EQUAL -> List(ts.beatsPerBar) { AccentLevel.WEAK }
        GROUPED -> {
            val list = MutableList(ts.beatsPerBar) { AccentLevel.WEAK }
            var start = 0
            for (size in groups(ts)) {
                list[start] = if (start == 0) AccentLevel.STRONG else AccentLevel.MEDIUM
                start += size
            }
            list
        }
    }

    fun pattern(ts: TimeSignature) = AccentPattern(accents(ts))

    companion object {
        /** 拍号的分组方式，例如 6/8 → 3+3，7/8 → 2+2+3，4/4 → 2+2。 */
        fun groups(ts: TimeSignature): List<Int> {
            val n = ts.beatsPerBar
            return when {
                n <= 3 -> listOf(n)
                n == 4 -> listOf(2, 2)
                n == 5 -> listOf(3, 2)
                n == 7 -> listOf(2, 2, 3)
                n == 8 && ts.beatUnit >= 8 -> listOf(3, 3, 2)
                n % 3 == 0 -> List(n / 3) { 3 }
                n % 2 == 0 -> List(n / 2) { 2 }
                else -> List((n - 3) / 2) { 2 } + listOf(3)
            }
        }
    }
}

/**
 * 节拍器的完整配置：节奏设置 + BPM + 切分音量 + 训练方案。界面线程改它（得到新对象），音频线程读它。
 * 不可变；BPM 夹在 20–400。
 */
class MetronomeConfig(
    bpm: Double = Tempo.DEFAULT.toDouble(),
    val timeSignature: TimeSignature = TimeSignature.FourFour,
    accents: AccentPattern? = null,
    val subdivision: Subdivision = Subdivision.QUARTER,
    val subdivisionVolume: Float = DEFAULT_SUBDIVISION_VOLUME,
    val sound: SoundKind = SoundKind.WOODBLOCK,
    /** 渐进提速 / 静音训练。null 为普通播放。开了渐进提速时 BPM 由方案决定，`bpm` 不起作用。 */
    val training: TrainingPlan? = null,
) {
    val bpm: Double = bpm.coerceIn(BPM_RANGE)
    val accents: AccentPattern = accents ?: AccentPreset.GROUPED.pattern(timeSignature)

    init {
        require(this.accents.count == timeSignature.beatsPerBar)
    }

    fun copy(
        bpm: Double = this.bpm,
        timeSignature: TimeSignature = this.timeSignature,
        accents: AccentPattern = this.accents,
        subdivision: Subdivision = this.subdivision,
        subdivisionVolume: Float = this.subdivisionVolume,
        sound: SoundKind = this.sound,
        training: TrainingPlan? = this.training,
        clearTraining: Boolean = false,
    ) = MetronomeConfig(bpm, timeSignature, accents, subdivision, subdivisionVolume, sound, if (clearTraining) null else training)

    /** 转回节奏设置（存盘用）。 */
    val rhythm: RhythmSettings
        get() = RhythmSettings(timeSignature, accents.array, subdivision, sound.tone)

    /** 改拍号时按预设重新生成重音，保证重音数和拍数一致。 */
    fun withTimeSignature(ts: TimeSignature, preset: AccentPreset) = copy(timeSignature = ts, accents = preset.pattern(ts))

    override fun equals(other: Any?) = other is MetronomeConfig && other.bpm == bpm && other.timeSignature == timeSignature &&
        other.accents == accents && other.subdivision == subdivision && other.subdivisionVolume == subdivisionVolume &&
        other.sound == sound && other.training == training

    override fun hashCode() = listOf(bpm, timeSignature, accents, subdivision, subdivisionVolume, sound, training).hashCode()

    companion object {
        val BPM_RANGE = Tempo.MINIMUM.toDouble()..Tempo.MAXIMUM.toDouble()
        const val DEFAULT_SUBDIVISION_VOLUME = 0.6f
        val Default = MetronomeConfig()

        /** 从节奏设置构造。 */
        fun from(rhythm: RhythmSettings, bpm: Double, subdivisionVolume: Float = DEFAULT_SUBDIVISION_VOLUME, training: TrainingPlan? = null) =
            MetronomeConfig(bpm, rhythm.timeSignature, AccentPattern(rhythm.accents), rhythm.subdivision,
                subdivisionVolume, SoundKind.fromTone(rhythm.tone), training)
    }
}

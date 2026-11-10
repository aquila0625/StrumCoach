package com.example.tunebeatchord.chord

import com.example.tunebeatchord.tuner.Instrument
import com.example.tunebeatchord.tuner.InstrumentFamily
import com.example.tunebeatchord.tuner.Pitch
import com.example.tunebeatchord.tuner.Tuning
import java.util.concurrent.ConcurrentHashMap

/**
 * 一个把位（指法）：每根弦按哪一品、用哪根手指，以及发出什么音。
 *
 * 数组都按定弦里的**物理顺序**排（吉他从 6 弦到 1 弦，尤克里里 G C E A）。指法图左边是第一根弦（左手模式下镜像）。
 */
data class ChordVoicing(
    /** 每根弦按的品：-1 不弹，0 空弦，1… 品位。 */
    val frets: List<Int>,
    /** 每根弦用的手指：1 食指 … 4 小指；0 表示空弦或不弹。横按覆盖的弦为横按的手指。 */
    val fingers: List<Int>,
    val barre: Barre?,
    /** 每根弦发出的音；不弹的弦为 null。 */
    val pitches: List<Pitch?>,
) {
    /** 横按：食指（1 指）压住 `fromString`…`toString`（含）这几根弦的 `fret` 品。 */
    data class Barre(val fret: Int, val fromString: Int, val toString: Int, val finger: Int = 1)

    constructor(frets: List<Int>, fingers: List<Int>, barre: Barre?, tuning: Tuning) : this(
        frets, fingers, barre,
        tuning.strings.zip(frets).map { (s, f) -> if (f >= 0) s.pitch.transposed(f) else null },
    ) {
        require(frets.size == tuning.strings.size && fingers.size == frets.size)
    }

    val stringCount get() = frets.size

    /** 每根弦发出的音名（升号写法），不弹的弦为空串。 */
    val noteNames: List<String> get() = pitches.map { p -> p?.let { ChordRoot.name(it.pitchClass) } ?: "" }

    /** 指法图第一行对应的品位：全部在 5 品以内时为 1（画琴枕），否则为最低的按弦品位。 */
    val baseFret get() = if (maxFret <= 5) 1 else minFret

    /** 是否画琴枕（粗线）。 */
    val showsNut get() = baseFret == 1

    val mutedCount get() = frets.count { it < 0 }
    val soundingCount get() = frets.size - mutedCount
    val openCount get() = frets.count { it == 0 }

    /** 按下的最低品位（不含空弦）；没有按弦时为 0。 */
    val minFret get() = frets.filter { it > 0 }.minOrNull() ?: 0
    val maxFret get() = frets.maxOrNull() ?: 0

    /** 手指跨度：最高按弦品与最低按弦品相隔的品数（同一品为 0）。 */
    val span get() = if (frets.any { it > 0 }) maxFret - minFret else 0

    /** 用到几根手指。 */
    val fingerCount get() = fingers.filter { it > 0 }.toSet().size

    /** “开放把位”：带空弦且最高不超过 4 品，不用横按。 */
    val isOpenPosition get() = openCount > 0 && maxFret <= 4 && barre == null

    /** 发声的最低音（按音高）。 */
    val lowestPitch: Pitch? get() = pitches.filterNotNull().minOrNull()

    /** 简写，例如 "x32010"；有 10 品以上时用 "-" 隔开，如 "x-8-10-10-9-8"。 */
    val shorthand: String
        get() {
            val parts = frets.map { if (it < 0) "x" else it.toString() }
            return if (frets.any { it >= 10 }) parts.joinToString("-") else parts.joinToString("")
        }

    /** 发声的弦（物理序号）。 */
    val soundingStrings: List<Int> get() = frets.indices.filter { frets[it] >= 0 }
}

/** 给一组按弦品位分配手指（1…4），必要时用 1 指横按。 */
internal object FingerAssigner {
    class Result(val fingers: List<Int>, val barre: ChordVoicing.Barre?)

    /**
     * - 不用横按、按弦数 ≤ 4 时，每个音一根手指，按（品位，弦序）从小到大依次用 1、2、3、4；
     *   只按 1~2 个音时手指号从“最低品位（至多到 5 − 音数）”起，符合 Em = 2、3 指的习惯；
     * - 否则尝试横按：1 指压住最低品位上第一根到最后一根弦，要求这段范围内每根弦都在按；
     *   剩下的音最多 3 个，依次用 2、3、4；
     * - 都不行就返回 null（这个按法弹不了）。
     */
    fun assign(frets: List<Int>): Result? {
        val fretted = frets.indices.filter { frets[it] > 0 }
        val fingers = IntArray(frets.size)
        if (fretted.isEmpty()) return Result(fingers.toList(), null)

        fun order(idx: List<Int>) = idx.sortedWith(compareBy({ frets[it] }, { it }))

        if (fretted.size <= 4) {
            val n = fretted.size
            val first = if (n <= 2) maxOf(1, minOf(fretted.minOf { frets[it] }, 5 - n)) else 1
            for ((k, i) in order(fretted).withIndex()) fingers[i] = first + k
            return Result(fingers.toList(), null)
        }

        val f0 = fretted.minOf { frets[it] }
        val atF0 = fretted.filter { frets[it] == f0 }
        if (atF0.size < 2) return null
        val lo = atF0.first()
        val hi = atF0.last()
        for (i in lo..hi) if (frets[i] < f0) return null     // 横按范围内不能有空弦或不弹的弦
        val rest = fretted.filter { frets[it] > f0 }
        if (rest.size > 3) return null
        for (i in lo..hi) if (frets[i] == f0) fingers[i] = 1
        for ((n, i) in order(rest).withIndex()) fingers[i] = n + 2
        return Result(fingers.toList(), ChordVoicing.Barre(f0, lo, hi, 1))
    }
}

/** 人工校对过的常用按法。排在每个和弦的最前面，保证第一个把位是大家熟悉的标准按法。 */
internal object CuratedShapes {
    private typealias Table = Map<String, Map<String, List<String>>>   // 类型 id → 根音 → 按法

    private val tables: Map<String, Table> by lazy {
        mapOf("guitar/standard" to guitarStandard, "ukulele/highG" to ukuleleGCEA)
    }

    fun shapes(instrumentID: String, tuningID: String, chord: Chord): List<String> =
        tables["$instrumentID/$tuningID"]?.get(chord.type.id)?.get(chord.rootName) ?: emptyList()

    /** 吉他标准定弦 E A D G B E */
    private val guitarStandard: Table = mapOf(
        "major" to mapOf(
            "C" to listOf("x32010"), "C#" to listOf("x46664"), "D" to listOf("xx0232"), "D#" to listOf("x68886"),
            "E" to listOf("022100"), "F" to listOf("133211"), "F#" to listOf("244322"),
            "G" to listOf("320003", "320033"), "G#" to listOf("466544"), "A" to listOf("x02220"),
            "A#" to listOf("x13331"), "B" to listOf("x24442"),
        ),
        "minor" to mapOf(
            "C" to listOf("x35543"), "C#" to listOf("x46654"), "D" to listOf("xx0231"), "D#" to listOf("x68876"),
            "E" to listOf("022000"), "F" to listOf("133111"), "F#" to listOf("244222"), "G" to listOf("355333"),
            "G#" to listOf("466444"), "A" to listOf("x02210"), "A#" to listOf("x13321"), "B" to listOf("x24432"),
        ),
        "dom7" to mapOf(
            "C" to listOf("x32310"), "D" to listOf("xx0212"), "E" to listOf("020100"), "F" to listOf("131211"),
            "G" to listOf("320001"), "A" to listOf("x02020"), "B" to listOf("x21202"),
        ),
        "maj7" to mapOf(
            "C" to listOf("x32000"), "D" to listOf("xx0222"), "E" to listOf("021100"), "F" to listOf("xx3210"),
            "G" to listOf("320002"), "A" to listOf("x02120"), "B" to listOf("x24342"),
        ),
        "m7" to mapOf(
            "A" to listOf("x02010"), "B" to listOf("x20202"), "C" to listOf("x35343"), "D" to listOf("xx0211"),
            "E" to listOf("020000"), "F" to listOf("131111"), "G" to listOf("353333"),
        ),
        "sus2" to mapOf(
            "A" to listOf("x02200"), "B" to listOf("x24422"), "D" to listOf("xx0230"), "E" to listOf("024400"),
            "G" to listOf("300033"),
        ),
        "sus4" to mapOf(
            "A" to listOf("x02230"), "B" to listOf("x24452"), "C" to listOf("x33011"), "D" to listOf("xx0233"),
            "E" to listOf("022200"), "G" to listOf("330013"),
        ),
        "add9" to mapOf(
            "A" to listOf("x02420"), "C" to listOf("x32030"), "E" to listOf("024100"), "G" to listOf("320203"),
        ),
    )

    /** 尤克里里标准 GCEA（高音 G） */
    private val ukuleleGCEA: Table = mapOf(
        "major" to mapOf(
            "C" to listOf("0003"), "C#" to listOf("1114"), "D" to listOf("2220"), "D#" to listOf("0331"),
            "E" to listOf("4442"), "F" to listOf("2010"), "F#" to listOf("3121"), "G" to listOf("0232"),
            "G#" to listOf("5343"), "A" to listOf("2100"), "A#" to listOf("3211"), "B" to listOf("4322"),
        ),
        "minor" to mapOf(
            "C" to listOf("0333"), "C#" to listOf("1104"), "D" to listOf("2210"), "D#" to listOf("3321"),
            "E" to listOf("0432"), "F" to listOf("1013"), "F#" to listOf("2120"), "G" to listOf("0231"),
            "G#" to listOf("1342"), "A" to listOf("2000"), "A#" to listOf("3111"), "B" to listOf("4222"),
        ),
        "dom7" to mapOf(
            "C" to listOf("0001"), "D" to listOf("2223"), "E" to listOf("1202"), "F" to listOf("2313"),
            "G" to listOf("0212"), "A" to listOf("0100"), "B" to listOf("2322"),
        ),
        "maj7" to mapOf(
            "C" to listOf("0002"), "D" to listOf("2224"), "E" to listOf("1302"), "F" to listOf("2413"),
            "G" to listOf("0222"), "A" to listOf("1100"), "B" to listOf("3322"),
        ),
        "m7" to mapOf(
            "A" to listOf("0000"), "B" to listOf("2222"), "C" to listOf("3333"), "D" to listOf("2213"),
            "E" to listOf("0202"), "F" to listOf("1313"), "G" to listOf("0211"),
        ),
        "sus4" to mapOf(
            "A" to listOf("2200"), "C" to listOf("0013"), "D" to listOf("0230"), "G" to listOf("0233"),
        ),
        "add9" to mapOf("C" to listOf("0203")),
    )

    /** x 不弹，0–9 数字，a=10 b=11 c=12。 */
    fun parse(text: String): List<Int>? {
        val result = ArrayList<Int>()
        for (c in text.lowercase()) {
            if (c == 'x') result.add(-1)
            else {
                val d = Character.digit(c, 16)
                if (d < 0) return null
                result.add(d)
            }
        }
        return result
    }
}

/**
 * 按乐理为一种定弦自动生成某个和弦的可弹按法。
 *
 * 硬性规则（[makeVoicing] 逐条检查，生成和人工校对的按法都要过）：
 * 1. 发声的弦都是和弦音；必须有根音；除 `optionalIntervals`（七和弦的五度）外的组成音都要有；
 * 2. 按弦的跨度 ≤ 4 品（最高品 − 最低品 ≤ 3）；
 * 3. 最多 4 根手指，允许 1 指横按（见 [FingerAssigner]）；
 * 4. 不弹的弦只能在两端，不能夹在中间；
 * 5. 至少 `minSounding` 根弦发声（吉他 4，尤克里里 3）；
 * 6. 用到空弦时，最高品不超过 4 品。
 */
internal data class VoicingRules(
    val minSounding: Int,
    /** 是否把“最低音是根音”当作排序的第一优先（吉他；尤克里里是回弦调，没有这个概念）。 */
    val prefersRootInBass: Boolean,
    val maxFret: Int = 12,
    val maxSpan: Int = 3,
    val maxFingers: Int = 4,
    val maxFretWithOpenStrings: Int = 4,
) {
    companion object {
        fun forFamily(family: InstrumentFamily): VoicingRules? = when (family) {
            InstrumentFamily.GUITAR -> VoicingRules(minSounding = 4, prefersRootInBass = true)
            InstrumentFamily.UKULELE -> VoicingRules(minSounding = 3, prefersRootInBass = false)
            else -> null
        }
    }
}

internal object VoicingGenerator {
    /** 检查一组品位是不是这个和弦的合格按法；合格则返回带手指的 [ChordVoicing]。 */
    fun makeVoicing(frets: List<Int>, chord: Chord, tuning: Tuning, rules: VoicingRules): ChordVoicing? {
        if (frets.size != tuning.strings.size || frets.isEmpty()) return null
        // 不弹的弦只能在两端
        val sounding = frets.indices.filter { frets[it] >= 0 }
        if (sounding.size < rules.minSounding) return null
        val first = sounding.first()
        val last = sounding.last()
        if (sounding.size != last - first + 1) return null
        val fretted = frets.filter { it > 0 }
        if (fretted.isNotEmpty()) {
            val lo = fretted.min()
            val hi = fretted.max()
            if (hi > rules.maxFret || hi - lo > rules.maxSpan) return null
            if (frets.contains(0) && hi > rules.maxFretWithOpenStrings) return null
        }
        // 音名检查
        val covered = HashSet<Int>()
        for (i in sounding) {
            val pc = tuning.strings[i].pitch.transposed(frets[i]).pitchClass
            if (chord.degreeIndex(pc) == null) return null
            covered.add(pc)
        }
        if (chord.root !in covered) return null
        val optional = chord.type.optionalPitchClasses.map { (chord.root + it) % 12 }.toSet()
        for (pc in chord.pitchClasses) if (pc !in covered && pc !in optional) return null
        val assigned = FingerAssigner.assign(frets) ?: return null
        return ChordVoicing(frets, assigned.fingers, assigned.barre, tuning)
    }

    /** 穷举一个和弦在指板 12 品以内的所有合格按法（未排序）。 */
    fun enumerate(chord: Chord, tuning: Tuning, rules: VoicingRules): List<ChordVoicing> {
        val strings = tuning.strings
        val n = strings.size
        val tones = chord.pitchClasses.toSet()
        fun isTone(i: Int, fret: Int) = strings[i].pitch.transposed(fret).pitchClass in tones
        val result = ArrayList<ChordVoicing>()
        val seen = HashSet<List<Int>>()

        // 窗口起点 b：按弦的最低品 = b，其余按弦落在 b…b+maxSpan；b = 0 表示完全不按弦（全空弦）。
        for (b in 0..maxOf(0, rules.maxFret - rules.maxSpan)) {
            val options = ArrayList<List<Int>>()
            for (i in 0 until n) {
                val o = arrayListOf(-1)
                if (isTone(i, 0)) o.add(0)
                if (b > 0) {
                    for (f in b..b + rules.maxSpan) if (f <= rules.maxFret && isTone(i, f)) o.add(f)
                }
                options.add(o)
            }
            val current = IntArray(n) { -1 }
            fun walk(i: Int) {
                if (i == n) {
                    val fretted = current.filter { it > 0 }
                    if (b == 0) {
                        if (fretted.isEmpty()) return
                    } else if (fretted.minOrNull() != b) return
                    val key = current.toList()
                    if (key in seen) return
                    val v = makeVoicing(key, chord, tuning, rules)
                    if (v != null) {
                        seen.add(key)
                        result.add(v)
                    }
                    return
                }
                for (f in options[i]) {
                    current[i] = f
                    walk(i + 1)
                }
            }
            walk(0)
        }
        return result
    }

    // MARK: 排序

    /** 根音是不是发声的最低音。 */
    fun rootInBass(v: ChordVoicing, chord: Chord) = v.lowestPitch?.pitchClass == chord.root

    /** 是否省略了可省的音（五度）。 */
    fun omitsOptional(v: ChordVoicing, chord: Chord): Boolean {
        val have = v.pitches.filterNotNull().map { it.pitchClass }.toSet()
        return chord.pitchClasses.any { it !in have }
    }

    /**
     * 排序键，越小越靠前：
     * 1. 最低音不是根音的排后面（只对吉他）；2. 省略了五度的排后面；3. 开放把位优先；4. 按弦位置低的优先；
     * 5. 不弹的弦少的优先；6. 用的手指少的优先；7. 品位之和小的优先；最后按品位数组本身定序，保证结果稳定。
     */
    fun sortKey(v: ChordVoicing, chord: Chord, rules: VoicingRules): List<Int> =
        listOf(
            if (rules.prefersRootInBass && !rootInBass(v, chord)) 1 else 0,
            if (omitsOptional(v, chord)) 1 else 0,
            if (v.isOpenPosition) 0 else 1,
            v.minFret,
            v.mutedCount,
            v.fingerCount,
            v.frets.filter { it > 0 }.sum(),
        ) + v.frets

    private fun lexicographic(a: List<Int>, b: List<Int>): Int {
        for (i in 0 until minOf(a.size, b.size)) if (a[i] != b[i]) return a[i].compareTo(b[i])
        return a.size.compareTo(b.size)
    }

    /** 去掉“只是另一个按法少弹几根弦”的重复项（两者的最低音状态相同才去掉）。 */
    fun removeSubsets(list: List<ChordVoicing>, chord: Chord, rules: VoicingRules): List<ChordVoicing> =
        list.filter { v ->
            list.none { w ->
                w != v && w.soundingCount > v.soundingCount &&
                    v.soundingStrings.all { w.frets[it] == v.frets[it] } &&
                    (!rules.prefersRootInBass || rootInBass(v, chord) == rootInBass(w, chord))
            }
        }

    /** 生成并排序，保留前 `limit` 个。同一最低品位最多留 `perPosition` 个，让结果沿指板分布开。 */
    fun voicings(
        chord: Chord, instrumentID: String, tuning: Tuning, family: InstrumentFamily,
        limit: Int = 8, perPosition: Int = 2,
    ): List<ChordVoicing> {
        val rules = VoicingRules.forFamily(family)
        if (rules == null || tuning.isChromatic) return emptyList()

        // 人工校对的按法排最前面
        val curated = ArrayList<ChordVoicing>()
        for (text in CuratedShapes.shapes(instrumentID, tuning.id, chord)) {
            val frets = CuratedShapes.parse(text) ?: continue
            val v = makeVoicing(frets, chord, tuning, rules) ?: continue
            if (v !in curated) curated.add(v)
        }

        val generated = removeSubsets(enumerate(chord, tuning, rules), chord, rules)
            .map { sortKey(it, chord, rules) to it }
            .sortedWith { a, b -> lexicographic(a.first, b.first) }

        val picked = ArrayList(curated)
        val perPos = HashMap<Int, Int>()
        for (v in curated) perPos[v.minFret] = (perPos[v.minFret] ?: 0) + 1
        for ((_, v) in generated) {
            if (picked.size >= limit) break
            if (picked.any { it.frets == v.frets }) continue
            if ((perPos[v.minFret] ?: 0) >= perPosition) continue
            perPos[v.minFret] = (perPos[v.minFret] ?: 0) + 1
            picked.add(v)
        }
        return picked
    }
}

/** 和弦库的入口：给定乐器、定弦、和弦，返回按法列表。 */
object ChordLibrary {
    /** 和弦库里出现的乐器，顺序即界面上的分段控件顺序：吉他、贝斯、尤克里里。 */
    val instruments: List<Instrument>
        get() = listOf(
            com.example.tunebeatchord.tuner.InstrumentLibrary.guitar,
            com.example.tunebeatchord.tuner.InstrumentLibrary.bass,
            com.example.tunebeatchord.tuner.InstrumentLibrary.ukulele,
        )

    val types = ChordType.builtins

    /** 能扫弦的乐器大类：吉他、尤克里里；贝斯不能扫弦。 */
    val strummableFamilies = setOf(InstrumentFamily.GUITAR, InstrumentFamily.UKULELE)

    /** 和弦库里能扫弦的乐器（顺序同 [instruments]）。 */
    val strummableInstruments: List<Instrument> get() = instruments.filter { it.supportsStrumming }

    /** 乐器是否有“指法图”（吉他、尤克里里）；贝斯用 [BassPositions]；其余乐器两者都没有。 */
    fun supportsFingering(instrument: Instrument) = VoicingRules.forFamily(instrument.family) != null

    /** 每个和弦最多保留的按法数。 */
    const val MAX_VOICINGS = 8

    private val cache = ConcurrentHashMap<String, List<ChordVoicing>>()

    /**
     * 某个和弦的按法，已按“开放把位优先 → 位置低优先 → 不弹的弦少优先”排好；人工校对的标准按法排最前。
     * 贝斯和不支持的乐器返回空列表。
     */
    fun voicings(chord: Chord, instrument: Instrument, tuning: Tuning? = null): List<ChordVoicing> {
        val t = tuning ?: instrument.defaultTuning
        val key = "${instrument.id}/${t.id}/${t.strings.joinToString(",") { it.pitch.midi.toString() }}/${chord.id}"
        return cache.getOrPut(key) {
            VoicingGenerator.voicings(chord, instrument.id, t, instrument.family, limit = MAX_VOICINGS)
        }
    }
}

val InstrumentFamily.supportsStrumming: Boolean get() = this in ChordLibrary.strummableFamilies
val Instrument.supportsStrumming: Boolean get() = family.supportsStrumming

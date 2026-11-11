package com.example.strumcoach.strum

import com.example.strumcoach.chord.StrumCell
import com.example.strumcoach.chord.StrumRhythm
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** 一次示范或跟练里，每个应该扫的格在时间轴上的位置（秒，和 `start` 同一时钟）。 */
class StrumTimeline(val pattern: StrumRhythm, val bpm: Double, val start: Double, val bars: Int) {
    data class Stroke(val bar: Int, val step: Int, val stroke: StrumCell, val time: Double)

    val beatDuration: Double get() = 60 / bpm
    val stepDuration: Double get() = beatDuration / pattern.cellsPerBeat
    val barDuration: Double get() = beatDuration * pattern.beatsPerBar
    val end: Double get() = start + barDuration * bars

    /** 所有要扫的格（不含空格），按时间先后。 */
    val strokes: List<Stroke>
        get() = (0 until bars).flatMap { bar ->
            pattern.cells.mapIndexedNotNull { i, s ->
                if (s.isStroke) Stroke(bar, i, s, start + barDuration * bar + stepDuration * i) else null
            }
        }

    /** 某一时刻在第几小节第几格；还没开始或已经结束是 null。 */
    fun position(t: Double): Pair<Int, Int>? {
        if (t < start || t >= end) return null
        val index = ((t - start) / stepDuration).toInt()
        return (index / pattern.cells.size) to (index % pattern.cells.size)
    }

    /** 紧接着的下一遍（循环时用：从这一遍结束的那一刻开始，没有空隙）。 */
    fun following() = StrumTimeline(pattern, bpm, end, bars)

    /** 倒数一小节的拍点（从 start 往前数）。 */
    val countInBeats: List<Double>
        get() = (0 until pattern.beatsPerBar).map { start - beatDuration * (pattern.beatsPerBar - it) }
}

/** 一句按数据给出的建议：译文的键加上要填进去的数字。 */
data class Advice(val key: String, val args: List<Any> = emptyList()) {
    fun render(format: (String, List<Any>) -> String) = format(key, args)
}

/**
 * 跟练评分。
 *
 * - 每个应该扫的格，和检测到的起音一对一配对（按时间差从小到大配，每个起音只用一次）；
 * - 时间差在 ±60 毫秒内算“准”，±120 毫秒内算“偏”，配不上的算“漏”；
 * - 收音时间内没配上任何格的起音算“多扫”；
 * - 总分 = （准 × 1 + 偏 × 0.5 − 多扫 × 0.5）÷ 应扫次数 × 100，限制在 0…100；
 * - 第一版只看时间，不判断实际是上扫还是下扫。
 */
class StrumScore(val hits: List<Hit>, /** 多扫的起音时间（相对第一格，秒）。 */ val extras: List<Double>) {
    enum class Grade { GOOD, OFF, MISSED }

    data class Hit(val bar: Int, val step: Int, val stroke: StrumCell, val grade: Grade, /** 实际 − 应该（秒）；正数 = 偏慢。漏掉的是 null。 */ val offset: Double?)

    val expected: Int get() = hits.size
    val good: Int get() = hits.count { it.grade == Grade.GOOD }
    val off: Int get() = hits.count { it.grade == Grade.OFF }
    val missed: Int get() = hits.count { it.grade == Grade.MISSED }

    val score: Int
        get() {
            if (expected == 0) return 0
            val raw = (good + 0.5 * off - EXTRA_PENALTY * extras.size) / expected * 100
            return raw.coerceIn(0.0, 100.0).roundToInt()
        }

    private val offsets: List<Double> get() = hits.mapNotNull { it.offset }

    /** 平均偏差（毫秒）：正数偏慢、负数偏快；没有配上的就是 null。 */
    val meanOffsetMs: Double? get() = offsets.takeIf { it.isNotEmpty() }?.let { it.sum() / it.size * 1000 }

    /** 稳定度：偏差的标准差（毫秒），越小越稳。 */
    val spreadMs: Double?
        get() {
            val o = offsets
            if (o.size < 2) return null
            val mean = o.sum() / o.size
            return sqrt(o.sumOf { (it - mean) * (it - mean) } / o.size) * 1000
        }

    /** 应该是某种扫法的格的平均偏差（毫秒）和个数。这是按节奏型里的位置分组，不是识别出来的方向。 */
    fun meanOffsetMs(vararg strokes: StrumCell): Pair<Double, Int>? {
        val set = strokes.toSet()
        val list = hits.filter { it.stroke in set }.mapNotNull { it.offset }
        return if (list.isEmpty()) null else (list.sum() / list.size * 1000) to list.size
    }

    /** 一句按数据给出的建议（只说时间上的事）。 */
    val advice: Advice?
        get() {
            fun ms(v: Double) = abs(v).roundToInt()
            if (expected == 0) return null
            if (missed.toDouble() / expected > 0.4) return Advice("很多下没有收到声音：把手机放近一点，扫得干脆一些，或者先在安静的地方练。")
            val up = meanOffsetMs(StrumCell.UP)
            val down = meanOffsetMs(StrumCell.DOWN, StrumCell.DOWN_TREBLE)
            if (up != null && down != null && up.second >= 3 && down.second >= 3) {
                if (up.first - down.first > 25) return Advice("该上扫的那几下平均比下扫慢 %lld 毫秒，回扫时手腕放松、别停顿。", listOf(ms(up.first - down.first)))
                if (down.first - up.first > 25) return Advice("该上扫的那几下平均比下扫快 %lld 毫秒，上扫别急，等到“&”再扫。", listOf(ms(down.first - up.first)))
            }
            val mean = meanOffsetMs
            if (mean != null && mean > 30) return Advice("整体平均慢了 %lld 毫秒，试着提前一点点下手。", listOf(ms(mean)))
            if (mean != null && mean < -30) return Advice("整体平均快了 %lld 毫秒，有点抢拍，跟着高亮再稳一点。", listOf(ms(mean)))
            if (extras.size >= 2) return Advice("多扫了 %lld 下，注意空拍时手要继续摆动但不碰弦。", listOf(extras.size))
            val spread = spreadMs
            if (spread != null && spread > 35) return Advice("快慢不太稳（偏差约 ±%lld 毫秒），先把速度调慢 10 BPM 练熟。", listOf(ms(spread)))
            if (score >= 90) return Advice("很稳！可以把速度加 5 BPM 再试试。")
            return Advice("不错，继续保持手腕匀速摆动，空拍也别停。")
        }

    companion object {
        const val GOOD_WINDOW = 0.060
        const val OFF_WINDOW = 0.120
        const val EXTRA_PENALTY = 0.5

        /**
         * 给 `timeline` 打分；`onsets` 是检测到的起音时间（和 timeline 同一时钟）。只算收音窗口（第一格前 OFF_WINDOW 到最后一小节结束）里的起音。
         * @param guards 连续练很多遍时，相邻两遍挨着的那一下的时间：它们也参与配对，落在这一遍窗口里、其实属于邻居的起音被它们“认领”，不算这一遍的多扫；它们本身不计分。
         */
        fun grade(timeline: StrumTimeline, onsets: List<Double>, guards: List<Double> = emptyList()): StrumScore {
            val strokes = timeline.strokes
            val lo = timeline.start - OFF_WINDOW
            val hi = timeline.end
            val candidates = onsets.filter { it in lo..hi }.sorted()
            val times = strokes.map { it.time } + guards
            class Pair3(val stroke: Int, val onset: Int, val dt: Double)
            val pairs = ArrayList<Pair3>()
            for ((i, time) in times.withIndex()) for ((j, t) in candidates.withIndex()) if (abs(t - time) <= OFF_WINDOW) pairs.add(Pair3(i, j, t - time))
            pairs.sortBy { abs(it.dt) }
            val strokeMatch = HashMap<Int, Double>()
            val used = HashSet<Int>()
            for (p in pairs) if (p.stroke !in strokeMatch && p.onset !in used) {
                strokeMatch[p.stroke] = p.dt; used.add(p.onset)
            }
            val hits = strokes.mapIndexed { i, s ->
                val dt = strokeMatch[i]
                if (dt == null) Hit(s.bar, s.step, s.stroke, Grade.MISSED, null)
                else Hit(s.bar, s.step, s.stroke, if (abs(dt) <= GOOD_WINDOW) Grade.GOOD else Grade.OFF, dt)
            }
            val extras = candidates.withIndex().filter { it.index !in used }.map { it.value - timeline.start }
            return StrumScore(hits, extras)
        }
    }
}

/** 和弦进行的分段成绩：每个和弦（进行里的位置）各自的得分，以及“换和弦后第一下扫弦”的偏差。 */
class ProgressionReport(
    val segments: List<Segment>, val changes: List<Change>, val changeMeanMs: Double?, val otherMeanMs: Double?,
) {
    data class Segment(val index: Int, val name: String, val score: Int, val expected: Int)

    /** 换到进行里第几个和弦后第一下：平均偏差（毫秒，正数 = 慢；全漏是 null）、统计到的次数（含漏掉的）、漏掉几次。 */
    data class Change(val index: Int, val name: String, val meanMs: Double?, val count: Int, val missed: Int)

    /** 换和弦处的建议；没什么问题就是 null。 */
    val advice: Advice?
        get() {
            fun ms(v: Double) = abs(v).roundToInt()
            val worst = changes.filter { (it.meanMs ?: 0.0) > 40 }.maxByOrNull { it.meanMs ?: 0.0 }
            val late = worst?.meanMs
            if (worst != null && late != null) return Advice("换到 %@ 时普遍晚了 %lld 毫秒，可以提前准备按法。", listOf(worst.name, ms(late)))
            val atChanges = changes.sumOf { it.count }
            val missedAtChanges = changes.sumOf { it.missed }
            if (atChanges >= 2 && missedAtChanges.toDouble() / atChanges >= 0.5) return Advice("换和弦后的第一下常常没扫到，换把时右手别停，先扫空弦也可以。")
            val c = changeMeanMs
            val o = otherMeanMs
            if (c != null && o != null && c - o > 30) return Advice("换和弦后的第一下平均比其他时候晚 %lld 毫秒，在上一小节最后一拍就开始换把。", listOf(ms(c - o)))
            return null
        }

    companion object {
        /** @param names 进行里每个和弦的名字（按当前的音名写法） */
        fun make(score: StrumScore, timeline: StrumTimeline, plan: ProgressionPlan, names: List<String>): ProgressionReport {
            // 每个和弦一段：只算属于它的小节里的格；多扫按它落在哪一小节算给那个和弦
            val segments = names.indices.map { i ->
                val hits = score.hits.filter { plan.chordIndex(it.bar) == i }
                val extras = score.extras.filter { plan.chordIndex((max(0.0, it) / timeline.barDuration).toInt()) == i }
                val part = StrumScore(hits, extras)
                Segment(i, names[i], part.score, part.expected)
            }.filter { it.expected > 0 }

            // 换和弦处：这一小节第一个该扫的格
            val firstAtChange = ArrayList<Pair<Int, StrumScore.Hit>>()
            val changeBars = plan.changeBars.toSet()
            for (bar in plan.changeBars) {
                val first = score.hits.filter { it.bar == bar }.minByOrNull { it.step }
                if (first != null) firstAtChange.add(plan.chordIndex(bar) to first)
            }
            val changes = firstAtChange.map { it.first }.toSortedSet().map { target ->
                val list = firstAtChange.filter { it.first == target }.map { it.second }
                val offsets = list.mapNotNull { it.offset }
                Change(target, names[target], if (offsets.isEmpty()) null else offsets.sum() / offsets.size * 1000, list.size, list.count { it.grade == StrumScore.Grade.MISSED })
            }
            val changeOffsets = firstAtChange.mapNotNull { it.second.offset }
            val firstKeys = firstAtChange.map { "${it.second.bar}-${it.second.step}" }.toSet()
            val otherOffsets = score.hits.filter { !(it.bar in changeBars && "${it.bar}-${it.step}" in firstKeys) }.mapNotNull { it.offset }
            fun mean(v: List<Double>) = if (v.isEmpty()) null else v.sum() / v.size * 1000
            return ProgressionReport(segments, changes, mean(changeOffsets), mean(otherOffsets))
        }
    }
}

/** 一次跟练：可以指定练几遍（一遍 = 整个和弦进行走一遍），也可以不限遍数一直练到用户点“结束”。每遍单独打分。 */
class PracticeRun(target: Int?, passBars: Int) {
    /** 要练几遍；null = 一直练。 */
    val target: Int? = target?.coerceIn(TARGET_RANGE)
    val passBars: Int = max(1, passBars)
    private val _passes = ArrayList<StrumScore>()
    val passes: List<StrumScore> get() = _passes

    fun add(score: StrumScore) { _passes.add(score) }

    /** 练够指定的遍数就结束；一直练时永远不会自己结束。 */
    val isComplete: Boolean get() = target != null && _passes.size >= target

    /** 还要不要再排下一遍（已经排好的遍数 `scheduled`）。 */
    fun needsPass(scheduled: Int): Boolean = target == null || scheduled < target

    val passScores: List<Int> get() = _passes.map { it.score }

    /** 各遍的平均分（四舍五入）；一遍都没练完是 null。 */
    val averageScore: Int? get() = if (_passes.isEmpty()) null else (passScores.sum().toDouble() / _passes.size).roundToInt()

    /** 最好的一遍：第几遍（从 1 起）和分数。 */
    val best: Pair<Int, Int>? get() = passScores.indices.maxByOrNull { passScores[it] }?.let { (it + 1) to passScores[it] }

    /** 把所有遍拼成一份成绩（小节号按遍往后接），用来算总的准 / 偏 / 漏、偏差和建议。 */
    val combined: StrumScore?
        get() {
            if (_passes.isEmpty()) return null
            val hits = ArrayList<StrumScore.Hit>()
            val extras = ArrayList<Double>()
            for ((k, p) in _passes.withIndex()) {
                hits += p.hits.map { it.copy(bar = it.bar + k * passBars) }
                extras += p.extras
            }
            return StrumScore(hits, extras)
        }

    companion object {
        val TARGET_RANGE = 1..99
    }
}

/** 每次跟练的成绩历史（本机）：训练页卡片显示上次成绩和这个节奏型的最好成绩。 */
class StrumHistory(private val store: com.example.strumcoach.settings.KeyValueStore) {
    @kotlinx.serialization.Serializable
    data class Entry(val dateMillis: Long, val patternID: String, val progression: String, val bpm: Int, val score: Int, val family: String? = null)

    private val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
    var entries: List<Entry> = store.getString(KEY)?.let { runCatching { json.decodeFromString<List<Entry>>(it) }.getOrNull() } ?: emptyList()
        private set

    fun add(entry: Entry) {
        entries = (entries + entry).takeLast(MAX)
        store.putString(KEY, json.encodeToString(kotlinx.serialization.builtins.ListSerializer(Entry.serializer()), entries))
    }

    val last: Entry? get() = entries.lastOrNull()
    fun best(patternID: String): Int? = entries.filter { it.patternID == patternID }.maxOfOrNull { it.score }

    private companion object {
        const val KEY = "strum.history"
        const val MAX = 200
    }
}

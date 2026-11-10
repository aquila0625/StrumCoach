package com.example.tunebeatchord.practice

import com.example.tunebeatchord.rhythm.PracticeMode
import com.example.tunebeatchord.settings.KeyValueStore
import com.example.tunebeatchord.settings.MemoryStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/** 一次练习记录。`startedAt` 是开始的时刻（毫秒），`duration` 是实际时长（秒）。 */
@Serializable
data class PracticeSession(
    val id: String = java.util.UUID.randomUUID().toString(),
    val startedAtMillis: Long,
    val duration: Double,
    val minBPM: Int,
    val maxBPM: Int,
    val modeId: String = PracticeMode.FREE.id,
) {
    val mode: PracticeMode get() = PracticeMode.fromId(modeId)
    val startedAt: Instant get() = Instant.ofEpochMilli(startedAtMillis)
    val endedAt: Instant get() = startedAt.plusMillis((duration * 1000).toLong())

    companion object {
        /** 速度范围顺序反了也会被纠正。 */
        fun make(startedAtMillis: Long, duration: Double, bpmA: Int, bpmB: Int, mode: PracticeMode = PracticeMode.FREE) =
            PracticeSession(startedAtMillis = startedAtMillis, duration = duration, minBPM = minOf(bpmA, bpmB), maxBPM = maxOf(bpmA, bpmB), modeId = mode.id)
    }
}

/** 练习记录的入库规则。 */
object PracticeRecording {
    /** 少于这个时长（秒）的播放不记录。刚好 30 秒算有效。 */
    const val MINIMUM_DURATION = 30.0

    fun shouldRecord(duration: Double) = duration >= MINIMUM_DURATION
}

data class DailyPractice(val day: LocalDate, val duration: Double)

/**
 * 练习统计。`zone` 决定时区，`firstDayOfWeek` 决定一周从哪天开始（默认周一）。
 *
 * - 少于 30 秒的记录一律不计；
 * - 一条记录整条算在它开始那天，不拆分跨午夜的部分；
 * - 日界线按 `zone` 的日历日算（用 LocalDate 加减天数，夏令时切换日不会出错）。
 */
class PracticeStatistics(val zone: ZoneId = ZoneId.systemDefault(), val firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY) {
    private fun valid(records: List<PracticeSession>) = records.filter { PracticeRecording.shouldRecord(it.duration) }
    private fun day(s: PracticeSession): LocalDate = s.startedAt.atZone(zone).toLocalDate()

    /** 本周总时长，单位秒。 */
    fun weeklyTotal(records: List<PracticeSession>, now: Instant = Instant.now()): Double {
        val today = now.atZone(zone).toLocalDate()
        val start = today.with(TemporalAdjusters.previousOrSame(firstDayOfWeek))
        val end = start.plusDays(7)
        return valid(records).filter { val d = day(it); !d.isBefore(start) && d.isBefore(end) }.sumOf { it.duration }
    }

    /** 最近 `days` 天（默认 7）每天的时长，从最早到今天，没练的天是 0。 */
    fun dailyDurations(records: List<PracticeSession>, now: Instant = Instant.now(), days: Int = 7): List<DailyPractice> {
        val byDay = HashMap<LocalDate, Double>()
        for (r in valid(records)) byDay[day(r)] = (byDay[day(r)] ?: 0.0) + r.duration
        val today = now.atZone(zone).toLocalDate()
        return (0 until maxOf(0, days)).reversed().map { offset ->
            val d = today.minusDays(offset.toLong())
            DailyPractice(d, byDay[d] ?: 0.0)
        }
    }

    /** 连续打卡天数。今天练了就算上今天；今天还没练则从昨天往前数（今天结束前不断档）。 */
    fun currentStreak(records: List<PracticeSession>, now: Instant = Instant.now()): Int {
        val today = now.atZone(zone).toLocalDate()
        val days = valid(records).map { day(it) }.toSet()
        var cursor = if (today in days) today else today.minusDays(1)
        var count = 0
        while (cursor in days) {
            count++
            cursor = cursor.minusDays(1)
        }
        return count
    }

    /** 最近的练习，新的在前。 */
    fun recent(records: List<PracticeSession>, limit: Int = 20): List<PracticeSession> =
        valid(records).sortedByDescending { it.startedAtMillis }.take(maxOf(0, limit))
}

/** 练习记录的本机存储（一个 JSON 数组，只在设备上）。 */
class PracticeLog(private val store: KeyValueStore = MemoryStore()) {
    private val json = Json { ignoreUnknownKeys = true }
    private var cache: List<PracticeSession>? = null

    val sessions: List<PracticeSession>
        @Synchronized get() = cache ?: load().also { cache = it }

    private fun load(): List<PracticeSession> =
        store.getString(KEY)?.let { runCatching { json.decodeFromString<List<PracticeSession>>(it) }.getOrNull() } ?: emptyList()

    /** 停止播放时调用。时长不足 30 秒返回 null 且不写入；否则存下并返回这条记录。 */
    @Synchronized
    fun record(startedAtMillis: Long, duration: Double, bpmRange: IntRange, mode: PracticeMode): PracticeSession? {
        if (!PracticeRecording.shouldRecord(duration)) return null
        val session = PracticeSession.make(startedAtMillis, duration, bpmRange.first, bpmRange.last, mode)
        val list = sessions + session
        cache = list
        store.putString(KEY, json.encodeToString(list))
        return session
    }

    @Synchronized
    fun clear() {
        cache = emptyList()
        store.putString(KEY, null)
    }

    private companion object {
        const val KEY = "practice.sessions"
    }
}

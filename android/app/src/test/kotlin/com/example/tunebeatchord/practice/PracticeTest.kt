package com.example.tunebeatchord.practice

import com.example.tunebeatchord.rhythm.PracticeMode
import com.example.tunebeatchord.settings.FileStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

class PracticeTest {
    private val ny = ZoneId.of("America/New_York")

    private fun at(zone: ZoneId, y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0): Instant = LocalDateTime.of(y, m, d, h, min).atZone(zone).toInstant()
    private fun rec(t: Instant, duration: Double) = PracticeSession.make(t.toEpochMilli(), duration, 100, 100)
    private fun stats(zone: ZoneId = ny, first: DayOfWeek = DayOfWeek.SUNDAY) = PracticeStatistics(zone, first)

    @Test fun recordingBoundary() {
        assertFalse(PracticeRecording.shouldRecord(29.0)); assertFalse(PracticeRecording.shouldRecord(29.999))
        assertTrue(PracticeRecording.shouldRecord(30.0)); assertFalse(PracticeRecording.shouldRecord(0.0)); assertFalse(PracticeRecording.shouldRecord(-5.0))
    }

    @Test fun statsIgnoreShortRecords() {
        val now = at(ny, 2026, 5, 13)
        val r = listOf(rec(now, 29.0), rec(now, 30.0))
        assertEquals(30.0, stats().weeklyTotal(r, now), 0.0)
        assertEquals(0, stats().currentStreak(listOf(rec(now, 29.0)), now))
        assertEquals(1, stats().recent(r).size)
        assertEquals(30.0, stats().dailyDurations(r, now).last().duration, 0.0)
    }

    @Test fun weeklyTotalDependsOnFirstWeekday() {
        val now = at(ny, 2026, 5, 13)
        val all = listOf(rec(at(ny, 2026, 5, 10, 9), 100.0), rec(at(ny, 2026, 5, 11, 9), 200.0), rec(at(ny, 2026, 5, 9, 23, 59), 400.0))
        assertEquals(300.0, stats(first = DayOfWeek.SUNDAY).weeklyTotal(all, now), 0.0)
        assertEquals(200.0, stats(first = DayOfWeek.MONDAY).weeklyTotal(all, now), 0.0)
        val before = rec(at(ny, 2026, 5, 10, 23, 59), 60.0); val start = rec(at(ny, 2026, 5, 11, 0, 0), 90.0)
        assertEquals(90.0, stats(first = DayOfWeek.MONDAY).weeklyTotal(listOf(before, start), now), 0.0)
        assertEquals(0.0, stats().weeklyTotal(emptyList(), Instant.now()), 0.0)
    }

    @Test fun lastSevenDays() {
        val now = at(ny, 2026, 5, 13, 8)
        val r = listOf(rec(at(ny, 2026, 5, 13, 7), 60.0), rec(at(ny, 2026, 5, 13, 7, 30), 40.0), rec(at(ny, 2026, 5, 11, 20), 300.0),
            rec(at(ny, 2026, 5, 7, 0, 0), 120.0), rec(at(ny, 2026, 5, 6, 23, 59), 999.0))
        val days = stats().dailyDurations(r, now)
        assertEquals(7, days.size); assertEquals(7, days.first().day.dayOfMonth); assertEquals(13, days.last().day.dayOfMonth)
        assertEquals(listOf(120.0, 0.0, 0.0, 0.0, 300.0, 0.0, 100.0), days.map { it.duration })
        // 夏令时那一周仍是连续 7 个日历日
        assertEquals(listOf(4, 5, 6, 7, 8, 9, 10), stats().dailyDurations(emptyList(), at(ny, 2026, 3, 10)).map { it.day.dayOfMonth })
    }

    @Test fun streak() {
        val now = at(ny, 2026, 5, 13, 20)
        assertEquals(3, stats().currentStreak(listOf(13, 12, 11).map { rec(at(ny, 2026, 5, it, 9), 60.0) }, now))
        assertEquals(2, stats().currentStreak(listOf(12, 11).map { rec(at(ny, 2026, 5, it, 9), 60.0) }, now))
        assertEquals(0, stats().currentStreak(listOf(rec(at(ny, 2026, 5, 11, 9), 60.0)), now))
        assertEquals(2, stats().currentStreak(listOf(13, 12, 10, 9, 8).map { rec(at(ny, 2026, 5, it, 9), 60.0) }, at(ny, 2026, 5, 13)))
        assertEquals(1, stats().currentStreak(listOf(rec(at(ny, 2026, 5, 13, 8), 60.0), rec(at(ny, 2026, 5, 13, 21), 60.0)), at(ny, 2026, 5, 13)))
        assertEquals(0, stats().currentStreak(emptyList(), now))
        assertEquals(0, stats().currentStreak(listOf(rec(at(ny, 2026, 5, 20, 9), 60.0)), at(ny, 2026, 5, 13)))
    }

    @Test fun streakAcrossMidnightAndTimeZones() {
        val r = listOf(rec(at(ny, 2026, 5, 12, 23, 59), 60.0), rec(at(ny, 2026, 5, 13, 0, 1), 60.0))
        assertEquals(2, stats().currentStreak(r, at(ny, 2026, 5, 13, 0, 5)))
        assertEquals(1, stats().currentStreak(listOf(r[0]), at(ny, 2026, 5, 13, 0, 5)))
        assertEquals(0, stats().currentStreak(listOf(r[0]), at(ny, 2026, 5, 14, 0, 5)))
        val instant = Instant.ofEpochSecond(1_778_642_400)
        val sh = ZoneId.of("Asia/Shanghai")
        val rr = listOf(rec(instant, 60.0))
        val now = instant.plusSeconds(10 * 3600)
        assertEquals(1, stats(ny).currentStreak(rr, now)); assertEquals(0.0, stats(ny).dailyDurations(rr, now).last().duration, 0.0)
        assertEquals(60.0, stats(sh).dailyDurations(rr, now).last().duration, 0.0)
    }

    @Test fun streakAcrossDaylightSaving() {
        val spring = listOf(rec(at(ny, 2026, 3, 7, 23, 30), 60.0), rec(at(ny, 2026, 3, 8, 3, 30), 60.0), rec(at(ny, 2026, 3, 9, 0, 10), 60.0))
        assertEquals(3, stats().currentStreak(spring, at(ny, 2026, 3, 9, 12)))
        assertEquals(1, stats().currentStreak(listOf(spring[0], spring[2]), at(ny, 2026, 3, 9, 12)))
        assertEquals(listOf(60.0, 60.0, 60.0), stats().dailyDurations(spring, at(ny, 2026, 3, 9, 0, 10), days = 3).map { it.duration })
        val fall = listOf(rec(at(ny, 2026, 10, 31, 23, 50), 60.0), rec(at(ny, 2026, 11, 1, 0, 30), 60.0), rec(at(ny, 2026, 11, 1, 23, 50), 60.0), rec(at(ny, 2026, 11, 2, 0, 5), 60.0))
        assertEquals(3, stats().currentStreak(fall, at(ny, 2026, 11, 2, 9)))
        assertEquals(listOf(60.0, 120.0, 60.0), stats().dailyDurations(fall, at(ny, 2026, 11, 2, 9), days = 3).map { it.duration })
        val sp = ZoneId.of("America/Sao_Paulo")
        val base = 1_541_289_600L
        val saoPaulo = listOf(base - 36_000, base + 21_600, base + 108_000).map { rec(Instant.ofEpochSecond(it), 60.0) }
        assertEquals(3, stats(sp).currentStreak(saoPaulo, Instant.ofEpochSecond(base + 115_200)))
    }

    @Test fun recentSortedAndLimited() {
        val base = at(ny, 2026, 5, 1)
        val r = (0 until 30).map { rec(base.plusSeconds(it * 3600L), 60.0 + it) }.shuffled()
        assertEquals(listOf(89.0, 88.0, 87.0, 86.0, 85.0), stats().recent(r, 5).map { it.duration })
        assertEquals(0, stats().recent(r, 0).size); assertEquals(30, stats().recent(r, 100).size)
    }

    @Test fun sessionFieldsAndLog() {
        val s = PracticeSession.make(1_000_000_000, 90.0, 120, 80, PracticeMode.RAMP_AND_MUTE)
        assertEquals(listOf(80, 120), listOf(s.minBPM, s.maxBPM)); assertEquals(PracticeMode.RAMP_AND_MUTE, s.mode)
        assertEquals(1_000_090_000L, s.endedAt.toEpochMilli()); assertEquals(PracticeMode.FREE, s.copy(modeId = "somethingNew").mode)
        val dir = java.nio.file.Files.createTempDirectory("practice").toFile()
        val log = PracticeLog(FileStore(dir))
        assertNull(log.record(0, 29.0, 100..100, PracticeMode.FREE))
        assertNotNull(log.record(1_000, 120.0, 80..96, PracticeMode.RAMP))
        // 重新打开：从文件读回来
        val again = PracticeLog(FileStore(dir))
        assertEquals(1, again.sessions.size)
        assertEquals(80..96, again.sessions[0].minBPM..again.sessions[0].maxBPM); assertEquals(PracticeMode.RAMP, again.sessions[0].mode)
        again.clear(); assertEquals(0, PracticeLog(FileStore(dir)).sessions.size)
        dir.deleteRecursively()
    }
}

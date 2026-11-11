package com.example.tunebeatchord.metronome

import com.example.tunebeatchord.practice.PracticeLog
import com.example.tunebeatchord.rhythm.PracticeMode
import com.example.tunebeatchord.settings.MemoryStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PracticeGoalTest {
    private val now = 1_800_000_000_000L   // 固定的“此刻”

    private fun controller(store: MemoryStore = MemoryStore(), log: PracticeLog = PracticeLog(), clock: () -> Long = { now }) =
        MetronomeController(null, store, log, wallClockMillis = clock)

    @Test fun defaultsAreOffAndTwentyMinutes() {
        val o = TrainingOptions()
        assertEquals(false, o.timerEnabled)
        assertEquals(20, o.timerMinutes)
        assertEquals(false, o.timerAutoStop)
    }

    @Test fun todayStartsFromTodaysRecordedPractice() {
        val log = PracticeLog()
        log.record(now - 3_600_000, 600.0, 80..80, PracticeMode.FREE)        // 一小时前练了 10 分钟
        log.record(now - 3 * 86_400_000L, 1200.0, 80..80, PracticeMode.FREE) // 三天前的不算
        log.record(now - 7_200_000, 10.0, 80..80, PracticeMode.FREE)          // 不足 30 秒不记
        assertEquals(600, controller(log = log).todaySeconds)
    }

    @Test fun reminderFiresOncePerDayWhenGoalReached() {
        val store = MemoryStore()
        var fired = 0
        val m = controller(store)
        m.onGoalReached = { fired++ }
        m.updateOptions { it.copy(timerEnabled = true, timerMinutes = 5) }
        m.updateToday(299.0); assertNull(m.notice); assertEquals(0, fired)
        m.updateToday(300.0)
        assertEquals(MetronomeController.Notice.TIMER_REACHED, m.notice)
        assertEquals(1, fired)
        m.notice = null
        m.updateToday(301.0); assertEquals(1, fired); assertNull(m.notice)   // 同一天不再提醒
        // 重开应用、同一天：还是不再提醒
        val again = controller(store)
        again.onGoalReached = { fired++ }
        again.updateOptions { it.copy(timerEnabled = true, timerMinutes = 5) }
        again.updateToday(400.0)
        assertEquals(1, fired)
        // 第二天会再提醒
        val tomorrow = controller(store) { now + 86_400_000L }
        tomorrow.onGoalReached = { fired++ }
        tomorrow.updateOptions { it.copy(timerEnabled = true, timerMinutes = 5) }
        tomorrow.updateToday(400.0)
        assertEquals(2, fired)
    }

    @Test fun disabledTimerNeverFires() {
        var fired = 0
        val m = controller()
        m.onGoalReached = { fired++ }
        m.updateOptions { it.copy(timerEnabled = false, timerMinutes = 5) }
        m.updateToday(10_000.0)
        assertEquals(0, fired); assertNull(m.notice)
        assertEquals(10_000, m.todaySeconds)
    }

    @Test fun baselinePlusPlayedIsCompared() {
        val log = PracticeLog()
        log.record(now - 3_600_000, 240.0, 80..80, PracticeMode.FREE)   // 已练 4 分钟
        val m = controller(log = log)
        m.updateOptions { it.copy(timerEnabled = true, timerMinutes = 5) }
        m.updateToday(59.0); assertNull(m.notice)
        m.updateToday(60.0); assertEquals(MetronomeController.Notice.TIMER_REACHED, m.notice)
    }

    @Test fun oldSavedZeroMinutesBecomesTwenty() {
        val store = MemoryStore()
        store.putString("metronome.config", """{"training":{"timerMinutes":0}}""")
        assertEquals(20, MetronomeController(null, store).options.timerMinutes)
    }
}

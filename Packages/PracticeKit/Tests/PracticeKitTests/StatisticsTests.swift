import XCTest
@testable import PracticeKit

private struct Rec: PracticeRecord {
    var startedAt: Date
    var duration: TimeInterval
}

private func makeCalendar(_ zone: String, firstWeekday: Int = 1) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    c.firstWeekday = firstWeekday
    return c
}

private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

final class StatisticsTests: XCTestCase {
    let ny = makeCalendar("America/New_York")

    private func stats(_ cal: Calendar? = nil) -> PracticeStatistics { PracticeStatistics(calendar: cal ?? ny) }

    // MARK: 30 秒边界

    func testRecordingBoundary() {
        XCTAssertFalse(PracticeRecording.shouldRecord(duration: 29))
        XCTAssertFalse(PracticeRecording.shouldRecord(duration: 29.999))
        XCTAssertTrue(PracticeRecording.shouldRecord(duration: 30))
        XCTAssertFalse(PracticeRecording.shouldRecord(duration: 0))
        XCTAssertFalse(PracticeRecording.shouldRecord(duration: -5))
    }

    func testStatsIgnoreShortRecords() {
        let now = date(ny, 2026, 5, 13)
        let records = [Rec(startedAt: now, duration: 29), Rec(startedAt: now, duration: 30)]
        XCTAssertEqual(stats().weeklyTotal(of: records, now: now), 30)
        XCTAssertEqual(stats().currentStreak(of: [Rec(startedAt: now, duration: 29)], now: now), 0)
        XCTAssertEqual(stats().recent(records).count, 1)
        XCTAssertEqual(stats().dailyDurations(of: records, now: now).last?.duration, 30)
    }

    // MARK: 本周总时长

    func testWeeklyTotalDependsOnFirstWeekday() {
        // 2026-05-13 是周三。周日/周一为一周起点会不同。
        let now = date(ny, 2026, 5, 13)
        let sunday = Rec(startedAt: date(ny, 2026, 5, 10, 9), duration: 100)   // 周日
        let monday = Rec(startedAt: date(ny, 2026, 5, 11, 9), duration: 200)
        let lastSat = Rec(startedAt: date(ny, 2026, 5, 9, 23, 59), duration: 400)
        let all = [sunday, monday, lastSat]
        XCTAssertEqual(stats(makeCalendar("America/New_York", firstWeekday: 1)).weeklyTotal(of: all, now: now), 300)
        XCTAssertEqual(stats(makeCalendar("America/New_York", firstWeekday: 2)).weeklyTotal(of: all, now: now), 200)
    }

    func testWeeklyTotalBoundaryAtWeekStartMidnight() {
        let cal = makeCalendar("America/New_York", firstWeekday: 2)
        let now = date(cal, 2026, 5, 13)
        let justBefore = Rec(startedAt: date(cal, 2026, 5, 10, 23, 59), duration: 60)
        let exactlyStart = Rec(startedAt: date(cal, 2026, 5, 11, 0, 0), duration: 90)
        XCTAssertEqual(stats(cal).weeklyTotal(of: [justBefore, exactlyStart], now: now), 90)
    }

    func testWeeklyTotalEmpty() {
        XCTAssertEqual(stats().weeklyTotal(of: [Rec](), now: Date()), 0)
    }

    // MARK: 最近 7 天

    func testLastSevenDays() {
        let now = date(ny, 2026, 5, 13, 8)
        let records = [
            Rec(startedAt: date(ny, 2026, 5, 13, 7), duration: 60),
            Rec(startedAt: date(ny, 2026, 5, 13, 7, 30), duration: 40),
            Rec(startedAt: date(ny, 2026, 5, 11, 20), duration: 300),
            Rec(startedAt: date(ny, 2026, 5, 7, 0, 0), duration: 120),   // 第 7 天（含）的 0 点
            Rec(startedAt: date(ny, 2026, 5, 6, 23, 59), duration: 999), // 7 天之外
        ]
        let days = stats().dailyDurations(of: records, now: now)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.day, date(ny, 2026, 5, 7, 0, 0))
        XCTAssertEqual(days.last?.day, date(ny, 2026, 5, 13, 0, 0))
        XCTAssertEqual(days.map(\.duration), [120, 0, 0, 0, 300, 0, 100])
    }

    func testLastSevenDaysAcrossDST() {
        // 2026-03-08 美东 02:00 拨快，当天只有 23 小时；日期序列仍应连续 7 个不同日历日
        let now = date(ny, 2026, 3, 10, 12)
        let days = stats().dailyDurations(of: [Rec](), now: now)
        let comps = days.map { ny.dateComponents([.month, .day, .hour, .minute], from: $0.day) }
        XCTAssertEqual(comps.map { $0.day! }, [4, 5, 6, 7, 8, 9, 10])
        XCTAssertTrue(comps.allSatisfy { $0.hour == 0 && $0.minute == 0 })
    }

    // MARK: 连续打卡

    func testStreakCountsTodayWhenPracticed() {
        let now = date(ny, 2026, 5, 13, 20)
        let r = [date(ny, 2026, 5, 13, 9), date(ny, 2026, 5, 12, 9), date(ny, 2026, 5, 11, 9)]
            .map { Rec(startedAt: $0, duration: 60) }
        XCTAssertEqual(stats().currentStreak(of: r, now: now), 3)
    }

    func testStreakNotBrokenUntilTodayEnds() {
        let now = date(ny, 2026, 5, 13, 20)   // 今天还没练
        let yesterdayAndBefore = [date(ny, 2026, 5, 12, 9), date(ny, 2026, 5, 11, 9)].map { Rec(startedAt: $0, duration: 60) }
        XCTAssertEqual(stats().currentStreak(of: yesterdayAndBefore, now: now), 2)
        let stale = [Rec(startedAt: date(ny, 2026, 5, 11, 9), duration: 60)]   // 前天练过，昨天断了
        XCTAssertEqual(stats().currentStreak(of: stale, now: now), 0)
    }

    func testStreakGapBreaksChain() {
        let now = date(ny, 2026, 5, 13)
        let r = [13, 12, 10, 9, 8].map { Rec(startedAt: date(ny, 2026, 5, $0, 9), duration: 60) }
        XCTAssertEqual(stats().currentStreak(of: r, now: now), 2)
    }

    func testStreakMultipleSessionsSameDayCountOnce() {
        let now = date(ny, 2026, 5, 13)
        let r = [Rec(startedAt: date(ny, 2026, 5, 13, 8), duration: 60), Rec(startedAt: date(ny, 2026, 5, 13, 21), duration: 60)]
        XCTAssertEqual(stats().currentStreak(of: r, now: now), 1)
    }

    func testStreakEmptyAndFutureRecords() {
        let now = date(ny, 2026, 5, 13)
        XCTAssertEqual(stats().currentStreak(of: [Rec](), now: now), 0)
        // 时钟被调快留下的未来记录不算
        let future = [Rec(startedAt: date(ny, 2026, 5, 20, 9), duration: 60)]
        XCTAssertEqual(stats().currentStreak(of: future, now: now), 0)
    }

    func testStreakAcrossMidnight() {
        // 23:59 和 00:01 只差 2 分钟，但是两个日历日
        let r = [Rec(startedAt: date(ny, 2026, 5, 12, 23, 59), duration: 60),
                 Rec(startedAt: date(ny, 2026, 5, 13, 0, 1), duration: 60)]
        XCTAssertEqual(stats().currentStreak(of: r, now: date(ny, 2026, 5, 13, 0, 5)), 2)
        // 23:59 的那条在午夜后“今天”看就是昨天
        XCTAssertEqual(stats().currentStreak(of: [r[0]], now: date(ny, 2026, 5, 13, 0, 5)), 1)
        XCTAssertEqual(stats().currentStreak(of: [r[0]], now: date(ny, 2026, 5, 14, 0, 5)), 0)
    }

    func testStreakDependsOnUserTimeZone() {
        // 同一个时刻：UTC 2026-05-13 03:30 = 纽约 5-12 23:30 = 上海 5-13 11:30
        let instant = Date(timeIntervalSince1970: 1_778_642_400)   // 2026-05-13T03:20:00Z
        let cal1 = makeCalendar("America/New_York"), cal2 = makeCalendar("Asia/Shanghai")
        XCTAssertEqual(cal1.component(.day, from: instant), 12)
        XCTAssertEqual(cal2.component(.day, from: instant), 13)
        let rec = [Rec(startedAt: instant, duration: 60)]
        // 对纽约用户：此刻（纽约 5-13 中午）练习是昨天；上海用户是今天
        let now = instant.addingTimeInterval(10 * 3600)
        XCTAssertEqual(cal1.component(.day, from: now), 13)
        XCTAssertEqual(stats(cal1).currentStreak(of: rec, now: now), 1)   // 昨天算起
        XCTAssertEqual(stats(cal1).dailyDurations(of: rec, now: now).last?.duration, 0)
        XCTAssertEqual(cal2.component(.day, from: now), 13)
        XCTAssertEqual(stats(cal2).dailyDurations(of: rec, now: now).last?.duration, 60)
    }

    func testStreakAcrossSpringForwardDST() {
        // 2026-03-08 美东 2:00→3:00，当天 23 小时
        let r = [
            Rec(startedAt: date(ny, 2026, 3, 7, 23, 30), duration: 60),
            Rec(startedAt: date(ny, 2026, 3, 8, 3, 30), duration: 60),     // 拨快后
            Rec(startedAt: date(ny, 2026, 3, 9, 0, 10), duration: 60),
        ]
        XCTAssertEqual(stats().currentStreak(of: r, now: date(ny, 2026, 3, 9, 12)), 3)
        // 中间隔了一天（3-8 没练）要断
        let gap = [r[0], r[2]]
        XCTAssertEqual(stats().currentStreak(of: gap, now: date(ny, 2026, 3, 9, 12)), 1)
        // 反例：直接减 86400 秒会跳过 3-8（落到 3-7），所以实现用的是日历加减天数而不是减秒数
        XCTAssertEqual(ny.startOfDay(for: date(ny, 2026, 3, 9, 0, 10).addingTimeInterval(-86_400)), date(ny, 2026, 3, 7, 0, 0))
        XCTAssertEqual(stats().dailyDurations(of: r, now: date(ny, 2026, 3, 9, 0, 10), days: 3).map(\.duration), [60, 60, 60])
    }

    func testStreakAcrossFallBackDST() {
        // 2026-11-01 美东 2:00→1:00，当天 25 小时
        let r = [
            Rec(startedAt: date(ny, 2026, 10, 31, 23, 50), duration: 60),
            Rec(startedAt: date(ny, 2026, 11, 1, 0, 30), duration: 60),
            Rec(startedAt: date(ny, 2026, 11, 1, 23, 50), duration: 60),   // 25 小时日的最后几分钟
            Rec(startedAt: date(ny, 2026, 11, 2, 0, 5), duration: 60),
        ]
        XCTAssertEqual(stats().currentStreak(of: r, now: date(ny, 2026, 11, 2, 9)), 3)
        let days = stats().dailyDurations(of: r, now: date(ny, 2026, 11, 2, 9), days: 3)
        XCTAssertEqual(days.map(\.duration), [60, 120, 60])
        // 只在 25 小时那天开头练过，次日检查：今天没练 → 从昨天算起
        XCTAssertEqual(stats().currentStreak(of: [r[1]], now: date(ny, 2026, 11, 2, 9)), 1)
        XCTAssertEqual(stats().currentStreak(of: [r[1]], now: date(ny, 2026, 11, 3, 9)), 0)
    }

    func testStreakInTimeZoneWithMidnightDST() {
        // 圣保罗历史上在午夜拨快（2018-11-04 00:00 → 01:00，当天没有 0 点）
        let sp = makeCalendar("America/Sao_Paulo")
        let r = [
            Rec(startedAt: Date(timeIntervalSince1970: 1_541_289_600 - 3600 * 10), duration: 60), // 2018-11-03 下午
            Rec(startedAt: Date(timeIntervalSince1970: 1_541_289_600 + 3600 * 6), duration: 60),  // 2018-11-04 凌晨之后
            Rec(startedAt: Date(timeIntervalSince1970: 1_541_289_600 + 3600 * 30), duration: 60), // 2018-11-05
        ]
        let now = Date(timeIntervalSince1970: 1_541_289_600 + 3600 * 32)
        XCTAssertEqual(stats(sp).currentStreak(of: r, now: now), 3)
    }

    // MARK: 最近练习

    func testRecentSortedAndLimited() {
        let base = date(ny, 2026, 5, 1)
        let r = (0..<30).map { Rec(startedAt: base.addingTimeInterval(Double($0) * 3600), duration: 60 + Double($0)) }.shuffled()
        let recent = stats().recent(r, limit: 5)
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.map(\.duration), [89, 88, 87, 86, 85])
        XCTAssertEqual(stats().recent(r, limit: 0).count, 0)
        XCTAssertEqual(stats().recent(r, limit: 100).count, 30)
    }
}

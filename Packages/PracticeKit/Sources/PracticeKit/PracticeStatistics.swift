import Foundation

/// 统计只需要这两个字段，方便不用 SwiftData 也能测试。`PracticeSession` 已遵守。
public protocol PracticeRecord {
    var startedAt: Date { get }
    var duration: TimeInterval { get }
}

extension PracticeSession: PracticeRecord {}

public struct DailyPractice: Equatable, Sendable {
    /// 当天 0 点（在 `calendar` 的时区里）。
    public var day: Date
    public var duration: TimeInterval
}

/// 练习统计。`calendar` 决定时区和每周第一天，传用户当前的 `Calendar.current` 即可。
///
/// 规则：
/// - 少于 30 秒的记录一律不计（入库时已经过滤，这里再兜底一次）。
/// - 一条记录整条算在它开始那天，不拆分跨午夜的部分。
/// - 日界线按 `calendar` 的日历日算，夏令时切换日（23 / 25 小时）不会出错。
public struct PracticeStatistics: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private func valid<S: Sequence>(_ records: S) -> [S.Element] where S.Element: PracticeRecord {
        records.filter { PracticeRecording.shouldRecord(duration: $0.duration) }
    }

    /// 本周（按 `calendar.firstWeekday`）总时长，单位秒。
    public func weeklyTotal<S: Sequence>(of records: S, now: Date = Date()) -> TimeInterval
    where S.Element: PracticeRecord {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        return valid(records)
            .filter { week.contains($0.startedAt) }
            .reduce(0) { $0 + $1.duration }
    }

    /// 最近 `days` 天（默认 7）每天的时长，从最早到今天，没练的天是 0。
    public func dailyDurations<S: Sequence>(of records: S, now: Date = Date(), days: Int = 7) -> [DailyPractice]
    where S.Element: PracticeRecord {
        var byDay: [Date: TimeInterval] = [:]
        for r in valid(records) {
            byDay[calendar.startOfDay(for: r.startedAt), default: 0] += r.duration
        }
        let today = calendar.startOfDay(for: now)
        return (0..<max(0, days)).reversed().map { offset in
            let day = startOfDay(daysBefore: offset, from: today)
            return DailyPractice(day: day, duration: byDay[day] ?? 0)
        }
    }

    /// 连续打卡天数。今天练了就算上今天；今天还没练则从昨天往前数（今天结束前不断档）。
    public func currentStreak<S: Sequence>(of records: S, now: Date = Date()) -> Int
    where S.Element: PracticeRecord {
        let today = calendar.startOfDay(for: now)
        let days = Set(valid(records).map { calendar.startOfDay(for: $0.startedAt) })
        var cursor = days.contains(today) ? today : startOfDay(daysBefore: 1, from: today)
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = startOfDay(daysBefore: 1, from: cursor)
        }
        return count
    }

    /// 最近的练习，新的在前。
    public func recent<S: Sequence>(_ records: S, limit: Int = 20) -> [S.Element]
    where S.Element: PracticeRecord {
        Array(valid(records).sorted { $0.startedAt > $1.startedAt }.prefix(max(0, limit)))
    }

    private func startOfDay(daysBefore n: Int, from day: Date) -> Date {
        let shifted = calendar.date(byAdding: .day, value: -n, to: day) ?? day.addingTimeInterval(-Double(n) * 86_400)
        return calendar.startOfDay(for: shifted)
    }
}

import XCTest
import SwiftData
@testable import PracticeKit

final class ModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try PracticeKitSchema.makeContainer(inMemory: true))
    }

    func testRecordDropsShortSessions() throws {
        let ctx = try makeContext()
        XCTAssertNil(PracticeRecording.record(startedAt: Date(), duration: 29, bpmRange: 100...100, mode: .free, in: ctx))
        XCTAssertNotNil(PracticeRecording.record(startedAt: Date(), duration: 30, bpmRange: 100...100, mode: .free, in: ctx))
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PracticeSession>()), 1)
    }

    func testRecordPersistsFields() throws {
        let container = try PracticeKitSchema.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_000_000)
        PracticeRecording.record(startedAt: start, duration: 120, bpmRange: 80...96, mode: .ramp, in: ctx)
        try ctx.save()
        let fetched = try ModelContext(container).fetch(FetchDescriptor<PracticeSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].bpmRange, 80...96)
        XCTAssertEqual(fetched[0].mode, .ramp)
        XCTAssertEqual(fetched[0].startedAt, start)
        XCTAssertEqual(fetched[0].duration, 120)
    }

    func testPracticeSessionFields() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let s = PracticeSession(startedAt: start, duration: 90, minBPM: 120, maxBPM: 80, mode: .rampAndMute)
        XCTAssertEqual([s.minBPM, s.maxBPM], [80, 120])   // 顺序反了也会被纠正
        XCTAssertEqual(s.mode, .rampAndMute)
        XCTAssertEqual(s.endedAt, start.addingTimeInterval(90))
        s.modeRaw = "somethingNew"   // 以后版本写入的未知模式不崩
        XCTAssertEqual(s.mode, .free)
    }

    func testStatisticsWorkDirectlyOnSwiftDataSessions() throws {
        let ctx = try makeContext()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12))!
        for daysAgo in 0..<3 {
            let t = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            PracticeRecording.record(startedAt: t, duration: 60, bpmRange: 100...100, mode: .free, in: ctx)
        }
        let all = try ctx.fetch(FetchDescriptor<PracticeSession>())
        let stats = PracticeStatistics(calendar: cal)
        XCTAssertEqual(stats.currentStreak(of: all, now: now), 3)
        XCTAssertEqual(stats.recent(all, limit: 2).count, 2)
    }
}

import XCTest
@testable import MetronomeCore

final class TapTempoTests: XCTestCase {
    func testNeedsTwoTaps() {
        var t = TapTempo()
        XCTAssertNil(t.tap(at: 10))
        XCTAssertEqual(t.tap(at: 10.5)!, 120, accuracy: 1e-9)
    }

    func testAveragesLastFourTaps() {
        var t = TapTempo()
        // 先慢后快：只看最近 4 次点按（3 个间隔）
        for time in [0.0, 1.0, 2.0] { _ = t.tap(at: time) }
        _ = t.tap(at: 2.5)
        _ = t.tap(at: 3.0)
        let bpm = t.tap(at: 3.5)!
        XCTAssertEqual(t.taps, [2.0, 2.5, 3.0, 3.5])
        XCTAssertEqual(bpm, 120, accuracy: 1e-9)
    }

    func testUnevenTapsAreAveraged() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        _ = t.tap(at: 0.4)
        _ = t.tap(at: 1.0)
        let bpm = t.tap(at: 1.5)!  // 平均间隔 0.5 s
        XCTAssertEqual(bpm, 120, accuracy: 1e-9)
    }

    func testResetsAfterTwoSecondPause() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        _ = t.tap(at: 1)
        XCTAssertNil(t.tap(at: 3.01), "超过 2 秒重新计算")
        XCTAssertEqual(t.taps, [3.01])
        XCTAssertEqual(t.tap(at: 3.51)!, 120, accuracy: 1e-6)
    }

    func testExactlyTwoSecondsStillCounts() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        XCTAssertEqual(t.tap(at: 2)!, 30, accuracy: 1e-9)
    }

    func testClampedToRange() {
        var t = TapTempo()
        _ = t.tap(at: 0)
        XCTAssertEqual(t.tap(at: 0.05), 400)
        var slow = TapTempo()
        slow.resetInterval = 10
        _ = slow.tap(at: 0)
        XCTAssertEqual(slow.tap(at: 5), 20)
    }
}

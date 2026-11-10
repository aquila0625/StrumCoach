import XCTest
@testable import TunerKit

/// 判定逻辑本身（纯值、手动推进时间）。
final class TuneConfirmationTests: XCTestCase {
    func testNeedsHalfASecondInsideFiveCents() {
        var c = TuneConfirmation()
        XCTAssertNil(c.update(key: 0, cents: 2, now: 10.0))
        XCTAssertNil(c.update(key: 0, cents: -4, now: 10.3))
        XCTAssertNil(c.update(key: 0, cents: 1, now: 10.49))
        XCTAssertEqual(c.update(key: 0, cents: 0, now: 10.5), .tuned(0))
    }

    func testLeavingTheZoneRestartsTheTimer() {
        var c = TuneConfirmation()
        _ = c.update(key: 0, cents: 1, now: 0)
        _ = c.update(key: 0, cents: 1, now: 0.4)
        XCTAssertNil(c.update(key: 0, cents: 7, now: 0.45))      // 出了 ±5
        XCTAssertNil(c.update(key: 0, cents: 1, now: 0.5))       // 重新开始计时
        XCTAssertNil(c.update(key: 0, cents: 1, now: 0.9))
        XCTAssertEqual(c.update(key: 0, cents: 1, now: 1.0), .tuned(0))
    }

    func testNoSignalRestartsTheTimerButKeepsTheLatch() {
        var c = TuneConfirmation()
        _ = c.update(key: 2, cents: 0, now: 0)
        XCTAssertEqual(c.update(key: 2, cents: 0, now: 0.5), .tuned(2))
        XCTAssertNil(c.update(key: nil, cents: nil, now: 0.6))
        XCTAssertNil(c.update(key: 2, cents: 0, now: 2))
        XCTAssertNil(c.update(key: 2, cents: 0, now: 4))         // 弦还是调准的，不再提示
        XCTAssertTrue(c.isLatched(2))
    }

    func testOnlyOncePerKeyUntilItDriftsBeyondTenCents() {
        var c = TuneConfirmation()
        _ = c.update(key: 1, cents: 0, now: 0)
        XCTAssertEqual(c.update(key: 1, cents: 0, now: 0.5), .tuned(1))
        XCTAssertNil(c.update(key: 1, cents: 0, now: 5))
        XCTAssertNil(c.update(key: 1, cents: 9.9, now: 5.1))     // 没超过 10：仍然锁着
        XCTAssertTrue(c.isLatched(1))
        XCTAssertEqual(c.update(key: 1, cents: 10.5, now: 5.2), .drifted(1))
        XCTAssertFalse(c.isLatched(1))
        XCTAssertNil(c.update(key: 1, cents: 0, now: 6))
        XCTAssertEqual(c.update(key: 1, cents: 0, now: 6.5), .tuned(1))
    }

    func testKeysAreIndependent() {
        var c = TuneConfirmation()
        _ = c.update(key: 0, cents: 0, now: 0)
        XCTAssertEqual(c.update(key: 0, cents: 0, now: 0.5), .tuned(0))
        _ = c.update(key: 1, cents: 0, now: 1)
        XCTAssertNil(c.update(key: 1, cents: 0, now: 1.4))       // 换了目标，从头计时
        XCTAssertEqual(c.update(key: 1, cents: 0, now: 1.5), .tuned(1))
        XCTAssertTrue(c.isLatched(0) && c.isLatched(1))
    }

    func testResetClearsEverything() {
        var c = TuneConfirmation()
        _ = c.update(key: 0, cents: 0, now: 0)
        _ = c.update(key: 0, cents: 0, now: 0.5)
        c.reset()
        XCTAssertFalse(c.isLatched(0))
    }

    func testChimeSynthesisIsShortQuietAndClickFree() {
        let rate = 44_100.0
        let x = TuneChime.render(sampleRate: rate)
        XCTAssertEqual(x.count, Int(TuneChime.duration * rate))
        let peak = x.map { abs($0) }.max() ?? 0
        XCTAssertEqual(peak, 0.4, accuracy: 0.01, "音量适中")
        XCTAssertEqual(x.last ?? 1, 0, accuracy: 1e-4)
        XCTAssertEqual(x.first ?? 1, 0, accuracy: 1e-3)
        // 没有跳变（咔哒）
        let maxStep = zip(x, x.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(maxStep, 0.12)
        // 两个音：开头在 E6 附近，第二个音出现后在 C6 附近
        let detector = PitchDetector()
        let first = Array(x[Int(0.012 * rate)..<Int(0.012 * rate) + 2048])
        let second = Array(x[Int(0.3 * rate)..<Int(0.3 * rate) + 2048])
        XCTAssertEqual(detector.detect(first, sampleRate: rate)?.frequency ?? 0, TuneChime.firstFrequency, accuracy: 15)
        XCTAssertEqual(detector.detect(second, sampleRate: rate)?.frequency ?? 0, TuneChime.secondFrequency, accuracy: 15)
        XCTAssertLessThan(TuneChime.duration, 1.0)
    }
}

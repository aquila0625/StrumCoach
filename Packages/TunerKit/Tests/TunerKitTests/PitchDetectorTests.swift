import XCTest
@testable import TunerKit

final class PitchDetectorTests: XCTestCase {
    let detector = PitchDetector()

    private func centsError(_ detected: Double, _ expected: Double) -> Double {
        1200 * log2(detected / expected)
    }

    func testSineAccuracyAcrossStrings() throws {
        let freqs = [82.41, 110, 146.83, 196, 246.94, 329.63, 440]
        for rate in [44100.0, 48000.0] {
            for f in freqs {
                let x = Signal.make(.sine, frequency: f, sampleRate: rate, count: 4096)
                let r = try XCTUnwrap(detector.detect(x, sampleRate: rate), "\(f) Hz @\(rate) 未检出")
                XCTAssertEqual(centsError(r.frequency, f), 0, accuracy: 1.0, "\(f) Hz @\(rate) 误差过大")
                XCTAssertGreaterThan(r.clarity, 0.95)
            }
        }
    }

    func testAccuracyWithArbitraryPhases() throws {
        for phase in stride(from: 0.0, to: 1.0, by: 0.173) {
            let x = Signal.make(.sine, frequency: 440, phase: phase)
            let r = try XCTUnwrap(detector.detect(x, sampleRate: 44100))
            XCTAssertEqual(centsError(r.frequency, 440), 0, accuracy: 1.0)
        }
    }

    func testLowBassString() throws {
        // 5 弦贝斯的 B0 ≈ 30.87 Hz
        let rate = 48000.0
        let n = PitchDetector.recommendedFrameLength(sampleRate: rate)
        let x = Signal.make(.harmonics, frequency: 30.87, sampleRate: rate, count: n)
        let r = try XCTUnwrap(detector.detect(x, sampleRate: rate))
        XCTAssertEqual(centsError(r.frequency, 30.87), 0, accuracy: 3.0)
    }

    func testSawtoothHasNoOctaveError() throws {
        for f in [82.41, 110, 196, 329.63, 440, 659.26] {
            let x = Signal.make(.sawtooth, frequency: f)
            let r = try XCTUnwrap(detector.detect(x, sampleRate: 44100), "\(f)")
            XCTAssertEqual(centsError(r.frequency, f), 0, accuracy: 5.0, "锯齿波 \(f) Hz 出现八度/倍频误判")
        }
    }

    func testWeakFundamentalHasNoOctaveError() throws {
        for f in [82.41, 110, 146.83, 196, 246.94] {
            let x = Signal.make(.harmonics, frequency: f)
            let r = try XCTUnwrap(detector.detect(x, sampleRate: 44100))
            XCTAssertEqual(centsError(r.frequency, f), 0, accuracy: 3.0, "\(f)")
        }
    }

    func testStillCorrectWithWhiteNoise() throws {
        // 单帧：信噪比 12 dB 时仍要识别成正确的音（偏差 < 15 音分，不能跳到邻音或八度）
        let freqs = [82.41, 110, 196, 329.63, 440]
        for f in freqs {
            for shape in [Signal.Shape.sine, .sawtooth] {
                let x = Signal.addNoise(Signal.make(shape, frequency: f), snrDB: 12)
                let r = try XCTUnwrap(detector.detect(x, sampleRate: 44100), "\(f) 噪声下未检出")
                XCTAssertEqual(centsError(r.frequency, f), 0, accuracy: 15, "\(f) 噪声下偏差过大")
            }
        }
    }

    func testSmoothingAveragesOutNoise() throws {
        // 连续多帧带噪声的信号，经平滑后应收敛到 ±3 音分内
        for f in [110.0, 196, 440] {
            var smoother = PitchSmoother()
            var last: PitchReading?
            for seed in 1...20 {
                let x = Signal.addNoise(Signal.make(.sawtooth, frequency: f, phase: Double(seed) * 0.37),
                                        snrDB: 12, seed: UInt64(seed))
                last = smoother.process(detector.detect(x, sampleRate: 44100), a4: 440)
            }
            XCTAssertEqual(centsError(try XCTUnwrap(last).frequency, f), 0, accuracy: 3, "\(f)")
        }
    }

    func testSilenceProducesNoPitch() {
        XCTAssertNil(detector.detect([Float](repeating: 0, count: 4096), sampleRate: 44100))
        // 极低电平的底噪
        let hiss = Signal.addNoise([Float](repeating: 0, count: 4096), snrDB: 0).map { $0 * 0.0001 }
        XCTAssertNil(detector.detect(hiss, sampleRate: 44100))
    }

    func testPureNoiseProducesNoPitch() {
        // 能量足够、但没有周期性的白噪声
        var rng = SplitMix64(seed: 7)
        let white = (0..<4096).map { _ in Float(rng.nextUnit() * 2 - 1) * 0.3 }
        XCTAssertNil(detector.detect(white, sampleRate: 44100))
    }
}

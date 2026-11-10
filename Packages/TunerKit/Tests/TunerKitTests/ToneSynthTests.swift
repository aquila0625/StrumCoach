import XCTest
@testable import TunerKit

final class ToneSynthTests: XCTestCase {
    private func render(_ timbre: ToneTimbre, frequency: Double, rate: Double = 44100, seconds: Double = 1.0) -> [Float] {
        var synth = ToneSynth()
        synth.frequency = frequency
        synth.timbre = timbre
        if timbre == .instrument {
            // 乐器音色由播放器先渲染好再载入；这里用吉他
            let tone = ReferenceTonePlayer.renderTone(.guitar, frequency: frequency, sampleRate: rate)
            synth.load(sample: tone.sample, loopStart: tone.loopStart)
        }
        synth.start()
        var out = [Float](repeating: 0, count: Int(rate * seconds))
        out.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, count: $0.count, sampleRate: rate) }
        return out
    }

    /// 参考音自己用检测器测一遍：发出的频率要准。
    func testReferenceToneIsInTuneForBothTimbres() throws {
        let detector = PitchDetector()
        for timbre in ToneTimbre.allCases {
            for f in [82.41, 220, 440, 659.26] {
                let x = render(timbre, frequency: f)
                let window = Array(x[20000..<(20000 + 4096)])
                let r = try XCTUnwrap(detector.detect(window, sampleRate: 44100), "\(timbre) \(f)")
                // 合成拨弦（Karplus-Strong）的音准误差在几个音分内，纯音和简单拨弦要求 1 音分
                XCTAssertEqual(1200 * log2(r.frequency / f), 0, accuracy: timbre == .instrument ? 5 : 1.0, "\(timbre) \(f)")
            }
        }
    }

    func testFadesOutOnStopWithoutClick() {
        var synth = ToneSynth()
        synth.frequency = 440
        synth.start()
        var buf = [Float](repeating: 0, count: 4410)
        buf.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, count: $0.count, sampleRate: 44100) }
        synth.stop()
        buf.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, count: $0.count, sampleRate: 44100) }
        XCTAssertEqual(buf.suffix(100).map(abs).max() ?? 1, 0, accuracy: 1e-6)
        XCTAssertFalse(synth.isSounding)
        let maxStep = zip(buf, buf.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(maxStep, 0.1)
    }

    func testPluckKeepsSoundingForLongerThanOneDecay() {
        let x = render(.pluck, frequency: 196, seconds: 6)
        // 重新拨弦：后面各段仍有能量
        for k in 1..<5 {
            let seg = x[(k * 44100)..<(k * 44100 + 4096)]
            XCTAssertGreaterThan(seg.map(abs).max() ?? 0, 0.02)
        }
        XCTAssertLessThanOrEqual(x.map(abs).max() ?? 0, 1.0)
    }
}

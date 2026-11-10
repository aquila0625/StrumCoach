import XCTest
@testable import TunerKit

/// 真实采样：解码、音准（用调音器自己的检测器量）、无缝循环、包体大小。
final class SampleBankTests: XCTestCase {
    private let bank = SampleBank.shared
    private func cents(_ a: Double, _ b: Double) -> Double { 1200 * log2(a / b) }

    func testEveryVoiceHasSamples() {
        for voice in InstrumentTone.Voice.allCases {
            XCTAssertTrue(bank.hasSamples(for: voice), "\(voice) 没有采样")
        }
    }

    func testDecodedLengthMatchesManifestAndStartsWithSound() throws {
        for voice in InstrumentTone.Voice.allCases {
            for (midi, f0) in bank.roots(for: voice) {
                let s = try XCTUnwrap(bank.sample(for: voice, nearestTo: f0), "\(voice) \(midi)")
                XCTAssertEqual(s.midi, midi)
                XCTAssertGreaterThan(s.data.count, 20_000)
                // 起音之前没有被 AAC 编码延迟（约 48 ms）填出一段静音：前 20 ms 里已经有声音抬头
                let peakEarly = s.data[0..<Int(0.02 * s.sampleRate)].map { abs($0) }.max() ?? 0
                let peakAll = s.data.map { abs($0) }.max() ?? 1
                if !voice.isSustained { XCTAssertGreaterThan(peakEarly, peakAll * 0.01, "\(voice) \(midi) 开头静音过长") }
                XCTAssertTrue(s.data.allSatisfy { $0.isFinite })
            }
        }
    }

    /// 每件乐器在整个音域里，任何音高（含 A4=415…466 带来的偏移）发出来都在 ±1 音分内。
    /// 单帧检测本身有零点几音分的抖动，所以和调音器界面一样取多帧的中位数；同时要求单帧也不能偏过 3 音分。
    func testPitchAccuracyForEveryVoice() throws {
        let rate = 48_000.0
        let detector = PitchDetector()
        let frame = PitchDetector.recommendedFrameLength(sampleRate: rate)
        let ranges: [InstrumentTone.Voice: ClosedRange<Int>] = [
            .guitar: 38...82, .bass: 23...55, .ukulele: 55...76,
            .violin: 55...84, .viola: 48...77, .cello: 36...65, .piano: 33...90,
        ]
        for (voice, range) in ranges.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            var worstMedian = 0.0, worstFrame = 0.0, at = ""
            for midi in range {
                for a4 in [415.0, 440.0, 466.0] {
                    let f = Pitch(midi: midi).frequency(a4: a4)
                    let tone = InstrumentTone.render(voice, frequency: f, sampleRate: rate, duration: 1.4, amplitude: 0.5)
                    var errors: [Double] = []
                    // 起音瞬间之后：0.25–0.6 s 每 50 ms 取一帧
                    for t in stride(from: 0.25, through: 0.6, by: 0.05) {
                        let start = Int(t * rate)
                        // 高音的拨弦衰减得快，后面的帧可能已经低于静音门限，跳过即可
                        if let raw = detector.detect(Array(tone[start..<(start + frame)]), sampleRate: rate) {
                            errors.append(cents(raw.frequency, f))
                        }
                    }
                    guard errors.count >= 5 else { XCTFail("\(voice) midi \(midi) a4=\(a4) 只检测到 \(errors.count) 帧"); continue }
                    let median = errors.sorted()[errors.count / 2]
                    worstFrame = max(worstFrame, errors.map { abs($0) }.max()!)
                    if abs(median) > worstMedian { worstMedian = abs(median); at = "midi \(midi) a4=\(a4)" }
                }
            }
            print("音准 \(voice): 多帧中位数最大偏差 \(String(format: "%.2f", worstMedian)) 音分（\(at)），单帧最大 \(String(format: "%.2f", worstFrame)) 音分")
            XCTAssertLessThanOrEqual(worstMedian, 1.0, "\(voice) 音准误差超过 ±1 音分：\(at)")
            XCTAssertLessThanOrEqual(worstFrame, 3.0, "\(voice) 单帧偏差超过 3 音分")
        }
    }

    /// 拉弦采样的循环接缝：连续播很久，接缝附近不能有咔嗒声（相邻采样的跳变不超过正常波形的斜率）。
    func testBowedLoopHasNoClicksAndKeepsSounding() throws {
        let rate = 44_100.0
        for voice in [InstrumentTone.Voice.violin, .viola, .cello] {
            for (midi, f0) in bank.roots(for: voice) where midi % 2 == 0 {
                let sample = try XCTUnwrap(bank.sample(for: voice, nearestTo: f0))
                let loop = try XCTUnwrap(sample.loop, "\(voice) \(midi) 没有循环区间")
                XCTAssertGreaterThan(loop.count, Int(0.2 * rate))
                let out = SamplePlayback.render(sample, frequency: f0, sampleRate: rate, duration: 6)
                // 最大的相邻采样跳变 vs 全程的 99.9% 分位数：接缝处不应突然冒出一个 3 倍大的跳变
                let diffs = zip(out, out.dropFirst()).map { abs($1 - $0) }
                let sorted = diffs.sorted()
                let p999 = sorted[Int(Double(sorted.count) * 0.999)]
                XCTAssertLessThan(sorted.last!, max(p999 * 3, 0.02), "\(voice) \(midi) 循环有咔嗒声")
                // 6 秒后仍在响，且响度稳定（没有衰减到消失，也没有越来越响）
                func rms(_ r: Range<Int>) -> Float { (out[r].map { $0 * $0 }.reduce(0, +) / Float(r.count)).squareRoot() }
                let a = rms(Int(2 * rate)..<Int(3 * rate)), b = rms(Int(5 * rate)..<Int(6 * rate))
                XCTAssertGreaterThan(b, a * 0.6, "\(voice) \(midi)")
                XCTAssertLessThan(b, a * 1.6, "\(voice) \(midi)")
            }
        }
    }

    func testPluckedSamplesDecayNaturallyAndEndWithinFourSeconds() throws {
        let rate = 44_100.0
        for voice in [InstrumentTone.Voice.guitar, .bass, .ukulele, .piano] {
            let f = voice == .bass ? 55.0 : (voice == .ukulele ? 392.0 : 220.0)
            let sample = try XCTUnwrap(bank.sample(for: voice, nearestTo: f))
            XCTAssertNil(sample.loop)
            XCTAssertLessThanOrEqual(sample.duration, 4.05)
            XCTAssertGreaterThanOrEqual(sample.duration, 2.0)
            let out = SamplePlayback.render(sample, frequency: f, sampleRate: rate, duration: 5)
            func rms(_ r: Range<Int>) -> Float { (out[r].map { $0 * $0 }.reduce(0, +) / Float(r.count)).squareRoot() }
            XCTAssertGreaterThan(rms(Int(0.1 * rate)..<Int(0.3 * rate)), rms(Int(1.8 * rate)..<Int(2.0 * rate)) * 1.3, "\(voice)")
            XCTAssertEqual(out.suffix(Int(0.2 * rate)).map { abs($0) }.max() ?? 1, 0, accuracy: 1e-4, "\(voice) 播完应当静音")
        }
    }

    func testPlaybackRetuneKeepsSoundContinuous() throws {
        let rate = 44_100.0
        let sample = try XCTUnwrap(bank.sample(for: .violin, nearestTo: 440))
        var p = SamplePlayback(sample: sample, frequency: 440, outputRate: rate)
        var out = [Float](repeating: 0, count: Int(rate))
        out.withUnsafeMutableBufferPointer { b in
            p.render(into: b.baseAddress!, count: 22_050)
            p.retune(frequency: 442)
            p.render(into: b.baseAddress! + 22_050, count: 22_050)
        }
        let seam = abs(out[22_050] - out[22_049])
        XCTAssertLessThan(seam, 0.1)
    }

    func testBundledSamplesStayUnderSizeBudget() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Samples", withExtension: nil))
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])!
        var total = 0
        for case let url as URL in files { total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        XCTAssertLessThan(Double(total) / 1_000_000, 15, "采样合计应不超过 15 MB，现在 \(Double(total) / 1_000_000) MB")
    }

    func testSynthFallbackStillWorksWithoutSamples() {
        let tone = InstrumentTone.render(.guitar, frequency: 110, sampleRate: 44_100, duration: 1, useSamples: false)
        XCTAssertEqual(tone.count, 44_100)
        XCTAssertGreaterThan(tone.map { abs($0) }.max() ?? 0, 0.4)
        let empty = SampleBank(directory: URL(fileURLWithPath: "/nonexistent"))
        XCTAssertFalse(empty.hasSamples(for: .guitar))
        XCTAssertNil(empty.sample(for: .guitar, nearestTo: 110))
    }
}

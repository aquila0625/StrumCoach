import XCTest
import TunerKit
@testable import ChordKit

final class AudioTests: XCTestCase {
    private func cents(_ detected: Double, _ expected: Double) -> Double { 1200 * log2(detected / expected) }

    func testKarplusStrongPitchAccuracy() throws {
        let detector = PitchDetector()
        let rate = 44100.0
        // 吉他和尤克里里的各根空弦和几个按弦音
        let pitches = ["E2", "A2", "D3", "G3", "B3", "E4", "C4", "A4", "C5", "E5"].compactMap { Pitch($0) }
        for p in pitches {
            let f = p.frequency()
            let samples = KarplusStrong(frequency: f, sampleRate: rate).render(duration: 0.6)
            // 跳过最开头的起音，取稳定的一段
            let window = Array(samples[4410..<(4410 + PitchDetector.recommendedFrameLength(sampleRate: rate, minFrequency: 70))])
            let r = try XCTUnwrap(detector.detect(window, sampleRate: rate), "\(p) 没检出音高")
            XCTAssertEqual(cents(r.frequency, f), 0, accuracy: 6, "\(p) 音准误差过大")
        }
    }

    func testBassFundamental() throws {
        let rate = 44100.0
        let f = Pitch("E1")!.frequency()
        let samples = KarplusStrong(frequency: f, sampleRate: rate).render(duration: 1.0)
        let detector = PitchDetector()
        let n = PitchDetector.recommendedFrameLength(sampleRate: rate)
        let r = try XCTUnwrap(detector.detect(Array(samples[8000..<(8000 + n)]), sampleRate: rate))
        XCTAssertEqual(cents(r.frequency, f), 0, accuracy: 12)
    }

    func testDeterministicAndDecaying() {
        let a = KarplusStrong(frequency: 220).render(duration: 0.5, seed: 3)
        let b = KarplusStrong(frequency: 220).render(duration: 0.5, seed: 3)
        XCTAssertEqual(a, b)
        let early = a[0..<2000].map { $0 * $0 }.reduce(0, +)
        let late = a[(a.count - 2000)...].map { $0 * $0 }.reduce(0, +)
        XCTAssertGreaterThan(early, late * 1.5, "拨弦应该逐渐衰减")
        XCTAssertLessThanOrEqual(a.map { abs($0) }.max()!, 0.51)
        XCTAssertGreaterThan(a.map { abs($0) }.max()!, 0.3)
        XCTAssertTrue(a.allSatisfy { $0.isFinite })
    }

    func testStrumOrderIsLowToHighAndSkipsMutedStrings() {
        let v = ChordLibrary.voicings(for: Chord("C", .major)!, instrument: InstrumentLibrary.guitar)[0]   // x32010
        let freqs = ChordStrummer.frequencies(for: v)
        XCTAssertEqual(freqs.count, 5)
        XCTAssertEqual(freqs, freqs.sorted(), "吉他按弦序拨，频率应从低到高")
        XCTAssertEqual(freqs[0], Pitch("C3")!.frequency(), accuracy: 0.01)

        let samples = ChordStrummer.render(frequencies: freqs, sampleRate: 44100, gap: 0.06, tail: 1.0)
        XCTAssertEqual(samples.count, Int((4 * 0.06 + 1.0) * 44100))
        // 第一根弦在 0 秒发声；最后一根弦在 0.24 秒才开始：开头 0.05 秒里只有一根弦，之后能量明显更大
        func energy(_ r: Range<Int>) -> Float { samples[r].map { $0 * $0 }.reduce(0, +) / Float(r.count) }
        XCTAssertGreaterThan(energy(15000..<17000), energy(0..<2000) * 0.5)
        XCTAssertLessThanOrEqual(samples.map { abs($0) }.max()!, 0.951)
        XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.001)
    }

    func testFrequenciesFollowTheTuningNotJustLowToHigh() {
        // 尤克里里 GCEA（高音 G）：按物理弦序，第一根弦（G4）比第二根（C4）高
        let v = ChordLibrary.voicings(for: Chord("C", .major)!, instrument: InstrumentLibrary.ukulele)[0]  // 0003
        let f = ChordStrummer.frequencies(for: v)
        XCTAssertEqual(f.map { Pitch.nearest(frequency: $0).pitch.fullName }, ["G4", "C4", "E4", "C5"])
    }

    @MainActor func testPlayerCanBeCreatedWithoutPlaying() {
        let player = ChordPlayer()
        XCTAssertFalse(player.isPlaying)
        player.stop()
    }
}

/// 试听用乐器声音扫弦：每根弦的音都在。
final class InstrumentStrumTests: XCTestCase {
    func testStrumWithInstrumentVoices() {
        for voice in [InstrumentTone.Voice.guitar, .ukulele, .bass] {
            let mix = ChordStrummer.render(frequencies: [110, 165, 220], sampleRate: 44_100, voice: voice)
            XCTAssertGreaterThan(mix.count, 44_100)
            XCTAssertLessThanOrEqual(mix.map { abs($0) }.max() ?? 0, 0.95)
            XCTAssertGreaterThan(mix.map { abs($0) }.max() ?? 0, 0.1, "\(voice)")
        }
    }
}

/// 真实乐器采样的试听：吉他/尤克里里按指法图上实际发声的弦扫弦，贝斯弹根音。
final class SampledStrumTests: XCTestCase {
    /// Goertzel：某个频率上的功率。
    private func power(_ x: ArraySlice<Float>, _ f: Double, _ rate: Double) -> Double {
        let w = 2 * Double.pi * f / rate
        let coeff = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s = Double(v) + coeff * s1 - s2; s2 = s1; s1 = s }
        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }

    @MainActor func testStrumGapIsInRealisticRange() {
        XCTAssertGreaterThanOrEqual(ChordStrummer.defaultGap, 0.025)
        XCTAssertLessThanOrEqual(ChordStrummer.defaultGap, 0.040)
        let player = ChordPlayer().voicingStrumGap
        XCTAssertGreaterThanOrEqual(player, 0.025)
        XCTAssertLessThanOrEqual(player, 0.040)
    }

    func testEveryStringOfTheChordIsHeardAtItsOwnPitch() throws {
        let rate = 44_100.0
        for inst in [InstrumentLibrary.guitar, InstrumentLibrary.ukulele] {
            let v = ChordLibrary.voicings(for: Chord("C", .major)!, instrument: inst)[0]
            let freqs = ChordStrummer.frequencies(for: v)
            let voice = InstrumentTone.Voice(family: inst.family)
            let mix = ChordStrummer.render(frequencies: freqs, sampleRate: rate, voice: voice)
            XCTAssertEqual(mix.count, Int((Double(freqs.count - 1) * ChordStrummer.defaultGap + 3.0) * rate))
            // 扫弦结束后（0.3–0.7 s）每根弦的基频上都有明显能量，比偏高/偏低半个半音（约 3%）处强得多
            let window = mix[Int(0.3 * rate)..<Int(0.7 * rate)]
            for f in freqs {
                let on = power(window, f, rate)
                let off = max(power(window, f * 1.0293, rate), power(window, f / 1.0293, rate))
                XCTAssertGreaterThan(on, off * 4, "\(inst.id) \(f) Hz 的那根弦没听到")
            }
            XCTAssertLessThanOrEqual(mix.map { abs($0) }.max()!, 0.951)
            XCTAssertEqual(mix.last ?? 1, 0, accuracy: 1e-4)
        }
    }

    func testSampledChordRingsLongerThanTwoSeconds() {
        let rate = 44_100.0
        let v = ChordLibrary.voicings(for: Chord("E", .minor)!, instrument: InstrumentLibrary.guitar)[0]
        let mix = ChordStrummer.render(frequencies: ChordStrummer.frequencies(for: v), sampleRate: rate, voice: .guitar)
        func rms(_ r: Range<Int>) -> Float { (mix[r].map { $0 * $0 }.reduce(0, +) / Float(r.count)).squareRoot() }
        XCTAssertGreaterThan(rms(Int(1.8 * rate)..<Int(2.0 * rate)), 0.001, "吉他和弦应自然衰减，而不是 1.6 秒就断")
        XCTAssertGreaterThan(rms(Int(0.2 * rate)..<Int(0.4 * rate)), rms(Int(2.6 * rate)..<Int(2.8 * rate)))
    }

    @MainActor func testBassPlaysOnlyTheRoot() {
        let pitches = ["E1", "G#1", "B1", "E2"].compactMap { Pitch($0) }
        XCTAssertEqual(ChordPlayer.frequencies(forPitches: pitches, voice: .bass, a4: 440, bassRootOnly: true).count, 1)
        XCTAssertEqual(ChordPlayer.frequencies(forPitches: pitches, voice: .bass, a4: 440, bassRootOnly: true)[0],
                       Pitch("E1")!.frequency(), accuracy: 1e-9)
        XCTAssertEqual(ChordPlayer.frequencies(forPitches: pitches, voice: .guitar, a4: 440, bassRootOnly: true).count, 4)
        XCTAssertEqual(ChordPlayer.frequencies(forPitches: pitches, voice: .bass, a4: 442, bassRootOnly: true)[0],
                       Pitch("E1")!.frequency(a4: 442), accuracy: 1e-9)
    }
}

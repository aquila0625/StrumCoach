import Foundation
import XCTest
@testable import TunerKit

/// 各乐器的参考音：用调音器自己的音高检测量音准。设环境变量 `TUNERKIT_TONE_DIR=<目录>` 会把每种声音导出成 WAV 试听。
final class InstrumentToneTests: XCTestCase {
    private let sr = 48_000.0

    private func cents(_ a: Double, _ b: Double) -> Double { 1200 * log2(a / b) }

    func testEveryVoiceIsInTune() {
        let cases: [(InstrumentTone.Voice, [String])] = [
            (.guitar, ["E2", "A2", "G3", "E4"]),
            (.bass, ["E1", "A1", "G2"]),
            (.ukulele, ["G4", "C4", "A4"]),
            (.violin, ["G3", "A4", "E5"]),
            (.viola, ["C3", "A4"]),
            (.cello, ["C2", "A3"]),
            (.piano, ["A3", "C5"]),
        ]
        let detector = PitchDetector()
        let frame = PitchDetector.recommendedFrameLength(sampleRate: sr)
        for (voice, notes) in cases {
            for note in notes {
                let f = Pitch(note)!.frequency()
                let tone = InstrumentTone.render(voice, frequency: f, sampleRate: sr, duration: 1.5, amplitude: 0.5)
                // 取起音之后的两段（拨弦衰减得快，第二段取 0.6 s；弓弦取 1.0 s）
                for start in [Int(0.3 * sr), Int((voice.isSustained ? 1.0 : 0.6) * sr)] {
                    let window = Array(tone[start..<min(tone.count, start + frame)])
                    guard let raw = detector.detect(window, sampleRate: sr) else {
                        XCTFail("\(voice) \(note) 没有检测到音高"); continue
                    }
                    XCTAssertEqual(cents(raw.frequency, f), 0, accuracy: 5, "\(voice) \(note) @\(start)")
                }
                XCTAssertEqual(tone.map { abs($0) }.max() ?? 0, 0.5, accuracy: 0.001)
            }
        }
    }

    func testPluckedVoicesDecayAndBowedVoicesSustain() {
        func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot() }
        let f = Pitch("A3")!.frequency()
        for voice in InstrumentTone.Voice.allCases {
            let tone = InstrumentTone.render(voice, frequency: f, sampleRate: sr, duration: 2.5)
            let early = rms(tone[Int(0.2 * sr)..<Int(0.4 * sr)])
            let late = rms(tone[Int(2.1 * sr)..<Int(2.3 * sr)])
            if voice.isSustained {
                XCTAssertGreaterThan(late, early * 0.7, "\(voice) 应该持续")
            } else {
                XCTAssertLessThan(late, early * 0.8, "\(voice) 应该自然衰减")
            }
        }
    }

    /// 导出试听文件（只在设置了环境变量时）。
    func testExportWavesWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["TUNERKIT_TONE_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let notes: [InstrumentTone.Voice: String] = [.guitar: "E2", .bass: "E1", .ukulele: "G4", .violin: "A4",
                                                     .viola: "C3", .cello: "C2", .piano: "A4"]
        for (voice, note) in notes {
            let samples = InstrumentTone.render(voice, frequency: Pitch(note)!.frequency(), sampleRate: 44_100, duration: 3, amplitude: 0.7)
            try wav(samples, sampleRate: 44_100).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(voice.rawValue)-\(note).wav"))
        }
    }

    private func wav(_ x: [Float], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var v = v.littleEndian; d.append(Data(bytes: &v, count: 4)) }
        func u16(_ v: UInt16) { var v = v.littleEndian; d.append(Data(bytes: &v, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + x.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(x.count * 2))
        for s in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        return d
    }
}

import XCTest
@testable import RhythmKit

final class RhythmKitTests: XCTestCase {
    func testTimeSignatureClampsInvalidValues() {
        XCTAssertEqual(TimeSignature(beatsPerBar: 0, beatUnit: 4).beatsPerBar, 1)
        XCTAssertEqual(TimeSignature(beatsPerBar: 99, beatUnit: 4).beatsPerBar, 32)
        XCTAssertEqual(TimeSignature(beatsPerBar: 4, beatUnit: 5).beatUnit, 4)
        XCTAssertEqual(TimeSignature.sixEight.displayName, "6/8")
    }

    func testTimeSignatureDecodingNormalizes() throws {
        let json = #"{"beatsPerBar":100,"beatUnit":3}"#.data(using: .utf8)!
        let ts = try JSONDecoder().decode(TimeSignature.self, from: json)
        XCTAssertEqual(ts, TimeSignature(beatsPerBar: 32, beatUnit: 4))
    }

    func testDefaultAccents() {
        let s = RhythmSettings(timeSignature: .threeFour)
        XCTAssertEqual(s.accents, [.strong, .weak, .weak])
    }

    func testAccentCountAlwaysMatchesBeats() {
        // 多了截断，少了补弱
        XCTAssertEqual(RhythmSettings(timeSignature: .twoFour, accents: [.strong, .medium, .weak]).accents, [.strong, .medium])
        XCTAssertEqual(RhythmSettings(timeSignature: .fourFour, accents: [.strong]).accents, [.strong, .weak, .weak, .weak])

        var s = RhythmSettings(timeSignature: .fourFour, accents: [.strong, .muted, .medium, .weak])
        s.setTimeSignature(.sixEight)
        XCTAssertEqual(s.accents, [.strong, .muted, .medium, .weak, .weak, .weak])
        s.setTimeSignature(.threeFour)
        XCTAssertEqual(s.accents, [.strong, .muted, .medium])
    }

    func testAccentLookupWrapsAndIgnoresOutOfRangeWrites() {
        var s = RhythmSettings(timeSignature: .threeFour)
        XCTAssertEqual(s.accent(atBeat: 3), .strong)
        XCTAssertEqual(s.accent(atBeat: -1), .weak)
        s.setAccent(.muted, atBeat: 9)
        XCTAssertEqual(s.accents, [.strong, .weak, .weak])
        s.setAccent(.muted, atBeat: 1)
        XCTAssertEqual(s.accents[1], .muted)
    }

    func testAccentCycle() {
        XCTAssertEqual(AccentLevel.strong.cycled, .medium)
        XCTAssertEqual(AccentLevel.muted.cycled, .strong)
        XCTAssertFalse(AccentLevel.muted.isAudible)
    }

    func testSubdivisionOffsets() {
        for s in Subdivision.allCases {
            XCTAssertEqual(s.offsets.first, 0, "\(s)")
            XCTAssertEqual(s.offsets, s.offsets.sorted(), "\(s)")
            XCTAssertTrue(s.offsets.allSatisfy { $0 >= 0 && $0 < 1 }, "\(s)")
        }
        XCTAssertEqual(Subdivision.triplet.clicksPerBeat, 3)
        XCTAssertEqual(Subdivision.syncopation.offsets, [0, 0.25, 0.75])
    }

    func testCodableRoundTripAndTolerantDecoding() throws {
        let original = RhythmSettings(
            timeSignature: .sixEight, accents: [.strong, .weak, .weak, .medium, .weak, .muted],
            subdivision: .eighthSixteenth, tone: "woodblock")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(RhythmSettings.self, from: data), original)

        // 字段缺失 → 默认值；重音数量不对 → 修正
        let partial = #"{"timeSignature":{"beatsPerBar":3,"beatUnit":4},"accents":[3]}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RhythmSettings.self, from: partial)
        XCTAssertEqual(s.accents, [.strong, .weak, .weak])
        XCTAssertEqual(s.subdivision, .quarter)
        XCTAssertEqual(s.tone, .default)
    }

    func testToneIDEncodesAsPlainString() throws {
        let data = try JSONEncoder().encode(["t": ToneID("clave")])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"t":"clave"}"#)
    }

    func testTempoClamp() {
        XCTAssertEqual(Tempo.clamp(5), 20)
        XCTAssertEqual(Tempo.clamp(999), 400)
        XCTAssertEqual(Tempo.clamp(120), 120)
    }
}

import XCTest
import TunerKit
@testable import ChordKit

final class PlaybackTests: XCTestCase {
    let guitar = InstrumentLibrary.guitar
    let ukulele = InstrumentLibrary.ukulele
    let bass = InstrumentLibrary.bass

    private func voicing(_ root: String, _ type: ChordType = .major, _ inst: Instrument? = nil, index: Int = 0) -> (Chord, ChordVoicing) {
        let c = Chord(root, type)!
        return (c, ChordLibrary.voicings(for: c, instrument: inst ?? guitar)[index])
    }
    private func pattern(_ id: String) -> ArpeggioPattern { ArpeggioPattern.pattern(id: id)! }

    // MARK: 根音弦替换

    func testRootStringIsReplacedForEachChord() {
        // C 在 5 弦，D 在 4 弦，G 在 6 弦，F 横按在 6 弦，A 在 5 弦，Em 在 6 弦
        let expected: [(String, ChordType, Int)] = [
            ("C", .major, 5), ("D", .major, 4), ("G", .major, 6), ("F", .major, 6),
            ("A", .major, 5), ("E", .minor, 6), ("C", .major7, 5), ("D", .minor, 4),
        ]
        for (root, type, string) in expected {
            let (c, v) = voicing(root, type)
            XCTAssertEqual(ArpeggioPattern.rootStringNumber(voicing: v, chord: c, tuning: guitar.defaultTuning), string, "\(c.name) \(v.shorthand)")
        }
    }

    func testGuitarPatternsSubstituteTheRootString() {
        let p = pattern("g-5321")
        XCTAssertEqual(p.stringNumbers(rootString: 5), [5, 3, 2, 1])      // C
        XCTAssertEqual(p.stringNumbers(rootString: 4), [4, 3, 2, 1])      // D
        XCTAssertEqual(p.stringNumbers(rootString: 6), [6, 3, 2, 1])      // G
        XCTAssertEqual(pattern("g-53231323").stringNumbers(rootString: 4), [4, 3, 2, 3, 1, 3, 2, 3])
        XCTAssertEqual(pattern("g-532313").stringNumbers(rootString: 5), [5, 3, 2, 3, 1, 3])
        XCTAssertEqual(pattern("g-523132").stringNumbers(rootString: 6), [6, 2, 3, 1, 3, 2])
        // 上行 + 下行琶音：从根音弦依次到 1 弦再回来
        XCTAssertEqual(pattern("g-sweep").stringNumbers(rootString: 5), [5, 4, 3, 2, 1, 2, 3, 4])
        XCTAssertEqual(pattern("g-sweep").stringNumbers(rootString: 4), [4, 3, 2, 1, 2, 3])
        XCTAssertEqual(pattern("g-sweep").stringNumbers(rootString: 6), [6, 5, 4, 3, 2, 1, 2, 3, 4, 5])
    }

    func testUkulelePatternsAreLiteral() {
        XCTAssertEqual(pattern("u-4321").stringNumbers(rootString: nil), [4, 3, 2, 1])
        XCTAssertEqual(pattern("u-432123").stringNumbers(rootString: nil), [4, 3, 2, 1, 2, 3])
        XCTAssertEqual(pattern("u-3212").stringNumbers(rootString: nil), [3, 2, 1, 2])
    }

    func testPatternListsPerInstrument() {
        XCTAssertEqual(ArpeggioPattern.patterns(for: .guitar).map(\.digits),
                       ["5 3 2 1", "5 3 2 3 1 3 2 3", "5 3 2 3 1 3", "5 2 3 1 3 2", "5 4 3 2 1 2 3 4"])
        XCTAssertEqual(ArpeggioPattern.patterns(for: .ukulele).map(\.digits), ["4 3 2 1", "4 3 2 1 2 3", "3 2 1 2"])
        XCTAssertEqual(ArpeggioPattern.patterns(for: .bass).count, 1)
        XCTAssertTrue(ArpeggioPattern.patterns(for: .violin).isEmpty)
        XCTAssertEqual(Set(ArpeggioPattern.all.map(\.id)).count, ArpeggioPattern.all.count)
    }

    // MARK: 音序列

    func testGuitarArpeggioNoteSequence() throws {
        let (c, v) = voicing("C")                                                  // x32010
        let pb = PlaybackBuilder.arpeggio(pattern: pattern("g-5321"), voicing: v, chord: c, tuning: guitar.defaultTuning,
                                          voice: .guitar, a4: 440, interval: 0.25)
        XCTAssertEqual(pb.events.map(\.pitch.fullName), ["C3", "G3", "C4", "E4"])
        XCTAssertEqual(pb.events.map(\.string), [1, 3, 4, 5])
        XCTAssertEqual(pb.events.map(\.time), [0, 0.25, 0.5, 0.75])
        XCTAssertEqual(pb.cycle, 1.0)
        XCTAssertTrue(pb.isLooping)

        let pb2 = PlaybackBuilder.arpeggio(pattern: pattern("g-53231323"), voicing: v, chord: c, tuning: guitar.defaultTuning,
                                           voice: .guitar, a4: 440, interval: 0.25)
        XCTAssertEqual(pb2.events.count, 8)
        // 5-3-2-3-1-3-2-3 → A弦 G弦 B弦 G弦 e弦 G弦 B弦 G弦
        XCTAssertEqual(pb2.events.map(\.string), [1, 3, 4, 3, 5, 3, 4, 3])
        XCTAssertEqual(pb2.cycle, 2.0)
    }

    func testDChordUsesTheFourthString() {
        let (c, v) = voicing("D")                                                  // xx0232
        let pb = PlaybackBuilder.arpeggio(pattern: pattern("g-5321"), voicing: v, chord: c, tuning: guitar.defaultTuning,
                                          voice: .guitar, a4: 440, interval: 0.25)
        XCTAssertEqual(pb.events.map(\.pitch.fullName), ["D3", "A3", "D4", "F♯4"])
        XCTAssertEqual(pb.events.map(\.string), [2, 3, 4, 5])
    }

    func testStringsThatAreNotPlayedAreSkippedButKeepTheRhythm() {
        // 只按 5 弦 3 品、空 3 弦：2、1 弦不弹，对应的拍休止，周期不变
        let tuning = guitar.defaultTuning
        let v = ChordVoicing(frets: [-1, 3, 2, 0, -1, -1], fingers: [0, 2, 1, 0, 0, 0], barre: nil, tuning: tuning)
        let steps = pattern("g-5321").steps(voicing: v, chord: Chord("C", .major)!, tuning: tuning)
        XCTAssertEqual(steps, [1, 3, nil, nil])
        let pb = PlaybackBuilder.arpeggio(pattern: pattern("g-5321"), voicing: v, chord: Chord("C", .major)!, tuning: tuning,
                                          voice: .guitar, a4: 440, interval: 0.3)
        XCTAssertEqual(pb.events.count, 2)
        XCTAssertEqual(pb.events.map(\.time), [0, 0.3])
        XCTAssertEqual(pb.cycle ?? 0, 1.2, accuracy: 1e-9)
    }

    func testUkuleleArpeggioSequence() {
        let (c, v) = voicing("C", .major, ukulele)                                 // 0003
        let tuning = ukulele.defaultTuning
        let pb = PlaybackBuilder.arpeggio(pattern: pattern("u-4321"), voicing: v, chord: c, tuning: tuning,
                                          voice: .ukulele, a4: 440, interval: 0.25)
        XCTAssertEqual(pb.events.map(\.pitch.fullName), ["G4", "C4", "E4", "C5"])
        let pb3 = PlaybackBuilder.arpeggio(pattern: pattern("u-3212"), voicing: v, chord: c, tuning: tuning,
                                           voice: .ukulele, a4: 440, interval: 0.25)
        XCTAssertEqual(pb3.events.map(\.pitch.fullName), ["C4", "E4", "C5", "E4"])
        let pb2 = PlaybackBuilder.arpeggio(pattern: pattern("u-432123"), voicing: v, chord: c, tuning: tuning,
                                           voice: .ukulele, a4: 440, interval: 0.25)
        XCTAssertEqual(pb2.events.count, 6)
        XCTAssertEqual(pb2.cycle, 1.5)
    }

    func testBassPlaysRootFifthOctaveFifth() throws {
        let tuning = bass.defaultTuning
        for (root, type, fifth) in [("C", ChordType.major, 7), ("A", .minor, 7), ("B", .diminished, 6), ("C", .augmented, 8), ("E", .dominant7, 7)] {
            let c = Chord(root, type)!
            let positions = BassPositions.make(chord: c, tuning: tuning)
            let pb = try XCTUnwrap(PlaybackBuilder.bassArpeggio(chord: c, tuning: tuning, positions: positions, voice: .bass, a4: 440, interval: 0.3))
            let r = try XCTUnwrap(positions?.anchor).pitch.midi
            XCTAssertEqual(pb.events.map(\.pitch.midi), [r, r + fifth, r + 12, r + fifth], "\(c.name)")
            XCTAssertEqual(pb.events.map(\.pitch.pitchClass.self)[0], c.root)
            XCTAssertEqual(pb.cycle ?? 0, 1.2, accuracy: 1e-9)
        }
        // 根音位置带着弦和品，动画能找到对应的标记
        let c = Chord("C", .major)!
        let positions = BassPositions.make(chord: c, tuning: tuning)!
        let pb = PlaybackBuilder.bassArpeggio(chord: c, tuning: tuning, positions: positions, voice: .bass, a4: 440, interval: 0.3)!
        XCTAssertEqual(pb.events[0].key, 1 * 100 + 3)                       // A 弦 3 品
        for e in pb.events where e.fret != nil {
            XCTAssertTrue(positions.markers.contains { $0.string == e.string && $0.fret == e.fret && $0.pitch == e.pitch })
        }
    }

    func testStrumEventsFollowTheStrumTimes() {
        let (_, v) = voicing("C")                                                  // x32010
        let pb = pbStrum(v)
        XCTAssertEqual(pb.events.count, 5)
        XCTAssertEqual(pb.events.map(\.string), [1, 2, 3, 4, 5])
        XCTAssertFalse(pb.isLooping)
        XCTAssertEqual(pb.events[0].time, 0)
        XCTAssertEqual(pb.events.map(\.time), ChordStrummer.strumTimes(count: 5, firstFrequency: Pitch("C3")!.frequency()))
        XCTAssertEqual(pb.events.map(\.time), pb.events.map(\.time).sorted())
        XCTAssertGreaterThan(pb.events.first!.gain, pb.events.last!.gain)         // 向下扫弦，越到高音弦越轻
    }
    private func pbStrum(_ v: ChordVoicing) -> ChordPlayback { PlaybackBuilder.strum(voicing: v, voice: .guitar, a4: 440) }

    func testNoteInterval() {
        XCTAssertEqual(PlaybackBuilder.noteInterval(bpm: nil), 0.3, accuracy: 1e-9)       // 默认 100 BPM，八分音符
        XCTAssertEqual(PlaybackBuilder.noteInterval(bpm: 120), 0.25, accuracy: 1e-9)
        XCTAssertEqual(PlaybackBuilder.noteInterval(bpm: 1000), 0.1, accuracy: 1e-9)       // 夹在 30…300 BPM
        XCTAssertEqual(PlaybackBuilder.noteInterval(bpm: 5), 0.7, accuracy: 1e-9)
    }

    // MARK: 时钟与渲染

    func testPluckClockAges() {
        let events = [
            PluckEvent(time: 0, string: 1, pitch: Pitch("C3")!, gain: 0.5),
            PluckEvent(time: 0.25, string: 3, pitch: Pitch("G3")!, gain: 0.5),
        ]
        var ages = PluckClock.ages(events: events, cycle: 1.0, time: 0.3)
        XCTAssertEqual(ages[3] ?? -1, 0.05, accuracy: 1e-9)
        XCTAssertEqual(ages[1] ?? -1, 0.3, accuracy: 1e-9)
        // 循环：第二个周期里仍然按取余的位置算；绕回去的“上一次”也算
        ages = PluckClock.ages(events: events, cycle: 1.0, time: 1.1)
        XCTAssertEqual(ages[1] ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(ages[3] ?? -1, 0.85, accuracy: 1e-9)
        // 超过窗口的不再显示
        XCTAssertNil(PluckClock.ages(events: events, cycle: 2.0, time: 1.5)[1])
        // 一次扫弦：还没拨到的弦不显示
        XCTAssertNil(PluckClock.ages(events: events, cycle: nil, time: 0.1)[3])
        XCTAssertEqual(PluckClock.ages(events: events, cycle: nil, time: 0.3)[3] ?? -1, 0.05, accuracy: 1e-9)
        XCTAssertTrue(PluckClock.ages(events: events, cycle: nil, time: -1).isEmpty)
    }

    func testRenderedOnsetsMatchTheEventTimes() {
        // 一次播放：只有一个事件在 0.5 秒，之前必须是静音，之后有声音——事件时间就是缓冲里的位置
        let rate = 44100.0
        let one = ChordPlayback(events: [PluckEvent(time: 0.5, string: 0, pitch: Pitch("A3")!, gain: 0.5)], cycle: nil, voice: .guitar, tail: 1.0)
        let samples = ChordStrummer.render(one, sampleRate: rate)
        XCTAssertEqual(samples.count, Int(1.5 * rate))
        let before = samples[0..<Int(0.49 * rate)].map { abs($0) }.max() ?? 1
        let after = samples[Int(0.5 * rate)..<Int(0.6 * rate)].map { abs($0) }.max() ?? 0
        XCTAssertEqual(before, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(after, 0.05)
    }

    func testLoopedRenderHasExactlyOneCycleAndWrapsTheTail() {
        let rate = 44100.0
        let (c, v) = voicing("C")
        let pb = PlaybackBuilder.arpeggio(pattern: pattern("g-5321"), voicing: v, chord: c, tuning: guitar.defaultTuning,
                                          voice: .guitar, a4: 440, interval: 0.25)
        let samples = ChordStrummer.render(pb, sampleRate: rate)
        XCTAssertEqual(samples.count, Int(rate))                                    // 周期 1 秒，正好一圈
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.951 })
        // 第 4 个音（0.75 秒）的余音绕回开头：开头那一小段里有声音，比只有第 1 个音时更饱满
        XCTAssertGreaterThan(samples[0..<Int(0.2 * rate)].map { abs($0) }.max()!, 0.05)
        // 每个音各自有起拨：0.25 秒、0.5 秒、0.75 秒附近都有新的能量
        func energy(_ a: Double, _ b: Double) -> Float { samples[Int(a * rate)..<Int(b * rate)].map { $0 * $0 }.reduce(0, +) }
        for t in [0.25, 0.5, 0.75] { XCTAssertGreaterThan(energy(t, t + 0.03), energy(t - 0.03, t) * 0.8, "t = \(t)") }
    }

    func testEmptyPlaybackRendersNothing() {
        XCTAssertTrue(ChordStrummer.render(ChordPlayback(events: [], cycle: nil, voice: .guitar), sampleRate: 44100).isEmpty)
    }
}

@MainActor
final class PlayModeModelTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "chordkit.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testChoicesAreRemembered() {
        let d = defaults()
        let m = ChordLibraryModel(defaults: d)
        XCTAssertEqual(m.playMode, .strum)
        XCTAssertEqual(m.arpeggioPattern?.id, "g-5321")
        m.select(playMode: .arpeggio)
        m.select(arpeggio: ArpeggioPattern.pattern(id: "g-sweep")!)
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(m.arpeggioPattern?.id, "u-4321")                  // 每种乐器各记各的
        m.select(arpeggio: ArpeggioPattern.pattern(id: "u-3212")!)
        m.select(arpeggio: ArpeggioPattern.pattern(id: "g-5321")!)       // 吉他的指法不能用在尤克里里上
        XCTAssertEqual(m.arpeggioPattern?.id, "u-3212")

        let again = ChordLibraryModel(defaults: d)          // 下次进来还是它
        XCTAssertEqual(again.playMode, .arpeggio)
        XCTAssertEqual(again.arpeggioPattern?.id, "g-sweep")
        again.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertEqual(again.arpeggioPattern?.id, "u-3212")
    }

    func testPlaybackFollowsTheMode() throws {
        let m = ChordLibraryModel(defaults: defaults())
        let strum = try XCTUnwrap(m.makePlayback())
        XCTAssertFalse(strum.isLooping)
        XCTAssertEqual(strum.events.count, 5)                             // C = x32010
        m.select(playMode: .arpeggio)
        let arp = try XCTUnwrap(m.makePlayback())
        XCTAssertTrue(arp.isLooping)
        XCTAssertEqual(arp.events.count, 4)
        m.setTempo(120)
        XCTAssertEqual(try XCTUnwrap(m.makePlayback()).cycle ?? 0, 1.0, accuracy: 1e-9)
        m.select(root: 2)                                                 // D：根音弦换成 4 弦
        XCTAssertEqual(m.rootStringNumber, 4)
        XCTAssertEqual(try XCTUnwrap(m.makePlayback()).events.map(\.string), [2, 3, 4, 5])
    }

    func testBassAlwaysArpeggiates() throws {
        let m = ChordLibraryModel(defaults: defaults())
        m.select(instrument: InstrumentLibrary.bass)
        XCTAssertFalse(m.supportsStrum)
        XCTAssertEqual(m.effectivePlayMode, .arpeggio)
        let pb = try XCTUnwrap(m.makePlayback())
        XCTAssertEqual(pb.events.count, 4)
        XCTAssertTrue(pb.isLooping)
        XCTAssertNil(m.rootStringNumber)
    }

    func testStopOnChangesAndNoAgesWhenIdle() {
        let m = ChordLibraryModel(defaults: defaults())
        XCTAssertTrue(m.pluckAges().isEmpty)
        m.stopPlayback()
        XCTAssertFalse(m.isPlaying)
    }
}

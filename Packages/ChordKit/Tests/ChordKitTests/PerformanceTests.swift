import XCTest
import TunerKit
@testable import ChordKit

final class LoopTimelineTests: XCTestCase {
    private func events() -> [PluckEvent] { [PluckEvent(time: 0, string: 1, pitch: Pitch("C3")!, gain: 0.5)] }

    func testCyclesAreContiguousWithNoGapOrOverlap() {
        for rate in [44100.0, 48000.0] {
            for bpm in [100.0, 137.0, 73.0, 211.0] {
                var t = LoopTimeline(sampleRate: rate)
                let length = 4 * 60 / bpm
                var previousEnd: Int64 = 0
                for k in 0..<500 {
                    let c = t.append(tag: k, length: length, events: events())
                    XCTAssertEqual(c.startSample, previousEnd, "\(rate) \(bpm) 第 \(k) 个循环和上一个之间有空隙或重叠")
                    XCTAssertGreaterThan(c.lengthSamples, 0)
                    previousEnd = c.endSample
                }
                XCTAssertEqual(t.scheduledEnd, previousEnd)
            }
        }
    }

    func testNoDriftOverThousandsOfCycles() {
        // 4 拍 137 BPM：一个循环 1.7518… 秒，不是整数采样；累计 5000 个循环（约 2.4 小时）后和理想位置的误差不超过 1 个采样
        for rate in [44100.0, 48000.0] {
            var t = LoopTimeline(sampleRate: rate)
            let length = 4 * 60 / 137.0
            for k in 0..<5000 { t.append(tag: k, length: length, events: events()) }
            let ideal = 5000 * length * rate
            XCTAssertEqual(Double(t.scheduledEnd), ideal, accuracy: 1.0, "采样率 \(rate)")
            // 整数采样的循环长度只有两种取值（向上 / 向下取整），不会越积越大
            let lengths = Set(t.cycles.map(\.lengthSamples))
            XCTAssertLessThanOrEqual(lengths.count, 2)
        }
    }

    func testLengthsMayChangeBetweenCycles() {
        // 速度中途变化：衔接仍然无缝
        var t = LoopTimeline(sampleRate: 44100)
        var end: Int64 = 0
        for (k, len) in [2.4, 2.4, 1.2, 1.2, 3.0, 2.0].enumerated() {
            let c = t.append(tag: k, length: len, events: events())
            XCTAssertEqual(c.startSample, end)
            end = c.endSample
        }
        XCTAssertEqual(end, Int64((12.2 * 44100).rounded()))
    }

    func testCycleLookupAndAges() {
        var t = LoopTimeline(sampleRate: 1000)
        let e = [PluckEvent(time: 0, string: 1, pitch: Pitch("C3")!, gain: 0.5), PluckEvent(time: 0.25, string: 3, pitch: Pitch("G3")!, gain: 0.5)]
        t.append(tag: 7, length: 1.0, events: e)
        t.append(tag: 8, length: 1.0, events: e)
        XCTAssertEqual(t.cycle(at: 0)?.tag, 7)
        XCTAssertEqual(t.cycle(at: 999)?.tag, 7)
        XCTAssertEqual(t.cycle(at: 1000)?.tag, 8)
        XCTAssertNil(t.cycle(at: 2000))
        XCTAssertNil(t.cycle(at: -5))
        // 1.1 秒：第二个循环的第一个事件过了 0.1 秒；第一个循环最后一个事件（0.25）已经过了 0.85 秒
        var ages = t.ages(at: 1100)
        XCTAssertEqual(ages[1] ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(ages[3] ?? -1, 0.85, accuracy: 1e-9)
        // 只认可某些循环
        ages = t.ages(at: 1100, accepting: { $0 == 8 })
        XCTAssertEqual(ages[1] ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertNil(ages[3])
        XCTAssertTrue(t.ages(at: 1100, accepting: { _ in false }).isEmpty)
    }

    func testPruneKeepsRecentCycles() {
        var t = LoopTimeline(sampleRate: 1000)
        for k in 0..<10 { t.append(tag: k, length: 1.0, events: events()) }
        t.prune(before: 9000)
        XCTAssertEqual(t.cycles.first?.tag, 6)       // 终点 + 2 秒 < 9 秒的丢掉
        XCTAssertEqual(t.scheduledEnd, 10000)
        t.reset()
        XCTAssertTrue(t.cycles.isEmpty)
        XCTAssertEqual(t.append(tag: 0, length: 1, events: events()).startSample, 0)
    }
}

@MainActor
final class PerformanceModelTests: XCTestCase {
    private func model(_ instrument: String = "guitar", root: Int = 0, type: ChordType = .major) -> ChordLibraryModel {
        let name = "chordkit.perf.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let m = ChordLibraryModel(current: ChordFavorite(instrumentID: instrument, tuningID: "", root: root, typeID: type.id, voicingIndex: 0),
                                  defaults: d)
        m.audioEnabled = false
        return m
    }

    /// 模拟演奏器：把当前这一小节的所有片段（每拍一个）都要出来。第一个片段是小节开头，换和弦只在这里生效。
    private func bar(_ m: ChordLibraryModel) -> [PerformedCycle] {
        var out = [m.nextCycle()!]
        while let plan = m.plan, m.planBeat < plan.lengthBeats - 1e-9 { out.append(m.nextCycle()!) }
        return out
    }

    private func events(_ cycles: [PerformedCycle]) -> [PluckEvent] { cycles.flatMap { $0.playback.events } }

    /// 模拟演奏器：排好一小节，再“听到”它的开头。
    @discardableResult private func play(_ m: ChordLibraryModel) -> Int {
        let b = bar(m)
        m.audibleCycle(b[0].tag)
        return b[0].tag
    }

    // MARK: 排队换和弦

    func testNotPlayingSwitchesImmediately() {
        let m = model()
        m.select(root: 2)
        XCTAssertEqual(m.root, 2)
        XCTAssertNil(m.queued)
        m.select(type: .minor)
        XCTAssertEqual(m.type, .minor)
        XCTAssertEqual(m.chord.name, "Dm")
    }

    func testChordChangeWaitsForTheNextCycle() throws {
        let m = model()
        m.startPlayback()
        XCTAssertTrue(m.isPlaying)
        let first = bar(m)[0]                                         // 演奏器排好第一小节（C）
        m.audibleCycle(first.tag)
        m.select(root: 2)                                             // 循环中间点 D：不立即切换
        XCTAssertEqual(m.chord.name, "C")
        XCTAssertEqual(m.queuedChord?.name, "D")
        XCTAssertEqual(m.queuedRoot, 2)
        XCTAssertNil(m.queuedType)
        XCTAssertTrue(m.hasQueuedChange)

        let second = try XCTUnwrap(bar(m).first)                      // 下一小节开头要内容时才用上排队的 D
        XCTAssertEqual(second.playback.events.map(\.pitch.pitchClass).first, 2)       // D 大三，xx0232：低音是 D
        XCTAssertEqual(m.chord.name, "C", "还没听到，界面仍然是 C")
        XCTAssertTrue(m.hasQueuedChange, "排队状态要保留到真正听到")
        m.audibleCycle(second.tag)                                    // 循环边界：听到新循环
        XCTAssertEqual(m.chord.name, "D")
        XCTAssertNil(m.queued)
        XCTAssertEqual(m.voicingIndex, 0)
    }

    func testLastRequestWins() throws {
        let m = model()
        m.startPlayback()
        play(m)
        m.select(root: 2); m.select(root: 4); m.select(root: 7)
        XCTAssertEqual(m.queuedChord?.name, "G")
        m.select(type: .minor)                                        // 在排队的 G 上再改类型：以最后一次为准
        XCTAssertEqual(m.queuedChord?.name, "Gm")
        let c = try XCTUnwrap(bar(m).first)
        XCTAssertEqual(c.playback.events.first?.pitch.pitchClass, 7)
        m.audibleCycle(c.tag)
        XCTAssertEqual(m.chord.name, "Gm")
        XCTAssertNil(m.queued)
        // 点回当前和弦就是取消排队
        m.select(root: 9)
        XCTAssertNotNil(m.queued)
        m.select(root: 7)
        XCTAssertNil(m.queued)
    }

    func testRequestMadeAfterSchedulingStaysQueued() throws {
        let m = model()
        m.startPlayback()
        play(m)
        m.select(root: 2)
        let d = try XCTUnwrap(bar(m).first)               // D 已排程
        m.select(root: 4)                                 // 之后又点了 E
        m.audibleCycle(d.tag)                             // 听到 D
        XCTAssertEqual(m.chord.name, "D")
        XCTAssertEqual(m.queuedChord?.name, "E", "E 还在排队，下一个循环才切")
        let e = try XCTUnwrap(bar(m).first)
        m.audibleCycle(e.tag)
        XCTAssertEqual(m.chord.name, "E")
        XCTAssertNil(m.queued)
    }

    func testVoicingChangeWhilePlayingTakesEffectNextCycle() throws {
        let m = model()
        m.startPlayback()
        play(m)
        XCTAssertTrue(m.select(voicingIndex: 1))
        XCTAssertEqual(m.voicingIndex, 0)
        XCTAssertEqual(m.queuedVoicingIndex, 1)
        XCTAssertEqual(m.targetVoicingIndex, 1)
        XCTAssertNil(m.queuedChord)
        let expected = ChordLibrary.voicings(for: m.chord, instrument: m.instrument)[1].pitches.compactMap { $0 }.map(\.midi)
        let c = bar(m)
        XCTAssertEqual(Set(events(c).map(\.pitch.midi)), Set(expected))
        m.audibleCycle(c[0].tag)
        XCTAssertEqual(m.voicingIndex, 1)
        XCTAssertNil(m.queued)
        // 已经排队了换和弦，翻把位不生效
        m.select(root: 5)
        XCTAssertFalse(m.select(voicingIndex: 0))
        XCTAssertEqual(m.queuedChord?.name, "F")
    }

    func testStopClearsQueueAndInstrumentSwitchStops() {
        let m = model()
        m.startPlayback(); play(m)
        m.select(root: 2)
        m.stopPlayback()
        XCTAssertFalse(m.isPlaying)
        XCTAssertNil(m.queued)
        XCTAssertEqual(m.chord.name, "C")
        m.startPlayback(); play(m)
        m.select(root: 2)
        m.select(instrument: InstrumentLibrary.ukulele)
        XCTAssertFalse(m.isPlaying)
        XCTAssertNil(m.queued)
    }

    func testFavoriteJumpQueuesOnTheSameInstrument() {
        let m = model()
        m.startPlayback(); play(m)
        let f = ChordFavorite(instrumentID: "guitar", tuningID: "standard", root: 7, typeID: "minor", voicingIndex: 0)
        m.go(to: f)
        XCTAssertEqual(m.queuedChord?.name, "Gm")
        XCTAssertEqual(m.chord.name, "C")
        m.go(to: ChordFavorite(instrumentID: "ukulele", tuningID: "highG", root: 0, typeID: "major", voicingIndex: 0))
        XCTAssertFalse(m.isPlaying)
        XCTAssertEqual(m.instrument.id, "ukulele")
    }

    // MARK: 循环内容

    func testStrumCycleFollowsTheSelectedRhythm() throws {
        let m = model()
        m.setTempo(120)
        XCTAssertEqual(m.strumRhythm.id, "folk1")                              // 吉他默认：民谣 1  D.DU.UDU
        let c = try XCTUnwrap(m.buildCycle(for: m.currentState))
        XCTAssertEqual(c.length, 2.0, accuracy: 1e-9)                          // 4 拍 × 0.5 秒
        XCTAssertFalse(c.playback.isLooping)                                   // 单次播放（带余音），循环由时间线负责
        XCTAssertEqual(c.cells?.count, 8)
        XCTAssertEqual(try XCTUnwrap(c.cells).duration, 0.25, accuracy: 1e-9)
        // C = x32010：下扫 5 根弦，上扫最高的 4 根；D.DU.UDU = 3 下 3 上
        XCTAssertEqual(c.playback.events.count, 3 * 5 + 3 * 4)
        let cell = 0.25
        func hits(_ i: Int) -> [PluckEvent] { c.playback.events.filter { $0.time >= Double(i) * cell && $0.time < Double(i) * cell + 0.1 } }
        XCTAssertEqual(hits(0).map(\.string), [1, 2, 3, 4, 5])                  // 下扫：低音弦 → 高音弦
        XCTAssertTrue(hits(1).isEmpty)                                         // 空拍
        XCTAssertEqual(hits(3).map(\.string), [5, 4, 3, 2])                     // 上扫：最高的 4 根，从最高的往回
        XCTAssertEqual(hits(0).first?.time ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(hits(2).first?.time ?? -1, 0.5, accuracy: 1e-9)
        // 第 1 格最重，其余拍点下扫次之，上扫最轻
        XCTAssertGreaterThan(hits(0)[0].gain, hits(2)[0].gain)
        XCTAssertGreaterThan(hits(6)[0].gain, hits(3)[0].gain)
        XCTAssertLessThan(c.playback.events.map(\.time).max()!, c.length)
    }

    func testDefaultTempoIs70BPM() throws {
        let m = model()
        XCTAssertEqual(ChordLibraryModel.defaultTempo, 70)
        XCTAssertEqual(m.tempo, 70)
        XCTAssertEqual(try XCTUnwrap(m.buildCycle(for: m.currentState)).length, 4 * 60 / 70.0, accuracy: 1e-9)
        m.setTempo(60)
        XCTAssertEqual(try XCTUnwrap(m.buildCycle(for: m.currentState)).length, 4.0, accuracy: 1e-9)
    }

    func testArpeggioCycleIsOnePassOfThePattern() throws {
        let m = model()
        m.select(playMode: .arpeggio)
        m.setTempo(120)
        let c = try XCTUnwrap(m.buildCycle(for: m.currentState))
        XCTAssertEqual(c.length, 1.0, accuracy: 1e-9)                          // 5-3-2-1：4 个八分音符
        XCTAssertEqual(c.playback.events.map(\.pitch.fullName), ["C3", "G3", "C4", "E4"])
        m.select(arpeggio: ArpeggioPattern.pattern(id: "g-53231323")!)
        XCTAssertEqual(try XCTUnwrap(m.buildCycle(for: m.currentState)).length, 2.0, accuracy: 1e-9)
    }

    func testBassCycle() throws {
        let m = model("bass", root: 0)
        let c = try XCTUnwrap(m.buildCycle(for: m.currentState))
        XCTAssertEqual(c.playback.events.map(\.pitch.midi), [36, 43, 48, 43])  // C2 G2 C3 G2
        XCTAssertEqual(c.length, 2 * 60 / 70.0, accuracy: 1e-9)             // 4 步 × 半拍，默认 70 BPM
    }

    func testModeChangeAppliesToTheNextCycle() throws {
        let m = model()
        m.startPlayback()
        XCTAssertEqual(events(bar(m)).count, 27)                               // 民谣 1：3 下 × 5 弦 + 3 上 × 4 弦
        m.select(playMode: .arpeggio)
        XCTAssertTrue(m.isPlaying)                                             // 不打断
        XCTAssertEqual(events(bar(m)).count, 4)                                // 下一小节起换成分解：5-3-2-1
    }

    // MARK: 点弦发声

    func testTappedStringGivesThePitchOfTheCurrentVoicing() {
        let m = model()                                                        // C = x32010
        XCTAssertNil(m.pluckPitch(forString: 0))                               // × 弦不发声
        XCTAssertEqual(m.pluckPitch(forString: 1)?.fullName, "C3")
        XCTAssertEqual(m.pluckPitch(forString: 2)?.fullName, "E3")
        XCTAssertEqual(m.pluckPitch(forString: 3)?.fullName, "G3")
        XCTAssertEqual(m.pluckPitch(forString: 4)?.fullName, "C4")
        XCTAssertEqual(m.pluckPitch(forString: 5)?.fullName, "E4")
        XCTAssertNil(m.pluckPitch(forString: 6))
        // 指定哪一页：第二个把位 x35553 之类，音高跟着那一页走
        let second = ChordLibrary.voicings(for: m.chord, instrument: m.instrument)[1]
        for i in 0..<6 { XCTAssertEqual(m.pluckPitch(forString: i, voicingIndex: 1), second.pitches[i]) }
        let u = model("ukulele")                                               // 0003
        XCTAssertEqual(u.pluckPitch(forString: 0)?.fullName, "G4")
        XCTAssertEqual(u.pluckPitch(forString: 3)?.fullName, "C5")
        u.select(root: 9); u.select(type: .minor)                              // Am = 2000
        XCTAssertEqual(u.pluckPitch(forString: 0)?.fullName, "A4")
        XCTAssertEqual(u.pluckPitch(forString: 1)?.fullName, "C4")
    }

    func testTappedStringShowsAnimationEvenWhenNotPlaying() {
        let m = model()
        XCTAssertFalse(m.isPlaying)
        XCTAssertFalse(m.isAnimating)
        m.pluckString(3)
        XCTAssertTrue(m.isAnimating)
        let ages = m.pluckAges()
        XCTAssertNotNil(ages[3])
        XCTAssertLessThan(ages[3] ?? 99, 0.2)
        m.pluckString(0)                                                       // × 弦：没有声音，但有轻微的动画（键 1000 + 序号）
        XCTAssertNotNil(m.pluckAges()[1000])
        XCTAssertNil(m.pluckAges()[0])
    }

    func testTappingWhilePlayingDoesNotDisturbTheLoop() throws {
        let m = model()
        m.startPlayback()
        play(m)
        m.pluckString(2)
        XCTAssertTrue(m.isPlaying)
        XCTAssertNil(m.queued)
        XCTAssertNotNil(m.pluckAges()[2])
    }

    func testBassMarkerTapGivesItsPitch() throws {
        let m = model("bass", root: 0)
        let positions = try XCTUnwrap(m.bassPositions)
        let anchor = try XCTUnwrap(positions.anchor)
        m.pluckBass(anchor)
        XCTAssertEqual(anchor.pitch.fullName, "C2")
        XCTAssertNotNil(m.pluckAges()[anchor.string * 100 + anchor.fret])
    }
}

@MainActor
final class PerformerSmokeTests: XCTestCase {
    /// 真正启动引擎：循环一个接一个被排上、被“听到”，停止后不再继续。
    func testLoopsRunAndStop() async throws {
        let performer = ChordPerformer()
        performer.configuresAudioSession = false
        var requested = 0
        var heard: [Int] = []
        var heardAt: [Double] = []
        let v = ChordLibrary.voicings(for: Chord("C", .major)!, instrument: InstrumentLibrary.guitar)[0]
        performer.cycleProvider = {
            requested += 1
            let strum = PlaybackBuilder.strumBar(voicing: v, voice: .guitar, a4: 440, bpm: 240, beats: 2)   // 一个循环 0.5 秒
            return PerformedCycle(playback: strum.playback, length: strum.length, tag: requested)
        }
        performer.onAudibleCycle = { heard.append($0); heardAt.append(ProcessInfo.processInfo.systemUptime) }
        guard performer.start() else { throw XCTSkip("这台机器启动不了音频引擎") }
        XCTAssertTrue(performer.isPlaying)
        try await Task.sleep(nanoseconds: 3_200_000_000)
        XCTAssertGreaterThanOrEqual(requested, 3, "2 秒内应该已经排了好几个循环")
        XCTAssertEqual(heard, Array((heard.first ?? 1)...(heard.last ?? 1)), "循环按顺序一个接一个被听到，中间没有跳过")
        XCTAssertLessThanOrEqual(heard.first ?? 1, 3)
        XCTAssertGreaterThanOrEqual(heard.count, 2)
        // 每个循环 0.5 秒：被听到的间隔就是 0.5 秒（只有 20 毫秒的定时器取样误差，没有空隙和抖动）
        // （第一个循环的“被听到”回调要等渲染时钟跑起来，会晚一点；它不影响排程，从第二个开始看间隔）
        for (a, b) in zip(heardAt.dropFirst(), heardAt.dropFirst(2)) { XCTAssertEqual(b - a, 0.5, accuracy: 0.15) }
        // 播放中点弦：叠加发声，不影响循环
        XCTAssertTrue(performer.pluck(Pitch("E4")!, voice: .guitar))
        XCTAssertTrue(performer.isPlaying)
        performer.stop()
        XCTAssertFalse(performer.isPlaying)
        let after = requested
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(requested, after, "停止后不再排循环")
        XCTAssertTrue(performer.pluckAges().isEmpty)
    }

    func testProviderEndingStopsPerformance() async throws {
        let performer = ChordPerformer()
        performer.configuresAudioSession = false
        var calls = 0
        let v = ChordLibrary.voicings(for: Chord("G", .major)!, instrument: InstrumentLibrary.guitar)[0]
        performer.cycleProvider = {
            calls += 1
            guard calls <= 2 else { return nil }
            let c = PlaybackBuilder.strumBar(voicing: v, voice: .guitar, a4: 440, bpm: 240, beats: 2)
            return PerformedCycle(playback: c.playback, length: c.length, tag: calls)
        }
        guard performer.start() else { throw XCTSkip("这台机器启动不了音频引擎") }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertFalse(performer.isPlaying)
        XCTAssertEqual(calls, 3)
    }
}

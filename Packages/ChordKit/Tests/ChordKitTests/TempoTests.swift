import XCTest
import TunerKit
@testable import ChordKit

@MainActor
final class TempoTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "chordkit.tempo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private func model(_ d: UserDefaults? = nil, instrument: String = "guitar") -> ChordLibraryModel {
        let m = ChordLibraryModel(current: ChordFavorite(instrumentID: instrument, tuningID: "", root: 0, typeID: "major", voicingIndex: 0),
                                  defaults: d ?? defaults())
        m.audioEnabled = false
        return m
    }
    /// 一小节里要出来的所有片段。
    private func bar(_ m: ChordLibraryModel) -> [PerformedCycle] {
        var out = [m.nextCycle()!]
        while let plan = m.plan, m.planBeat < plan.lengthBeats - 1e-9 { out.append(m.nextCycle()!) }
        return out
    }

    // MARK: 范围、默认值、持久化

    func testDefaultsAndRange() {
        let m = model()
        XCTAssertEqual(m.tempo, 70)
        XCTAssertFalse(m.followsMetronome)
        XCTAssertEqual(m.effectiveBPM, 70)
        XCTAssertEqual(ChordLibraryModel.tempoRange, 30...200)
        m.setTempo(10);  XCTAssertEqual(m.tempo, 30)
        m.setTempo(-5);  XCTAssertEqual(m.tempo, 30)
        m.setTempo(500); XCTAssertEqual(m.tempo, 200)
        m.setTempo(.infinity); XCTAssertEqual(m.tempo, 200)
        m.setTempo(99.6); XCTAssertEqual(m.tempo, 100)                      // 取整
        m.setTempo(30)
        m.adjustTempo(by: -1); XCTAssertEqual(m.tempo, 30)                  // 到下限不再减
        m.adjustTempo(by: 1);  XCTAssertEqual(m.tempo, 31)
        m.setTempo(200)
        m.adjustTempo(by: 1);  XCTAssertEqual(m.tempo, 200)                 // 到上限不再加
        m.adjustTempo(by: -10); XCTAssertEqual(m.tempo, 190)
    }

    func testPersistence() {
        let d = defaults()
        let m = model(d)
        m.setTempo(95)
        m.setFollowsMetronome(true)
        let again = model(d)
        XCTAssertEqual(again.tempo, 95)
        XCTAssertTrue(again.followsMetronome)
        again.setFollowsMetronome(false)
        XCTAssertFalse(model(d).followsMetronome)
        // 存的值超范围（手动改过 / 以后改了范围）读进来时夹回范围
        d.set(999.0, forKey: ChordLibraryModel.tempoKey)
        XCTAssertEqual(model(d).tempo, 200)
        d.set(3.0, forKey: ChordLibraryModel.tempoKey)
        XCTAssertEqual(model(d).tempo, 30)
        d.set("abc", forKey: ChordLibraryModel.tempoKey)
        XCTAssertEqual(model(d).tempo, 70)
    }

    func testFollowingTheMetronome() {
        let m = model()
        m.bpm = 120
        XCTAssertEqual(m.effectiveBPM, 70, "默认不跟随：用自己的速度，节拍器的速度不影响")
        m.setFollowsMetronome(true)
        XCTAssertEqual(m.effectiveBPM, 120)
        m.bpm = 90
        XCTAssertEqual(m.effectiveBPM, 90)                                  // 节拍器改速度，跟着变
        m.bpm = nil
        XCTAssertEqual(m.effectiveBPM, 70, "App 没传节拍器速度时用自己的")
        m.bpm = 1000
        XCTAssertEqual(m.effectiveBPM, 300)                                 // 节拍器范围更宽，夹在 30–300
        m.bpm = 10
        XCTAssertEqual(m.effectiveBPM, 30)
        m.setFollowsMetronome(false)
        XCTAssertEqual(m.effectiveBPM, 70)
        m.setTempo(150)                                                     // 自己的速度独立保存，不受跟随影响
        XCTAssertEqual(m.tempo, 150)
    }

    // MARK: 播放中改速度：下一拍生效，不打断、不跳拍

    func testTempoChangeTakesEffectOnTheNextBeat() throws {
        let m = model()
        m.setTempo(120)
        m.startPlayback()
        let b0 = try XCTUnwrap(m.nextCycle())                               // 第 1 拍：120 BPM → 0.5 秒
        XCTAssertEqual(b0.length, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.planBeat, 1)
        m.setTempo(60)                                                      // 播放中改成 60
        XCTAssertTrue(m.isPlaying)                                          // 不打断
        let b1 = try XCTUnwrap(m.nextCycle())                               // 第 2 拍：已经是 60 BPM → 1 秒
        XCTAssertEqual(b1.length, 1.0, accuracy: 1e-9)
        XCTAssertEqual(m.planBeat, 2, "只前进一拍，没有跳拍也没有重复")
        // 第 2 拍里的上扫在拍内半拍处（民谣 1 的第 4 格）：已经按新速度算
        let up = try XCTUnwrap(b1.playback.events.first { $0.time > 0.2 })
        XCTAssertEqual(up.time, 0.5, accuracy: 0.05)
        m.setTempo(120)
        let b2 = try XCTUnwrap(m.nextCycle())
        XCTAssertEqual(b2.length, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.planBeat, 3)
    }

    func testChordChangeStillWaitsForTheBarEvenWhenTempoChanges() throws {
        let m = model()
        m.startPlayback()
        let first = try XCTUnwrap(m.nextCycle())
        m.audibleCycle(first.tag)
        m.select(root: 2)                                                   // 排队换 D
        m.setTempo(150)
        // 这一小节剩下的 3 拍仍然是 C（只有速度变了）
        for _ in 0..<3 {
            let c = try XCTUnwrap(m.nextCycle())
            XCTAssertEqual(c.length, 60 / 150.0, accuracy: 1e-9)
            m.audibleCycle(c.tag)
            XCTAssertEqual(m.chord.name, "C")
        }
        let next = try XCTUnwrap(m.nextCycle())                             // 下一小节开头才换 D
        m.audibleCycle(next.tag)
        XCTAssertEqual(m.chord.name, "D")
    }

    func testFollowToggleAlsoAppliesOnTheNextBeat() throws {
        let m = model()
        m.bpm = 150
        m.startPlayback()
        XCTAssertEqual(try XCTUnwrap(m.nextCycle()).length, 60 / 70.0, accuracy: 1e-9)
        m.setFollowsMetronome(true)
        XCTAssertEqual(try XCTUnwrap(m.nextCycle()).length, 60 / 150.0, accuracy: 1e-9)
        m.bpm = 100                                                          // 节拍器改速度也是下一拍生效
        XCTAssertEqual(try XCTUnwrap(m.nextCycle()).length, 0.6, accuracy: 1e-9)
    }

    func testBarLengthIsTheSumOfItsBeats() throws {
        let m = model()
        m.setTempo(100)
        m.startPlayback()
        let cycles = bar(m)
        XCTAssertEqual(cycles.count, 4)                                      // 民谣 1：4 拍，每拍一个片段
        XCTAssertEqual(cycles.map(\.length).reduce(0, +), 4 * 0.6, accuracy: 1e-9)
        // 所有片段的事件合起来 = 整个小节的事件（3 下 × 5 弦 + 3 上 × 4 弦）
        XCTAssertEqual(cycles.flatMap { $0.playback.events }.count, 27)
        XCTAssertEqual(Set(cycles.map(\.tag)).count, 4)
    }

    // MARK: 计划切片

    func testSegmentsKeepEventsOnTheirBeat() throws {
        let m = model()
        let plan = try XCTUnwrap(m.buildPlan(for: m.currentState))            // D.DU.UDU：格序号 0 2 3 5 6 7 → 拍 0 1 1.5 2.5 3 3.5
        XCTAssertEqual(plan.lengthBeats, 4)
        XCTAssertEqual(plan.items.map(\.beat), [0, 1, 1.5, 2.5, 3, 3.5])
        let beat = 0.5
        let s1 = plan.segment(from: 1, beatDuration: beat)
        XCTAssertEqual(s1.beats, 1)
        XCTAssertEqual(s1.events.map(\.time).min() ?? -1, 0, accuracy: 1e-9)             // 第 2 拍正点的下扫从 0 开始
        XCTAssertTrue(s1.events.contains { abs($0.time - 0.25) < 0.05 })       // 1.5 拍 = 片段里 0.25 秒
        // 空拍（第 3 拍里只有 2.5 的上扫；第 3、4 格之间没有别的）：每个片段只含它那一拍的事件
        for start in [0.0, 1, 2, 3] {
            let seg = plan.segment(from: start, beatDuration: beat)
            XCTAssertTrue(seg.events.allSatisfy { $0.time >= 0 && $0.time < beat + 0.05 }, "第 \(start) 拍的事件时间都在这一拍里")
        }
        XCTAssertEqual(plan.wholeBar(beatDuration: beat).count, 27)
    }

    func testFractionalBarEndsWithAHalfBeatSegment() throws {
        let m = model()
        m.select(playMode: .arpeggio)
        let saved = try XCTUnwrap(m.saveCustomArpeggio(text: "5 3 2 1 2"))     // 5 步 = 2.5 拍
        m.select(arpeggio: ArpeggioPattern.pattern(id: "custom-" + saved.id) ?? m.arpeggioPattern!)
        let plan = try XCTUnwrap(m.buildPlan(for: m.currentState))
        XCTAssertEqual(plan.lengthBeats, 2.5)
        XCTAssertEqual(plan.segment(from: 2, beatDuration: 0.5).beats, 0.5)
        m.startPlayback()
        let cycles = bar(m)
        XCTAssertEqual(cycles.count, 3)
        XCTAssertEqual(cycles.map(\.length).reduce(0, +), 2.5 * 60 / 70.0, accuracy: 1e-9)
    }

    func testSilentBeatsProduceEmptySegmentsOfTheRightLength() throws {
        let m = model()
        m.setTempo(120)
        let saved = try XCTUnwrap(m.saveCustomRhythm(text: "D.......", cellsPerBeat: 2))   // 只有第 1 拍有声音
        XCTAssertNotNil(saved)
        m.startPlayback()
        let cycles = bar(m)
        XCTAssertEqual(cycles.count, 4)
        XCTAssertFalse(cycles[0].playback.events.isEmpty)
        for c in cycles.dropFirst() {
            XCTAssertTrue(c.playback.events.isEmpty)
            XCTAssertEqual(c.length, 0.5, accuracy: 1e-9)                      // 休止的拍照样占时间
        }
    }

    func testArpeggioStepsAreHalfBeats() throws {
        let m = model()
        m.select(playMode: .arpeggio)                                           // 5-3-2-1：4 步 = 2 拍
        m.setTempo(120)
        m.startPlayback()
        let cycles = bar(m)
        XCTAssertEqual(cycles.count, 2)
        XCTAssertEqual(cycles.map { $0.playback.events.map(\.time) }, [[0, 0.25], [0, 0.25]])    // 每拍两个音：0 和半拍（0.25 秒）
        XCTAssertEqual(cycles.flatMap { $0.playback.events }.map(\.pitch.fullName), ["C3", "G3", "C4", "E4"])
    }

    func testPlayingCellFollowsTheSegment() {
        let m = model()
        m.startPlayback()
        _ = m.nextCycle()
        XCTAssertNil(m.playingCell(), "没有真实演奏器时没有播放位置")
    }

    func testSegmentsTimelineStaysSeamlessAcrossTempoChanges() {
        // 每拍一个片段、速度中途变化：时间线首尾相接，总长是各拍之和
        var t = LoopTimeline(sampleRate: 44100)
        var expected = 0.0
        var previousEnd: Int64 = 0
        for (k, tempo) in [70.0, 70, 70, 90, 120, 120, 200, 60, 30, 70].enumerated() {
            let beat = 60 / tempo
            expected += beat
            let c = t.append(tag: k, length: beat, events: [])
            XCTAssertEqual(c.startSample, previousEnd)
            previousEnd = c.endSample
        }
        XCTAssertEqual(Double(t.scheduledEnd), expected * 44100, accuracy: 1)
    }
}

@MainActor
final class PerformerSilentSegmentTests: XCTestCase {
    /// 没有事件的片段（休止的一拍）不能让演奏停下来。
    func testSilentSegmentsKeepThePerformanceGoing() async throws {
        let performer = ChordPerformer()
        performer.configuresAudioSession = false
        var calls = 0
        var heard: [Int] = []
        let v = ChordLibrary.voicings(for: Chord("C", .major)!, instrument: InstrumentLibrary.guitar)[0]
        let hit = RhythmStrum.playback(voicing: v, direction: .down, voice: .guitar)
        performer.cycleProvider = {
            calls += 1
            // 单数拍有声音，双数拍休止，每拍 0.25 秒
            let events = calls % 2 == 1 ? hit.events : []
            return PerformedCycle(playback: ChordPlayback(events: events, cycle: nil, voice: .guitar, tail: 1.0, noteSeconds: 1.0),
                                  length: 0.25, tag: calls)
        }
        performer.onAudibleCycle = { heard.append($0) }
        guard performer.start() else { throw XCTSkip("这台机器启动不了音频引擎") }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertTrue(performer.isPlaying)
        XCTAssertGreaterThanOrEqual(calls, 6)
        // 休止的拍也要按顺序被听到，中间没有跳过（机器很忙时第一个片段可能来不及被取样到，所以只要求从第一个听到的起连续）
        XCTAssertEqual(heard, Array((heard.first ?? 1)...(heard.last ?? 1)), "片段按顺序一个接一个被听到")
        XCTAssertLessThanOrEqual(heard.first ?? 1, 3)
        performer.stop()
    }
}

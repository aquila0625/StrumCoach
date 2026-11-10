import XCTest
import AVFoundation
import TunerKit
@testable import ChordKit

final class RhythmStrumTests: XCTestCase {
    let guitar = InstrumentLibrary.guitar
    let ukulele = InstrumentLibrary.ukulele

    private func voicing(_ root: String, _ type: ChordType = .major, _ inst: Instrument? = nil) -> ChordVoicing {
        ChordLibrary.voicings(for: Chord(root, type)!, instrument: inst ?? guitar)[0]
    }
    private func playback(_ v: ChordVoicing, _ d: StrumDirection, velocity: Float = 1, muted: Bool = false) -> ChordPlayback {
        RhythmStrum.playback(voicing: v, direction: d, velocity: velocity, muted: muted, voice: .guitar)
    }

    // MARK: 方向

    func testDownStrumGoesLowToHighOverAllSoundingStrings() {
        let v = voicing("C")                                           // x32010：5 根弦
        let p = playback(v, .down)
        XCTAssertEqual(p.events.map(\.string), [1, 2, 3, 4, 5])
        XCTAssertEqual(p.events.map(\.pitch.midi), p.events.map(\.pitch.midi).sorted())
        XCTAssertEqual(p.events[0].time, 0)
        XCTAssertFalse(p.isLooping)
    }

    func testUpStrumUsesOnlyTheHighestStringsGoingBack() {
        // 5 根弦以上取最高的 4 根，从最高的一根往回
        XCTAssertEqual(playback(voicing("C"), .up).events.map(\.string), [5, 4, 3, 2])
        XCTAssertEqual(playback(voicing("F"), .up).events.map(\.string), [5, 4, 3, 2])       // 133211：6 根弦
        // 4 根弦取 3 根（D = xx0232）
        XCTAssertEqual(playback(voicing("D"), .up).events.map(\.string), [5, 4, 3])
        let p = playback(voicing("C"), .up)
        XCTAssertEqual(p.events.map(\.pitch.midi), p.events.map(\.pitch.midi).sorted(by: >))    // 音高从高到低
    }

    func testStringGapIsBetween8And15Milliseconds() {
        for d in StrumDirection.allCases {
            for root in ["C", "F", "G", "A"] {
                let p = playback(voicing(root), d)
                let gaps = zip(p.events, p.events.dropFirst()).map { $1.time - $0.time }
                XCTAssertFalse(gaps.isEmpty)
                for g in gaps { XCTAssertTrue((0.008...0.015).contains(g), "\(d) \(root) 间隔 \(g)") }
            }
        }
        // 比和弦库试听里的扫弦快
        XCTAssertLessThan(RhythmStrum.downGap, ChordStrummer.defaultGap)
        // 可以自己指定间隔
        let p = RhythmStrum.playback(voicing: voicing("C"), direction: .down, voice: .guitar, gap: 0.02)
        XCTAssertGreaterThan(p.events[1].time, 0.017)
    }

    // MARK: 力度与闷音

    func testVelocityScalesGainAndIsClamped() {
        let v = voicing("C")
        let soft = playback(v, .down, velocity: 0.5).events[0].gain
        let normal = playback(v, .down).events[0].gain
        let accent = playback(v, .down, velocity: 1.25).events[0].gain
        XCTAssertEqual(normal / soft, 2, accuracy: 0.01)
        XCTAssertEqual(accent / normal, 1.25, accuracy: 0.01)
        XCTAssertEqual(playback(v, .down, velocity: 99).events[0].gain / normal, 1.6, accuracy: 0.01)
        XCTAssertGreaterThan(playback(v, .down, velocity: -3).events[0].gain, 0)
        // 上扫比下扫轻一些
        XCTAssertLessThan(playback(v, .up).events[0].gain, normal)
    }

    func testMutedStrumIsShortAndStopsRinging() {
        let v = voicing("C")
        let rate = 44100.0
        let open = ChordStrummer.render(playback(v, .down), sampleRate: rate)
        let muted = ChordStrummer.render(playback(v, .down, muted: true), sampleRate: rate)
        XCTAssertGreaterThan(open.count, Int(1.0 * rate))
        XCTAssertLessThan(muted.count, Int(0.2 * rate))                               // 一瞬间
        XCTAssertGreaterThan(muted.map { abs($0) }.max() ?? 0, 0.02)                  // 但有声音
        XCTAssertEqual(muted.last ?? 1, 0, accuracy: 0.001)                           // 结尾切干净
        // 同样的头 0.1 秒里，闷音的声音不比开放的响
        let n = Int(0.1 * rate)
        let e: ([Float]) -> Float = { $0[0..<n].map { $0 * $0 }.reduce(0, +) }
        XCTAssertLessThanOrEqual(e(muted), e(open) * 1.01)
    }

    func testRenderedStrumIsFiniteAndLimited() {
        for d in StrumDirection.allCases {
            let s = ChordStrummer.render(playback(voicing("G"), d, velocity: 1.6), sampleRate: 44100)
            XCTAssertTrue(s.allSatisfy { $0.isFinite && abs($0) <= 0.951 })
        }
    }

    func testUkuleleStrum() {
        let v = voicing("C", .major, ukulele)                         // 0003：4 根弦
        XCTAssertEqual(RhythmStrum.playback(voicing: v, direction: .down, voice: .ukulele).events.map(\.string), [0, 1, 2, 3])
        XCTAssertEqual(RhythmStrum.playback(voicing: v, direction: .up, voice: .ukulele).events.map(\.string), [3, 2, 1])
    }

    // MARK: 可扫弦的乐器

    func testStrummableInstruments() {
        XCTAssertTrue(InstrumentLibrary.guitar.supportsStrumming)
        XCTAssertTrue(InstrumentLibrary.ukulele.supportsStrumming)
        XCTAssertFalse(InstrumentLibrary.bass.supportsStrumming)
        XCTAssertFalse(InstrumentLibrary.violin.supportsStrumming)
        XCTAssertTrue(InstrumentFamily.guitar.supportsStrumming)
        XCTAssertEqual(ChordLibrary.strummableInstruments.map(\.id), ["guitar", "ukulele"])
        // 每个可扫弦的乐器都有指法（扫弦要靠指法发声）
        for i in ChordLibrary.strummableInstruments { XCTAssertTrue(ChordLibrary.supportsFingering(i), i.id) }
    }

    // MARK: 节点分配

    func testVoiceAllocatorRotatesAndNeverOverlapsWhenItCanAvoidIt() {
        var a = VoiceAllocator(count: 3)
        // 每 0.3 秒一下、每下占 1.2 秒：最多同时 4 个，3 个节点不够时落到最早空闲的那个
        var picks: [Int] = []
        for k in 0..<3 { picks.append(a.reserve(start: Double(k) * 0.3, duration: 1.2)) }
        XCTAssertEqual(Set(picks).count, 3)                           // 前三下各用一个节点
        XCTAssertEqual(a.reserve(start: 1.5, duration: 1.2), picks[0])    // 第一个节点 1.2 秒就空闲了
        a.reset()
        XCTAssertEqual(a.reserve(start: 10, duration: 1), 0)
        XCTAssertEqual(a.reserve(start: 10.2, duration: 1), 1)
        XCTAssertEqual(a.reserve(start: 11.5, duration: 1), 2)           // 三个都空闲了：一直没用过的那个先用
    }

    @MainActor func testCacheKeyDistinguishesStrums() {
        let v = voicing("C")
        let keys = [
            playback(v, .down), playback(v, .up), playback(v, .down, velocity: 1.25), playback(v, .down, muted: true),
            RhythmStrum.playback(voicing: v, direction: .down, voice: .ukulele),
            RhythmStrum.playback(voicing: voicing("G"), direction: .down, voice: .guitar),
        ].map { RhythmStrummer.cacheKey($0, sampleRate: 44100) }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(RhythmStrummer.cacheKey(playback(v, .down), sampleRate: 44100),
                       RhythmStrummer.cacheKey(playback(v, .down), sampleRate: 44100))
    }

    // MARK: 预约（真正启动引擎，只验证不崩溃、返回值和停止）

    @MainActor func testSchedulingReturnsTheRequestedTimeAndStopAllIsSafe() throws {
        let s = RhythmStrummer()
        s.configuresAudioSession = false
        let v = voicing("C")
        // 不能扫弦的乐器不发声
        XCTAssertNil(s.strum(v, instrument: InstrumentLibrary.bass, after: 0.1))
        do { try s.prepare() } catch { throw XCTSkip("这台机器启动不了音频引擎") }      // 提前启动，预约的时间点才不会被启动耗时吃掉
        let t = RhythmStrummer.hostTime(afterSeconds: 0.2)
        guard let first = s.strum(v, instrument: guitar, direction: .down, velocity: 1.25, at: t) else {
            throw XCTSkip("这台机器启动不了音频引擎")
        }
        // 请求的时间点还在未来就原样预约；机器太忙、请求的时间已经过了才会按“立即”处理（晚一点，不会更早）
        XCTAssertGreaterThanOrEqual(first.hostTime, t.hostTime)
        XCTAssertLessThan(AVAudioTime.seconds(forHostTime: first.hostTime - t.hostTime), 1.0)
        XCTAssertEqual(first.events.count, 5)
        XCTAssertEqual(first.direction, .down)
        let second = try XCTUnwrap(s.strum(v, instrument: guitar, direction: .up, muted: true, after: 0.5))
        XCTAssertGreaterThan(second.hostTime, first.hostTime)
        XCTAssertEqual(second.events.count, 4)
        // 过去的时间点按“立即”处理
        let late = try XCTUnwrap(s.strum(v, instrument: ukulele, at: AVAudioTime(hostTime: 1)))
        XCTAssertGreaterThanOrEqual(late.hostTime, RhythmStrummer.nowHostTime - AVAudioTime.hostTime(forSeconds: 0.5))
        s.stopAll()
        // 停止之后还能继续预约
        XCTAssertNotNil(s.strum(v, instrument: guitar, after: 0.05))
        s.stopAll()
    }
}

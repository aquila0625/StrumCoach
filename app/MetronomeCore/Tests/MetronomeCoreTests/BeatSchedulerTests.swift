import XCTest
@testable import MetronomeCore

final class BeatSchedulerTests: XCTestCase {
    private func events(_ scheduler: inout BeatScheduler, from start: Int64 = 0, count: Int, chunk: Int = 512) -> [ClickEvent] {
        var out: [ClickEvent] = []
        var pos = start
        let end = start + Int64(count)
        while pos < end {
            let n = Int(min(Int64(chunk), end - pos))
            scheduler.generate(from: pos, count: n) { out.append($0) }
            pos += Int64(n)
        }
        return out
    }

    private func started(_ config: MetronomeConfig, sampleRate: Double = 48_000) -> BeatScheduler {
        var s = BeatScheduler(sampleRate: sampleRate, config: config)
        s.start(at: 0)
        return s
    }

    // MARK: 每拍的采样位置

    func testQuarterBeatsAt120BPM() {
        var s = started(MetronomeConfig(bpm: 120))
        let e = events(&s, count: 24_000 * 8)
        XCTAssertEqual(e.map(\.sample), (0..<8).map { Int64($0) * 24_000 })
        XCTAssertEqual(e.map(\.beatInBar), [0, 1, 2, 3, 0, 1, 2, 3])
        XCTAssertEqual(e.map(\.beatSerial), Array(0..<8))
        XCTAssertTrue(e.allSatisfy(\.isMainBeat))
    }

    func testFractionalBeatLengthHasNoAccumulatedDrift() {
        // 137 BPM @ 44.1 kHz：一拍 19313.868… 个采样，不是整数。
        let sr = 44_100.0, bpm = 137.0
        var s = started(MetronomeConfig(bpm: bpm), sampleRate: sr)
        let length = sr * 60 / bpm
        let beats = 20_000
        let e = events(&s, count: Int(length * Double(beats)) + 1, chunk: 4_096)
        XCTAssertEqual(e.count, beats + 1)
        for (n, ev) in e.enumerated() {
            XCTAssertEqual(ev.sample, Int64((Double(n) * length).rounded()), "beat \(n)")
        }
    }

    func testStartOffsetAndAccentsAndGains() {
        var config = MetronomeConfig(bpm: 60, timeSignature: .init(4, 4), accents: AccentPattern([.strong, .medium, .weak, .muted]))
        config.sound = .cowbell
        var s = BeatScheduler(sampleRate: 1_000, config: config)
        s.start(at: 500)
        let e = events(&s, from: 500, count: 4_000, chunk: 7)
        XCTAssertEqual(e.map(\.sample), [500, 1_500, 2_500, 3_500])
        XCTAssertEqual(e.map(\.accent), [.strong, .medium, .weak, .muted])
        XCTAssertEqual(e.map(\.level), [.strong, .medium, .weak, .weak])
        XCTAssertEqual(e.map(\.gain), [1.0, 0.78, 0.6, 0])
        XCTAssertTrue(e.allSatisfy { $0.sound == .cowbell })
    }

    // MARK: 各种切分的偏移

    func testSubdivisionOffsets() {
        let expected: [Subdivision: [Int64]] = [
            .quarter: [0],
            .eighth: [0, 12_000],
            .triplet: [0, 8_000, 16_000],
            .sixteenth: [0, 6_000, 12_000, 18_000],
            .dotted: [0, 18_000],
            .eighthSixteenth: [0, 12_000, 18_000],
            .sixteenthEighth: [0, 6_000, 12_000],
            .syncopation: [0, 6_000, 18_000],
        ]
        XCTAssertEqual(Set(expected.keys), Set(Subdivision.allCases))
        for (sub, offsets) in expected {
            var s = started(MetronomeConfig(bpm: 120, subdivision: sub))
            let e = events(&s, count: 48_000)
            let want = offsets + offsets.map { $0 + 24_000 }
            XCTAssertEqual(e.map(\.sample), want, "\(sub)")
            XCTAssertEqual(e.map(\.subIndex), Array(0..<offsets.count) + Array(0..<offsets.count), "\(sub)")
        }
    }

    func testSubdivisionVolumeIs60PercentOfBeat() {
        var config = MetronomeConfig(bpm: 120, accents: AccentPattern([.strong, .weak, .medium, .muted]), subdivision: .eighth)
        XCTAssertEqual(config.subdivisionVolume, 0.6)
        config.subdivisionVolume = 0.6
        var s = started(config)
        let e = events(&s, count: 24_000 * 4)
        let subs = e.filter { !$0.isMainBeat }
        XCTAssertEqual(subs.count, 4)
        for sub in subs {
            XCTAssertEqual(sub.gain, sub.accent.gain * 0.6, accuracy: 1e-6)
            XCTAssertEqual(sub.level, .weak)
        }
        XCTAssertEqual(subs.last?.gain, 0, "静音拍的切分也静音")
    }

    func testTripletRoundsToNearestSample() {
        // 100 BPM @ 44.1k：一拍 26460 采样，三连音间隔 8820。
        var s = started(MetronomeConfig(bpm: 100, subdivision: .triplet), sampleRate: 44_100)
        let e = events(&s, count: 26_460)
        XCTAssertEqual(e.map(\.sample), [0, 8_820, 17_640])
        // 7 BPM 之类除不尽的情况：137 BPM @ 48k
        var s2 = started(MetronomeConfig(bpm: 137, subdivision: .triplet))
        let length = 48_000 * 60 / 137.0
        let e2 = events(&s2, count: Int(length) + 1)
        XCTAssertEqual(e2.map(\.sample), [0, Int64((length / 3).rounded()), Int64((length * 2 / 3).rounded())])
    }

    // MARK: 拍边界上的切换

    func testBPMChangeTakesEffectAtNextBeat() {
        var s = started(MetronomeConfig(bpm: 120, subdivision: .eighth))
        // 渲染到第 0 拍中间（已经过了拍头，还没到八分点）
        var e = events(&s, count: 6_000)
        XCTAssertEqual(e.map(\.sample), [0])
        var faster = s.config
        faster.bpm = 60
        s.update(faster)
        e += events(&s, from: 6_000, count: 200_000 - 6_000)
        // 第 0 拍剩下的八分点仍按 120 BPM；第 1 拍拍头在 24000，从这里开始一拍 48000。
        XCTAssertEqual(Array(e.map(\.sample).prefix(6)), [0, 12_000, 24_000, 48_000, 72_000, 96_000])
        XCTAssertEqual(Array(e.filter(\.isMainBeat).map(\.beatInBar).prefix(4)), [0, 1, 2, 3], "不回到第 1 拍")
    }

    func testChangeExactlyOnBoundaryAndLastUpdateWins() {
        var s = started(MetronomeConfig(bpm: 120))
        var e = events(&s, count: 24_000)  // 刚好渲染完第 0 拍，第 1 拍还没发出
        var c = s.config
        c.bpm = 200; s.update(c)
        c.bpm = 240; s.update(c)  // 同一拍内多次修改，以最后一次为准
        e += events(&s, from: 24_000, count: 36_001)
        XCTAssertEqual(e.map(\.sample), [0, 24_000, 36_000, 48_000, 60_000])
    }

    func testTimeSignatureChangeContinuesBarPosition() {
        var s = started(MetronomeConfig(bpm: 120, timeSignature: .init(4, 4)))
        var e = events(&s, count: 24_000 * 2 - 10)  // 第 0、1 拍
        var c = s.config
        c.setTimeSignature(.init(3, 4), preset: .firstStrong)
        s.update(c)
        e += events(&s, from: 24_000 * 2 - 10, count: 24_000 * 5)
        XCTAssertEqual(e.map(\.beatInBar), [0, 1, 2, 0, 1, 2, 0])
        XCTAssertEqual(e.map(\.beatsPerBar), [4, 4, 3, 3, 3, 3, 3])
        XCTAssertEqual(e.map(\.sample), (0..<7).map { Int64($0) * 24_000 }, "改拍号不影响节拍位置")
    }

    func testAccentAndSoundChangeAppliesNextBeatWithoutRestart() {
        var s = started(MetronomeConfig(bpm: 120, accents: AccentPattern([.strong, .weak, .weak, .weak])))
        var e = events(&s, count: 20_000)  // 第 0 拍已发出，第 1 拍还没到
        var c = s.config
        c.accents[1] = .muted
        c.accents[2] = .strong
        c.sound = .electronic
        c.subdivision = .sixteenth
        s.update(c)
        e += events(&s, from: 20_000, count: 24_000 * 3 - 20_000)
        let mains = e.filter(\.isMainBeat)
        XCTAssertEqual(mains.map(\.accent), [.strong, .muted, .strong])
        XCTAssertEqual(mains.map(\.sound), [.woodblock, .electronic, .electronic])
        // 第 1 拍（已生效）有 4 个点；第 0 拍只有一个点。
        XCTAssertEqual(e.filter { $0.beatSerial == 0 }.count, 1)
        XCTAssertEqual(e.filter { $0.beatSerial == 1 }.count, 4)
    }

    func testChunkSizeDoesNotChangeEvents() {
        let config = MetronomeConfig(bpm: 173, timeSignature: .init(7, 8), subdivision: .syncopation)
        var a = started(config), b = started(config)
        let ea = events(&a, count: 500_000, chunk: 1)
        let eb = events(&b, count: 500_000, chunk: 4_096)
        XCTAssertEqual(ea, eb)
    }

    func testUpdateWhileStoppedAppliesImmediately() {
        var s = BeatScheduler(sampleRate: 48_000, config: .default)
        var c = MetronomeConfig.default
        c.bpm = 60
        s.update(c)
        XCTAssertEqual(s.config.bpm, 60)
        s.start(at: 0)
        let e = events(&s, count: 96_001)
        XCTAssertEqual(e.map(\.sample), [0, 48_000, 96_000])
    }

    func testStopSilencesScheduler() {
        var s = started(MetronomeConfig(bpm: 120))
        _ = events(&s, count: 1_000)
        s.stop()
        XCTAssertTrue(events(&s, from: 1_000, count: 100_000).isEmpty)
    }

    // MARK: 模型

    func testBPMIsClamped() {
        var c = MetronomeConfig(bpm: 5)
        XCTAssertEqual(c.bpm, 20)
        c.bpm = 999
        XCTAssertEqual(c.bpm, 400)
    }

    func testAccentCycleUsesRhythmKit() {
        XCTAssertEqual(AccentLevel.strong.cycled, .medium)
        XCTAssertEqual(AccentLevel.medium.cycled, .weak)
        XCTAssertEqual(AccentLevel.weak.cycled, .muted)
        XCTAssertEqual(AccentLevel.muted.cycled, .strong)
    }

    /// 音频线程用的 offset(_:)/clickCount 必须和 RhythmKit 的 offsets 完全一致。
    func testSubdivisionTablesMatchRhythmKit() {
        for sub in Subdivision.allCases {
            XCTAssertEqual(sub.clickCount, sub.clicksPerBeat, "\(sub)")
            XCTAssertEqual((0..<sub.clickCount).map(sub.offset), sub.offsets, "\(sub)")
        }
    }

    func testConfigRoundTripsThroughRhythmSettings() throws {
        var rhythm = RhythmSettings(timeSignature: .sevenEight, subdivision: .syncopation, tone: SoundKind.cowbell.tone)
        rhythm.setAccent(.muted, atBeat: 3)
        let config = MetronomeConfig(rhythm: rhythm, bpm: 133, subdivisionVolume: 0.4,
                                     training: TrainingPlan(baseBPM: 133, mute: .bars(audible: 2, muted: 1)))
        XCTAssertEqual(config.rhythm, rhythm)
        XCTAssertEqual(config.sound, .cowbell)
        let decoded = try JSONDecoder().decode(MetronomeConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(SoundKind(tone: .default), .woodblock, "RhythmKit 默认的 click 按木鱼处理")
    }

    func testAccentPatternPacking() {
        var p = AccentPattern(repeating: .weak, count: 16)
        p[15] = .muted
        p[0] = .strong
        p[7] = .medium
        XCTAssertEqual(p[15], .muted)
        XCTAssertEqual(p[0], .strong)
        XCTAssertEqual(p[7], .medium)
        XCTAssertEqual(p[8], .weak)
        var wide = AccentPattern(repeating: .weak, count: 32)
        wide[31] = .strong
        wide[30] = .muted
        XCTAssertEqual(wide[31], .strong)
        XCTAssertEqual(wide[30], .muted)
        XCTAssertEqual(wide[29], .weak)
    }

    func testAccentPresets() {
        let ts44 = TimeSignature(4, 4)
        XCTAssertEqual(AccentPreset.firstStrong.pattern(for: ts44).array, [.strong, .weak, .weak, .weak])
        XCTAssertEqual(AccentPreset.allEqual.pattern(for: ts44).array, [.weak, .weak, .weak, .weak])
        XCTAssertEqual(AccentPreset.grouped.pattern(for: ts44).array, [.strong, .weak, .medium, .weak])
        XCTAssertEqual(AccentPreset.grouped.pattern(for: .init(6, 8)).array, [.strong, .weak, .weak, .medium, .weak, .weak])
        XCTAssertEqual(AccentPreset.grouped.pattern(for: .init(7, 8)).array, [.strong, .weak, .medium, .weak, .medium, .weak, .weak])
        XCTAssertEqual(AccentPreset.groups(for: .init(5, 4)), [3, 2])
        XCTAssertEqual(AccentPreset.groups(for: .init(11, 8)), [2, 2, 2, 2, 3])
        for beats in TimeSignature.beatsRange {
            for unit in TimeSignature.allowedBeatUnits {
                let ts = TimeSignature(beats, unit)
                XCTAssertEqual(AccentPreset.groups(for: ts).reduce(0, +), beats, "\(ts)")
                XCTAssertEqual(AccentPreset.grouped.pattern(for: ts).count, beats)
            }
        }
    }

    func testTimeSignatureValidation() {
        XCTAssertEqual(TimeSignature(0, 4).beatsPerBar, 1)
        XCTAssertEqual(TimeSignature(33, 4).beatsPerBar, 32)
        XCTAssertEqual(TimeSignature(4, 3).beatUnit, 4)
        XCTAssertEqual(AccentPreset.firstStrong.accents(for: .fiveFour), RhythmSettings.defaultAccents(for: .fiveFour))
    }

    func testTempoTerms() {
        // 意大利文术语与语言无关；完整名称 = 本地名称 + 意大利文（测试进程里是英文，只显示意大利文）
        XCTAssertEqual(TempoTerm.italian(for: 120), "Allegro")
        XCTAssertEqual(TempoTerm.italian(for: 119), "Moderato")
        XCTAssertEqual(TempoTerm.italian(for: 20), "Grave")
        XCTAssertEqual(TempoTerm.italian(for: 400), "Prestissimo")
        XCTAssertEqual(TempoTerm.italian(for: 90), "Andante")
        XCTAssertTrue(TempoTerm.name(for: 120).hasSuffix("Allegro"))
    }
}

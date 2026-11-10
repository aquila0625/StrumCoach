import ChordKit
import XCTest
@testable import TuneBeatChord

/// 扫弦节奏型：节奏型 → 时间点、评分、起音检测。
final class StrumRhythmTests: XCTestCase {
    func testPresetShapes() {
        let lib = StrumRhythm.presets(for: .guitar)
        XCTAssertGreaterThanOrEqual(lib.count, 7)
        XCTAssertEqual(lib.prefix(2).map(\.id), ["folk1", "folk2"])
        XCTAssertEqual(StrumRhythm.folk1.arrows, "↓· ↓↑ ·↑ ↓↑")
        XCTAssertEqual(StrumRhythm.waltz.cells.count, 6)
        XCTAssertEqual(StrumRhythm.funk.cells.count, 16)
        XCTAssertEqual(StrumRhythm.chunk.cells.filter { $0 == .mute }.count, 2)
        XCTAssertEqual(StrumRhythm.funk.countLabel(1), "e")
        XCTAssertEqual(StrumRhythm.folk1.countLabel(3), "&")
        XCTAssertEqual(StrumRhythm.folk1.countLabel(4), "3")
    }

    /// 尤克里里有自己的推荐列表：默认岛屿扫弦，第二个是 D · D U D U D U。
    @MainActor
    func testInstrumentSpecificPatterns() {
        let uke = StrumRhythm.presets(for: .ukulele)
        XCTAssertEqual(uke.prefix(2).map(\.id), ["island", "ukeBasic"])
        XCTAssertEqual(StrumRhythm.find("island", library: nil)?.id, "island")
    }

    /// 换乐器：当前节奏型不在新乐器的列表里就换成它的默认值。
    @MainActor
    func testSwitchingInstrumentPicksItsDefaultPattern() {
        let suite = "StrumInstrumentTests"
        UserDefaults().removePersistentDomain(forName: suite)
        let trainer = StrumTrainer(bpm: 80, defaults: UserDefaults(suiteName: suite)!)
        trainer.instrumentID = "guitar"
        trainer.pattern = .folk2
        trainer.instrumentID = "ukulele"
        XCTAssertEqual(trainer.pattern.id, "island")
        trainer.pattern = .eighths
        trainer.instrumentID = "guitar"
        XCTAssertEqual(trainer.pattern.id, "eighths", "两边都有的节奏型保留")
        XCTAssertEqual(trainer.patterns.map(\.id), StrumRhythm.presets(for: .guitar).map(\.id))
        UserDefaults().removePersistentDomain(forName: suite)
    }

    /// 和弦库里存的自定义节奏型（按乐器分）排在预设后面；删了就回到第一个预设；改了内容跟着变。
    @MainActor
    func testCustomRhythmsSharedWithChordLibrary() throws {
        let suite = "StrumCustomTests"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        let library = ChordLibraryModel(defaults: d)
        let trainer = StrumTrainer(bpm: 80, library: library, defaults: d)
        trainer.instrumentID = "guitar"
        let saved = try XCTUnwrap(library.saveCustomRhythm(name: "我的", text: "D-DU", cellsPerBeat: 2, family: .guitar, select: false))
        library.saveCustomRhythm(name: "尤克", text: "DUDU", cellsPerBeat: 2, family: .ukulele, select: false)
        let presets = StrumRhythm.presets(for: .guitar)
        XCTAssertEqual(trainer.patterns.count, presets.count + 1, "只列出这类乐器的自定义")
        let custom = try XCTUnwrap(trainer.patterns.last)
        XCTAssertTrue(custom.isCustom)
        XCTAssertEqual(custom.displayTitle, "我的")
        XCTAssertEqual(custom.code, "D.DU")
        trainer.pattern = custom
        // 重新打开训练页：记住选的是自定义的
        XCTAssertEqual(StrumTrainer(bpm: 80, library: library, defaults: d).pattern.id, custom.id)
        XCTAssertEqual(StrumRhythm.find(custom.id, library: library)?.code, "D.DU")
        // 在和弦库里改了内容
        library.saveCustomRhythm(id: saved.id, name: "我的", text: "DUDU", cellsPerBeat: 2, family: .guitar, select: false)
        XCTAssertEqual(trainer.pattern.code, "DUDU")
        // 删掉
        library.deleteCustomRhythm(id: saved.id, family: .guitar)
        XCTAssertEqual(trainer.pattern.id, presets[0].id)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    /// 民谣 1，90 BPM：每格 1/3 秒，空格不出现，两小节 12 下。
    func testTimelinePlacesStrokesOnEighths() {
        let tl = StrumTimeline(pattern: .preset(id: "folk1")!, bpm: 90, start: 10, bars: 2)
        XCTAssertEqual(tl.stepDuration, 1.0 / 3, accuracy: 1e-12)
        let s = tl.strokes
        XCTAssertEqual(s.count, 12)
        XCTAssertEqual(s.map(\.step).prefix(6), [0, 2, 3, 5, 6, 7])
        XCTAssertEqual(s[1].time, 10 + 2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(s[6].bar, 1)
        XCTAssertEqual(s[6].time, 10 + tl.barDuration, accuracy: 1e-12)
        XCTAssertEqual(tl.end, 10 + 2 * tl.barDuration, accuracy: 1e-12)
        XCTAssertEqual(tl.countInBeats.count, 4)
        XCTAssertEqual(tl.countInBeats.first!, 10 - 4 * (60.0 / 90), accuracy: 1e-12)
        XCTAssertEqual(tl.position(at: 10 + 0.4)?.step, 1)
        XCTAssertNil(tl.position(at: 9.9))
        XCTAssertNil(tl.position(at: tl.end))
    }

    func testSixteenthFunkTimeline() {
        let tl = StrumTimeline(pattern: .preset(id: "funk")!, bpm: 100, start: 0, bars: 1)
        XCTAssertEqual(tl.stepDuration, 0.15, accuracy: 1e-12)
        XCTAssertEqual(tl.strokes.count, 16)
    }
}

final class StrumScoringTests: XCTestCase {
    private let tl = StrumTimeline(pattern: .preset(id: "folk1")!, bpm: 90, start: 0, bars: 2)

    func testPerfectTakeScores100() {
        let s = StrumScore.grade(tl, onsets: tl.strokes.map(\.time))
        XCTAssertEqual(s.score, 100)
        XCTAssertEqual(s.good, 12)
        XCTAssertEqual(s.meanOffsetMs!, 0, accuracy: 1e-6)
        XCTAssertEqual(s.spreadMs!, 0, accuracy: 1e-6)
    }

    /// 准、偏、漏、多扫各算一遍：±60 ms 内准，±120 ms 内偏，再远就漏；多出来的扣 0.5。
    func testGoodOffMissedAndExtra() {
        var onsets = tl.strokes.map(\.time)
        onsets[0] += 0.055      // 准
        onsets[1] -= 0.080      // 偏（快）
        onsets[2] += 0.110      // 偏（慢）
        onsets[3] += 0.200      // 太远：第 4 格漏，这个起音也离别的格太远 → 多扫
        onsets.remove(at: 4)    // 第 5 格漏
        onsets.append(tl.strokes[6].time + 0.17)  // 两格中间多扫一下
        let s = StrumScore.grade(tl, onsets: onsets)
        XCTAssertEqual(s.hits.map(\.grade).prefix(5), [.good, .off, .off, .missed, .missed])
        XCTAssertEqual(s.good, 8)
        XCTAssertEqual(s.off, 2)
        XCTAssertEqual(s.missed, 2)
        XCTAssertEqual(s.extras.count, 2)
        // (8 + 1 − 1) / 12 = 66.7
        XCTAssertEqual(s.score, 67)
        XCTAssertEqual(s.hits[1].offset!, -0.080, accuracy: 1e-9)
    }

    func testOnsetIsUsedOnlyOnce() {
        // 一个起音正好在两格中间（八分 90 BPM 两格相距 333 ms，太远）；换成十六分 Funk，两格相距 150 ms
        let funk = StrumTimeline(pattern: .preset(id: "funk")!, bpm: 100, start: 0, bars: 1)
        let s = StrumScore.grade(funk, onsets: [0.075])
        XCTAssertEqual(s.hits.filter { $0.grade != .missed }.count, 1, "一个起音只配一格")
    }

    func testOnsetsOutsideWindowAreIgnoredAndScoreClamps() {
        let s = StrumScore.grade(tl, onsets: [-2, -0.5, tl.end + 1])
        XCTAssertEqual(s.extras.count, 0, "倒数时和结束后的声音不算")
        XCTAssertEqual(s.score, 0)
        let noisy = StrumScore.grade(tl, onsets: stride(from: 0.05, to: tl.end, by: 0.09).map { $0 })
        XCTAssertGreaterThanOrEqual(noisy.score, 0)
        XCTAssertLessThanOrEqual(noisy.score, 100)
    }

    func testMeanOffsetSpreadAndAdvice() {
        // 全部慢 50 ms → 平均 +50，稳定度 0，建议说慢了
        let late = StrumScore.grade(tl, onsets: tl.strokes.map { $0.time + 0.05 })
        XCTAssertEqual(late.meanOffsetMs!, 50, accuracy: 1e-6)
        XCTAssertEqual(late.spreadMs!, 0, accuracy: 1e-6)
        XCTAssertTrue(late.advice.contains("50"), late.advice)
        // 节奏型里该上扫的格慢 40 ms，下扫的准 → 说上扫慢
        let upLate = StrumScore.grade(tl, onsets: tl.strokes.map { $0.time + ($0.stroke == .up ? 0.04 : 0) })
        XCTAssertEqual(upLate.meanOffsetMs(for: .up)!.ms, 40, accuracy: 1e-6)
        XCTAssertTrue(upLate.advice.contains("40"), upLate.advice)
        // 满分给提速建议
        XCTAssertFalse(StrumScore.grade(tl, onsets: tl.strokes.map(\.time)).advice.isEmpty)
    }
}

final class OnsetDetectorTests: XCTestCase {
    private let sr = 48_000.0

    /// 合成一段扫弦录音：节奏型里每个该扫的格放一下（下扫从低音弦往高音弦，上扫反过来只扫高音的 4 根，
    /// 闷音是 30 ms 的噪声“嚓”），加上持续的底噪和几下很小的杂音。
    private func synthesize(_ tl: StrumTimeline, noise: Float = 0.002, clicks: [Double] = [], loud: Float = 0.6,
                            bassLevel: Float = 0.35) -> [Float] {
        let total = Int((tl.end + 1) * sr)
        var audio = [Float](repeating: 0, count: total)
        var seed: UInt64 = 42
        func rand() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: seed >> 1) % 20_000) / 10_000 - 1
        }
        let c = [130.81, 164.81, 196.0, 261.63, 329.63]  // C 和弦（开放把位）
        for s in tl.strokes {
            let start = Int(s.time * sr)
            let clip: [Float]
            switch s.stroke {
            case .down: clip = ChordStrummer.render(frequencies: c, sampleRate: sr, gap: 0.010, tail: 0.6, amplitude: loud)
            case .up: clip = ChordStrummer.render(frequencies: Array(c.reversed().prefix(4)), sampleRate: sr, gap: 0.010, tail: 0.5, amplitude: loud * 0.7)
            case .downTreble: clip = ChordStrummer.render(frequencies: Array(c.suffix(4)), sampleRate: sr, gap: 0.010, tail: 0.5, amplitude: loud * 0.75)
            // 根音单拨：一根弦，比扫弦轻得多
            case .bass: clip = ChordStrummer.render(frequencies: [c[0]], sampleRate: sr, gap: 0, tail: 0.6, amplitude: loud * bassLevel)
            case .mute: clip = (0..<Int(0.03 * sr)).map { i in rand() * loud * 0.6 * exp(-Float(i) / Float(0.008 * sr)) }
            case .rest: clip = []
            }
            for (i, v) in clip.enumerated() where start + i < total { audio[start + i] += v }
        }
        for t in clicks {
            let start = Int(t * sr)
            for i in 0..<Int(0.004 * sr) where start + i < total { audio[start + i] += rand() * 0.004 }
        }
        for i in 0..<total { audio[i] += rand() * noise }
        return audio
    }

    private func check(_ id: String, bpm: Double, file: StaticString = #filePath, line: UInt = #line) {
        let tl = StrumTimeline(pattern: .preset(id: id)!, bpm: bpm, start: 0.5, bars: 2)
        // 节拍外的小杂音：每两格中间一下
        let noise = tl.strokes.dropLast().map { $0.time + tl.stepDuration / 2 }
        let audio = synthesize(tl, clicks: noise)
        let onsets = OnsetDetector(sampleRate: sr).detect(audio).map { Double($0) / sr }
        let score = StrumScore.grade(tl, onsets: onsets)
        XCTAssertEqual(onsets.count, tl.strokes.count, "\(id)：起音数", file: file, line: line)
        XCTAssertEqual(score.good, tl.strokes.count, "\(id)：每下都在 ±60 ms 内", file: file, line: line)
        XCTAssertEqual(score.extras.count, 0, "\(id)：杂音和余音不算起音", file: file, line: line)
        XCTAssertLessThan(abs(score.meanOffsetMs ?? 99), 8, "\(id)：平均误差", file: file, line: line)
    }

    func testDetectsFolkPattern() { check("folk1", bpm: 90) }
    func testDetectsHalfStrums() { check("country", bpm: 100) }

    /// 根音单拨很轻：在该拨根音的格子附近放低门槛，都能算命中；节拍外的杂音照样不算
    func testQuietRootNotesCountNearTheirCells() {
        let tl = StrumTimeline(pattern: .preset(id: "rootStrum")!, bpm: 90, start: 0.5, bars: 2)
        let noise = tl.strokes.dropLast().map { $0.time + tl.stepDuration / 2 }
        let audio = synthesize(tl, clicks: noise, bassLevel: 0.08)
        let windows = StrumTrainer.bassWindows(tl, delay: 0).map { Int($0.lowerBound * sr)...Int($0.upperBound * sr) }
        let onsets = OnsetDetector(sampleRate: sr).detect(audio, sensitive: windows).map { Double($0) / sr }
        let score = StrumScore.grade(tl, onsets: onsets)
        XCTAssertEqual(score.missed, 0, "每个根音都收到")
        XCTAssertEqual(score.extras.count, 0, "杂音不算")
        XCTAssertEqual(score.hits.filter { $0.stroke == .bass }.count, 4, "B.D.B.D. 两小节 4 个根音")
    }
    func testDetectsFastEighths() { check("eighths", bpm: 140) }
    func testDetectsMutedStrokes() { check("chunk", bpm: 100) }
    func testDetectsSixteenthFunk() { check("funk", bpm: 90) }

    func testSilenceAndSteadyNoiseGiveNoOnsets() {
        let detector = OnsetDetector(sampleRate: sr)
        XCTAssertEqual(detector.detect([Float](repeating: 0, count: Int(sr * 3))), [])
        var seed: UInt64 = 7
        let noise: [Float] = (0..<Int(sr * 3)).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Float(Int64(bitPattern: seed >> 1) % 20_000) / 10_000 - 1) * 0.003
        }
        XCTAssertEqual(detector.detect(noise), [], "持续的底噪不算扫弦")
    }

    /// 弹得早或晚，检测出来的时间跟着走（误差在 5 ms 内）。
    func testOnsetTimesAreAccurate() {
        let tl = StrumTimeline(pattern: .preset(id: "quarters")!, bpm: 80, start: 0.5, bars: 2)
        let shift = 0.037
        let shifted = StrumTimeline(pattern: tl.pattern, bpm: 80, start: 0.5 + shift, bars: 2)
        let onsets = OnsetDetector(sampleRate: sr).detect(synthesize(shifted)).map { Double($0) / sr }
        let score = StrumScore.grade(tl, onsets: onsets)
        XCTAssertEqual(score.meanOffsetMs!, shift * 1000, accuracy: 5)
    }
}

/// 录音换算到主机时钟：起音时间按它所在缓冲自己的时间戳换算；缓冲之间有空隙也不累积误差。
final class StrumCaptureTests: XCTestCase {
    func testOnsetsMapToHostClockAcrossBuffers() {
        let sr = 48_000.0
        let tl = StrumTimeline(pattern: .preset(id: "quarters")!, bpm: 100, start: 0.4, bars: 2)
        // 一段合成录音：每拍一下扫弦
        var audio = [Float](repeating: 0, count: Int((tl.end + 0.5) * sr))
        let c = [130.81, 164.81, 196.0, 261.63, 329.63]
        for s in tl.strokes {
            let clip = ChordStrummer.render(frequencies: c, sampleRate: sr, gap: 0.010, tail: 0.5, amplitude: 0.6)
            let start = Int(s.time * sr)
            for (i, v) in clip.enumerated() where start + i < audio.count { audio[start + i] += v }
        }
        // 切成 1024 采样一块，每块带主机时间；中途有一块的时间戳比连续的晚 3 ms（模拟丢帧后重新对齐）
        let host0 = 5_000.0
        var chunks: [(time: Double, samples: [Float])] = []
        var i = 0
        var skew = 0.0
        while i < audio.count {
            if i >= Int(1.2 * sr) { skew = 0.003 }
            chunks.append((host0 + Double(i) / sr + skew, Array(audio[i..<min(audio.count, i + 1024)])))
            i += 1024
        }
        let times = InputRecorder.Capture(chunks: chunks, sampleRate: sr).onsetTimes()
        XCTAssertEqual(times.count, tl.strokes.count)
        for (t, s) in zip(times, tl.strokes) {
            let expected = host0 + s.time + (s.time >= 1.2 ? 0.003 : 0)
            XCTAssertEqual(t, expected, accuracy: 0.006)
        }
    }

    func testHistoryKeepsLastAndBest() {
        let suite = "StrumHistoryTests"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        var h = StrumHistory(defaults: d)
        h.add(.init(date: Date(), patternID: "folk1", chord: "C", bpm: 80, score: 70))
        h.add(.init(date: Date(), patternID: "folk1", chord: "G", bpm: 85, score: 88))
        h.add(.init(date: Date(), patternID: "folk2", chord: "C", bpm: 80, score: 60))
        let reloaded = StrumHistory(defaults: d)
        XCTAssertEqual(reloaded.last?.score, 60)
        XCTAssertEqual(reloaded.best(for: "folk1"), 88)
        XCTAssertNil(reloaded.best(for: "funk"))
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

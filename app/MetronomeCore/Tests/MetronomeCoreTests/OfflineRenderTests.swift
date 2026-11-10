import XCTest
@testable import MetronomeCore

/// 离线渲染真实的音频输出，从波形里找每一下的起音点来量节拍间隔。
final class OfflineRenderTests: XCTestCase {
    private struct Measurement {
        var onsets: [Int64] = []
        var mainBeatEvents: [ClickEvent] = []
        var peak: Float = 0
    }

    /// 渲染 `seconds` 秒，检测起音：超过阈值、且距离上一个起音至少 `minGap` 秒的第一个采样。
    private func render(_ config: MetronomeConfig, sampleRate: Double, seconds: Double, chunk: Int = 512,
                        threshold: Float = 1e-4, minGap: Double = 0.25) -> Measurement {
        let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sampleRate), config: config)
        renderer.start(config: config)
        let total = Int64(seconds * sampleRate)
        let gap = Int64(minGap * sampleRate)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var m = Measurement()
        var lastOnset = Int64.min / 2
        var pos: Int64 = 0
        while pos < total {
            let n = Int(min(Int64(chunk), total - pos))
            renderer.render(into: buffer, frames: n) { event in
                if event.isMainBeat { m.mainBeatEvents.append(event) }
            }
            for i in 0..<n {
                let v = abs(buffer[i])
                m.peak = max(m.peak, v)
                let s = pos + Int64(i)
                if v > threshold && s - lastOnset >= gap {
                    m.onsets.append(s)
                    lastOnset = s
                }
            }
            pos += Int64(n)
        }
        return m
    }

    /// 10 分钟、120 BPM：每拍间隔误差不超过 1 毫秒，累计漂移为 0。
    func testTenMinutesAt120BPM() {
        let sr = 48_000.0
        let config = MetronomeConfig(bpm: 120, timeSignature: .init(4, 4))  // 默认重音：强 弱 次强 弱
        let m = render(config, sampleRate: sr, seconds: 600)
        let beatSamples: Int64 = 24_000

        // 10 分钟 × 120 BPM = 1200 拍
        XCTAssertEqual(m.onsets.count, 1_200)
        XCTAssertEqual(m.mainBeatEvents.count, 1_200)
        XCTAssertGreaterThan(m.peak, 0.3)
        XCTAssertLessThanOrEqual(m.peak, 1)

        // 调度出来的拍子位置精确等于 n × 24000
        for (n, e) in m.mainBeatEvents.enumerated() {
            XCTAssertEqual(e.sample, Int64(n) * beatSamples)
        }

        // 波形里量到的每拍间隔，误差不超过 1 ms
        var maxErrorMs = 0.0
        for i in 1..<m.onsets.count {
            let interval = Double(m.onsets[i] - m.onsets[i - 1])
            maxErrorMs = max(maxErrorMs, abs(interval - Double(beatSamples)) / sr * 1_000)
        }
        XCTAssertLessThanOrEqual(maxErrorMs, 1.0)

        // 累计漂移：同一种音（每小节第 1 拍都是强拍音）相对第一拍的位置必须正好是整数个小节
        let downbeats = stride(from: 0, to: m.onsets.count, by: 4).map { m.onsets[$0] }
        let drift = downbeats.enumerated().map { k, s in s - downbeats[0] - Int64(k) * 4 * beatSamples }
        XCTAssertEqual(drift.map { abs($0) }.max(), 0, "累计漂移必须为 0")

        print(String(format: "10 分钟 120 BPM：%d 拍，最大间隔误差 %.4f ms，累计漂移 0 采样", m.onsets.count, maxErrorMs))
    }

    /// 除不尽的情况：137 BPM @ 44.1 kHz，渲染 10 分钟，量化误差不累积。
    func testTenMinutesAtFractionalTempo() {
        let sr = 44_100.0, bpm = 137.0
        let m = render(MetronomeConfig(bpm: bpm, accents: AccentPattern(repeating: .strong, count: 4), sound: .electronic),
                       sampleRate: sr, seconds: 600, chunk: 1_024, threshold: 0.01, minGap: 0.2)
        let length = sr * 60 / bpm
        XCTAssertEqual(m.onsets.count, Int((600 / (60 / bpm)).rounded(.up)))
        let offset0 = Double(m.onsets[0])
        var maxDeviation = 0.0
        for (n, onset) in m.onsets.enumerated() {
            maxDeviation = max(maxDeviation, abs(Double(onset) - offset0 - Double(n) * length))
        }
        // 每拍都只有不超过 1 个采样的取整误差，不随时间增长
        XCTAssertLessThanOrEqual(maxDeviation, 1.0)
    }

    /// 播放中改速度：渲染出来的波形在拍边界无缝切换，不丢拍也不多拍。
    func testTempoChangeInRenderedAudio() {
        let sr = 48_000.0
        let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sr), config: MetronomeConfig(bpm: 120))
        renderer.start(config: MetronomeConfig(bpm: 120))
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { buffer.deallocate() }
        var beats: [Int64] = []
        var changed = false
        while renderer.cursor < 48_000 * 4 {
            if !changed && renderer.cursor >= 30_000 {
                var c = renderer.scheduler.config
                c.bpm = 90
                renderer.update(c)
                changed = true
            }
            renderer.render(into: buffer, frames: 256) { if $0.isMainBeat { beats.append($0.sample) } }
        }
        // 0、24000 按 120；第 2 拍（48000）开始每拍 32000
        XCTAssertEqual(beats, [0, 24_000, 48_000, 80_000, 112_000, 144_000, 176_000])
    }

    /// 渐进提速 10 分钟：80 → 120、每 4 小节 +2。从波形量出的每一拍都要落在理论位置 ±1 ms 内，
    /// 而且到第 10 分钟也不累积误差（理论位置按每拍长度逐拍累加的连续时间算）。
    func testTenMinutesOfTempoRamp() {
        let sr = 48_000.0
        let plan = TrainingPlan(baseBPM: 80, ramp: RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4))
        let m = render(MetronomeConfig(training: plan), sampleRate: sr, seconds: 600, minGap: 0.3)
        XCTAssertEqual(m.onsets.count, m.mainBeatEvents.count)
        var ideal = 0.0
        var maxErrorMs = 0.0
        for (n, onset) in m.onsets.enumerated() {
            maxErrorMs = max(maxErrorMs, abs(Double(onset) - ideal) / sr * 1_000)
            ideal += sr * 60 / Double(plan.bpm(atBar: n / 4))
        }
        XCTAssertLessThanOrEqual(maxErrorMs, 1.0)
        // 最后一拍和理论位置的差不超过取整的半个采样：没有累计漂移
        let last = m.onsets.count - 1
        var t = 0.0
        for n in 0..<last { t += sr * 60 / Double(plan.bpm(atBar: n / 4)) }
        XCTAssertLessThanOrEqual(abs(Double(m.onsets[last]) - t), 0.5)
        XCTAssertEqual(m.mainBeatEvents.last?.bpm, 120)
        print(String(format: "渐进提速 10 分钟：%d 拍，最大误差 %.4f ms", m.onsets.count, maxErrorMs))
    }

    /// 静音小节 10 分钟、120 BPM：有声 3 小节 + 静音 1 小节。静音小节里波形必须完全没有起音，
    /// 恢复后的第一拍仍然正好落在 n × 24000。
    func testTenMinutesOfMutedBars() {
        let sr = 48_000.0
        let plan = TrainingPlan(baseBPM: 120, mute: .bars(audible: 3, muted: 1))
        let m = render(MetronomeConfig(bpm: 120, subdivision: .eighth, training: plan), sampleRate: sr, seconds: 600, minGap: 0.4)
        let expected = (0..<1_200).filter { ($0 / 4) % 4 != 3 }.map { Int64($0) * 24_000 }
        XCTAssertEqual(m.onsets, expected, "只在有声小节出现起音，位置精确到采样")
        XCTAssertEqual(m.mainBeatEvents.count, 1_200, "静音小节的拍照样调度（界面高亮要用）")
    }

    /// 两种训练同时开：提速 + 随机静音（保留每小节第一拍）。
    func testRampAndRandomMuteTogether() {
        let sr = 44_100.0
        let mute = MuteSettings.randomBeats(probability: 0.3, seed: 2026, keepsDownbeat: true)
        let plan = TrainingPlan(baseBPM: 100, ramp: RampSettings(startBPM: 100, targetBPM: 160, step: 3, barsPerStep: 2), mute: mute)
        let m = render(MetronomeConfig(timeSignature: .threeFour, training: plan), sampleRate: sr, seconds: 300, minGap: 0.3)
        var ideal: [Double] = []
        var t = 0.0
        for e in m.mainBeatEvents {
            ideal.append(t)
            t += sr * 60 / e.bpm
            XCTAssertEqual(e.bpm, Double(plan.bpm(atBar: e.bar)))
        }
        let audible = zip(m.mainBeatEvents, ideal).filter { !$0.0.isTrainingMuted }.map(\.1)
        XCTAssertEqual(m.onsets.count, audible.count)
        for (onset, t) in zip(m.onsets, audible) {
            XCTAssertLessThanOrEqual(abs(Double(onset) - t), 0.5)
        }
    }

    func testAllVoicesAreSynthesized() {
        let bank = VoiceBank(sampleRate: 48_000)
        for sound in SoundKind.allCases {
            for level in VoiceLevel.allCases {
                let b = bank.buffer(sound, level)
                XCTAssertGreaterThan(b.count, 1_000)
                let peak = b.map { abs($0) }.max()!
                XCTAssertEqual(peak, 0.95, accuracy: 0.001)
                XCTAssertLessThan(abs(b[b.count - 1]), 0.05, "\(sound) \(level) 结尾要衰减干净")
            }
        }
    }

    /// 人声报数：第 n 拍放第 n 个数字的声音；动态槽位按本机采样率重采样。
    func testVoiceCountUsesTheNumberOfEachBeat() {
        let sr = 48_000.0
        let bank = VoiceBank(sampleRate: sr)
        // 每个数字用不同的直流电平标记：第 k 拍 = 0.1 × (k + 1)，长 0.1 秒（源采样率 24k → 重采样后 4800 个）
        for k in 0..<4 {
            bank.setDynamic(VoiceBank.countSlot(k), samples: Array(repeating: Float(k + 1) * 0.1, count: 2_400), sourceRate: 24_000)
            XCTAssertEqual(bank.dynamicBuffer(VoiceBank.countSlot(k))?.count, 4_800)
        }
        let config = MetronomeConfig(bpm: 120, accents: AccentPattern(repeating: .strong, count: 4), sound: .voice)
        let renderer = ClickRenderer(voices: bank, config: config)
        renderer.masterGain = 1
        renderer.start(config: config)
        let n = 24_000 * 4
        let out = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { out.deallocate() }
        renderer.render(into: out, frames: n)
        for k in 0..<4 {
            XCTAssertEqual(out[k * 24_000 + 1_000], Float(k + 1) * 0.1, accuracy: 0.001, "第 \(k + 1) 拍")
        }
    }

    /// 我的声音比拍间隔长时，下一下在它的起音点之前淡出结束，不会叠在一起。
    func testLongCustomVoiceIsCutAtTheNextBeat() {
        let sr = 48_000.0
        let bank = VoiceBank(sampleRate: sr)
        bank.setDynamic(VoiceBank.customStrongSlot, samples: Array(repeating: 0.5, count: 96_000), sourceRate: sr)  // 2 秒
        let config = MetronomeConfig(bpm: 240, accents: AccentPattern(repeating: .strong, count: 4), sound: .custom)  // 每拍 12000 个采样
        let renderer = ClickRenderer(voices: bank, config: config)
        renderer.masterGain = 1
        renderer.start(config: config)
        let n = 12_000 * 2
        let out = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { out.deallocate() }
        renderer.render(into: out, frames: n)
        XCTAssertEqual(out[6_000], 0.5, accuracy: 0.001, "第一拍中间只有一个声音")
        XCTAssertLessThan(out[11_999], 0.01, "在下一拍之前淡出")
        XCTAssertEqual(out[18_000], 0.5, accuracy: 0.001, "第二拍中间也只有一个声音，没有叠加")
    }
}

/// 切分点：界面按它们画拍子方块里的格子并高亮，所以位置、所属切分和预测都要和实际发声一致。
final class SubdivisionTimelineTests: XCTestCase {
    private let sr = 48_000.0

    private func renderEvents(_ renderer: ClickRenderer, until end: Int64, chunk: Int = 256,
                              beforeChunk: (ClickRenderer) -> Void = { _ in }) -> [ClickEvent] {
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var events: [ClickEvent] = []
        while renderer.cursor < end {
            beforeChunk(renderer)
            renderer.render(into: buffer, frames: chunk) { events.append($0) }
        }
        return events
    }

    /// 每种切分：切分点落在“拍头 + offset × 一拍长度”（取整到采样），并带着自己那一拍的切分。
    func testEverySubdivisionPlacesClicksAtItsOffsets() {
        for sub in Subdivision.allCases {
            let config = MetronomeConfig(bpm: 100, subdivision: sub)
            let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sr), config: config)
            renderer.start(config: config)
            let beat = 60.0 / 100 * sr
            let events = renderEvents(renderer, until: Int64(beat * 8))
            XCTAssertEqual(events.count, 8 * sub.clickCount, "\(sub)")
            for e in events {
                XCTAssertEqual(e.subdivision, sub)
                let expected = (Double(e.beatSerial) + sub.offset(e.subIndex)) * beat
                XCTAssertEqual(Double(e.sample), expected.rounded(), accuracy: 1, "\(sub) \(e.beatSerial).\(e.subIndex)")
            }
        }
    }

    /// 播放中把附点改成十六分：当前这一拍的切分点照旧，从下一拍起每拍 4 个点，事件里的切分也同时换。
    func testChangingSubdivisionSwitchesAtTheNextBeat() {
        let config = MetronomeConfig(bpm: 120, subdivision: .dotted)
        let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sr), config: config)
        renderer.start(config: config)
        var changed = false
        let events = renderEvents(renderer, until: 48_000 * 3) { r in
            if !changed && r.cursor >= 30_000 {   // 第 2 拍（24000…48000）中间
                var c = r.scheduler.config
                c.subdivision = .sixteenth
                r.update(c)
                changed = true
            }
        }
        for e in events {
            XCTAssertEqual(e.subdivision, e.beatSerial < 2 ? .dotted : .sixteenth, "beat \(e.beatSerial)")
        }
        XCTAssertEqual(events.filter { $0.beatSerial == 1 }.count, 2)
        XCTAssertEqual(events.filter { $0.beatSerial == 2 }.count, 4)
    }

    /// 预测接口（发布给界面的“接下来的点”）和随后真正渲染出来的点逐个一致。
    func testPeekClicksPredictsWhatRenders() {
        let config = MetronomeConfig(bpm: 173, subdivision: .syncopation)
        let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sr), config: config)
        renderer.start(config: config)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { buffer.deallocate() }
        let window = Int(sr * 0.4)
        for _ in 0..<40 {
            var predicted: [ClickEvent] = []
            renderer.peekClicks(frames: window) { predicted.append($0) }
            var actual: [ClickEvent] = []
            let end = renderer.cursor + Int64(window)
            while renderer.cursor < end {
                renderer.render(into: buffer, frames: min(256, Int(end - renderer.cursor))) { actual.append($0) }
            }
            XCTAssertEqual(predicted, actual)
            XCTAssertFalse(actual.isEmpty)
        }
    }

    /// 波形里每个切分点的采样位置都有起音：紧接着的 2 ms 能量远大于之前的 2 ms（十六分、200 BPM，每 75 ms 一下）。
    func testSubdivisionClicksAreAudibleAtTheirSamples() {
        let config = MetronomeConfig(bpm: 200, subdivision: .sixteenth)
        let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sr), config: config)
        renderer.start(config: config)
        let total = Int(sr * 3)
        let audio = UnsafeMutablePointer<Float>.allocate(capacity: total + 512)
        defer { audio.deallocate() }
        var events: [ClickEvent] = []
        while renderer.cursor < Int64(total) {
            renderer.render(into: audio + Int(renderer.cursor), frames: 512) { events.append($0) }
        }
        let w = Int(sr * 0.002)
        func energy(_ from: Int) -> Float { (max(0, from)..<min(total, from + w)).reduce(0) { $0 + audio[$1] * audio[$1] } }
        let inside = events.filter { Int($0.sample) + w <= total }
        XCTAssertEqual(inside.count, 40)
        for e in inside {
            let s = Int(e.sample)
            let after = energy(s), before = energy(s - w)
            XCTAssertGreaterThan(after, before * 4 + 1e-6, "\(e.beatSerial).\(e.subIndex) 处没有起音")
        }
    }
}

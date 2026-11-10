import Foundation
import TunerKit

/// 按乐理为一种定弦自动生成某个和弦的可弹按法。
///
/// 硬性规则（`validate` 逐条检查，生成和人工校对的按法都要过）：
/// 1. 发声的弦都是和弦音；必须有根音；除 `optionalIntervals`（七和弦的五度）外的组成音都要有；
/// 2. 按弦的跨度 ≤ 4 品（最高品 − 最低品 ≤ 3）；
/// 3. 最多 4 根手指，允许 1 指横按（见 `FingerAssigner`）；
/// 4. 不弹的弦只能在两端，不能夹在中间；
/// 5. 至少 `minSounding` 根弦发声（吉他 4，尤克里里 3）；
/// 6. 用到空弦时，最高品不超过 4 品（高把位带空弦的按法没法用）。
///
/// 排序规则见 `sortKey`。
struct VoicingRules: Sendable {
    var minSounding: Int
    /// 是否把“最低音是根音”当作排序的第一优先（吉他；尤克里里是回弦调，没有这个概念）。
    var prefersRootInBass: Bool
    var maxFret = 12
    var maxSpan = 3
    var maxFingers = 4
    var maxFretWithOpenStrings = 4

    static func rules(for family: InstrumentFamily) -> VoicingRules? {
        switch family {
        case .guitar: return VoicingRules(minSounding: 4, prefersRootInBass: true)
        case .ukulele: return VoicingRules(minSounding: 3, prefersRootInBass: false)
        default: return nil
        }
    }
}

enum VoicingGenerator {
    /// 检查一组品位是不是这个和弦的合格按法；合格则返回带手指的 `ChordVoicing`。
    static func makeVoicing(frets: [Int], chord: Chord, tuning: Tuning, rules: VoicingRules) -> ChordVoicing? {
        guard frets.count == tuning.strings.count, !frets.isEmpty else { return nil }
        // 不弹的弦只能在两端
        let sounding = frets.indices.filter { frets[$0] >= 0 }
        guard sounding.count >= rules.minSounding,
              let first = sounding.first, let last = sounding.last,
              sounding.count == last - first + 1 else { return nil }
        let fretted = frets.filter { $0 > 0 }
        if let lo = fretted.min(), let hi = fretted.max() {
            guard hi <= rules.maxFret, hi - lo <= rules.maxSpan else { return nil }
            if frets.contains(0) && hi > rules.maxFretWithOpenStrings { return nil }
        }
        // 音名检查
        var covered = Set<Int>()
        for i in sounding {
            let pc = tuning.strings[i].pitch.transposed(by: frets[i]).pitchClass
            guard chord.degreeIndex(ofPitchClass: pc) != nil else { return nil }
            covered.insert(pc)
        }
        guard covered.contains(chord.root) else { return nil }
        let optional = Set(chord.type.optionalPitchClasses.map { (chord.root + $0) % 12 })
        for pc in chord.pitchClasses where !covered.contains(pc) && !optional.contains(pc) { return nil }
        guard let assigned = FingerAssigner.assign(frets: frets) else { return nil }
        return ChordVoicing(frets: frets, fingers: assigned.fingers, barre: assigned.barre, tuning: tuning)
    }

    /// 穷举一个和弦在指板 12 品以内的所有合格按法（未排序）。
    static func enumerate(chord: Chord, tuning: Tuning, rules: VoicingRules) -> [ChordVoicing] {
        let strings = tuning.strings
        let n = strings.count
        let tones = Set(chord.pitchClasses)
        func isTone(_ i: Int, _ fret: Int) -> Bool {
            tones.contains(strings[i].pitch.transposed(by: fret).pitchClass)
        }
        var result: [ChordVoicing] = []
        var seen = Set<[Int]>()

        // 窗口起点 b：按弦的最低品 = b，其余按弦落在 b…b+maxSpan；b = 0 表示完全不按弦（全空弦）。
        for b in 0...max(0, rules.maxFret - rules.maxSpan) {
            var options: [[Int]] = []
            for i in 0..<n {
                var o = [-1]
                if isTone(i, 0) { o.append(0) }
                if b > 0 {
                    for f in b...(b + rules.maxSpan) where f <= rules.maxFret && isTone(i, f) { o.append(f) }
                }
                options.append(o)
            }
            var current = [Int](repeating: -1, count: n)
            func walk(_ i: Int) {
                if i == n {
                    let fretted = current.filter { $0 > 0 }
                    if b == 0 ? !fretted.isEmpty : fretted.min() != b { return }
                    if seen.contains(current) { return }
                    if let v = makeVoicing(frets: current, chord: chord, tuning: tuning, rules: rules) {
                        seen.insert(current)
                        result.append(v)
                    }
                    return
                }
                for f in options[i] { current[i] = f; walk(i + 1) }
            }
            walk(0)
        }
        return result
    }

    // MARK: 排序

    /// 根音是不是发声的最低音。
    static func rootInBass(_ v: ChordVoicing, chord: Chord) -> Bool {
        v.lowestPitch?.pitchClass == chord.root
    }

    /// 是否省略了可省的音（五度）。
    static func omitsOptional(_ v: ChordVoicing, chord: Chord) -> Bool {
        let have = Set(v.pitches.compactMap { $0?.pitchClass })
        return chord.pitchClasses.contains { !have.contains($0) }
    }

    /// 排序键，越小越靠前：
    /// 1. 最低音不是根音的排后面（只对吉他）；2. 省略了五度的排后面；
    /// 3. 开放把位优先；4. 按弦位置低的优先；5. 不弹的弦少的优先；6. 用的手指少的优先；
    /// 7. 品位之和小的优先；最后按品位数组本身定序，保证结果稳定。
    static func sortKey(_ v: ChordVoicing, chord: Chord, rules: VoicingRules) -> [Int] {
        [
            rules.prefersRootInBass && !rootInBass(v, chord: chord) ? 1 : 0,
            omitsOptional(v, chord: chord) ? 1 : 0,
            v.isOpenPosition ? 0 : 1,
            v.minFret,
            v.mutedCount,
            v.fingerCount,
            v.frets.filter { $0 > 0 }.reduce(0, +),
        ] + v.frets
    }

    /// 去掉“只是另一个按法少弹几根弦”的重复项（两者的最低音状态相同才去掉）。
    static func removeSubsets(_ list: [ChordVoicing], chord: Chord, rules: VoicingRules) -> [ChordVoicing] {
        list.filter { v in
            !list.contains { w in
                w != v && w.soundingCount > v.soundingCount
                    && v.soundingStrings.allSatisfy { w.frets[$0] == v.frets[$0] }
                    && (!rules.prefersRootInBass || rootInBass(v, chord: chord) == rootInBass(w, chord: chord))
            }
        }
    }

    /// 生成并排序，保留前 `limit` 个。同一最低品位最多留 `perPosition` 个，让结果沿指板分布开。
    static func voicings(chord: Chord, instrumentID: String, tuning: Tuning, family: InstrumentFamily,
                         limit: Int = 8, perPosition: Int = 2) -> [ChordVoicing] {
        guard let rules = VoicingRules.rules(for: family), !tuning.isChromatic else { return [] }

        // 人工校对的按法排最前面
        var curated: [ChordVoicing] = []
        for text in CuratedShapes.shapes(instrumentID: instrumentID, tuningID: tuning.id, chord: chord) {
            if let frets = CuratedShapes.parse(text),
               let v = makeVoicing(frets: frets, chord: chord, tuning: tuning, rules: rules),
               !curated.contains(v) {
                curated.append(v)
            }
        }

        let generated = removeSubsets(enumerate(chord: chord, tuning: tuning, rules: rules), chord: chord, rules: rules)
            .map { (key: sortKey($0, chord: chord, rules: rules), voicing: $0) }
            .sorted { $0.key.lexicographicallyPrecedes($1.key) }

        var picked = curated
        var perPos: [Int: Int] = [:]
        for v in curated { perPos[v.minFret, default: 0] += 1 }
        for item in generated where picked.count < limit {
            let v = item.voicing
            if picked.contains(where: { $0.frets == v.frets }) { continue }
            if perPos[v.minFret, default: 0] >= perPosition { continue }
            perPos[v.minFret, default: 0] += 1
            picked.append(v)
        }
        return picked
    }
}

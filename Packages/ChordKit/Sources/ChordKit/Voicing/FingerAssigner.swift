import Foundation

/// 给一组按弦品位分配手指（1…4），必要时用 1 指横按。
///
/// 规则：
/// - 不用横按、按弦数 ≤ 4 时，每个音一根手指，按（品位，弦序）从小到大依次用 1、2、3、4；
///   只按 1~2 个音时手指号从“最低品位（至多到 5 − 音数）”起，符合 Em = 2、3 指的习惯；
/// - 否则尝试横按：1 指压住最低品位上第一根到最后一根弦，要求这段范围内每根弦都在按（不能有空弦/不弹的弦夹在中间）；
///   剩下的音最多 3 个，依次用 2、3、4；
/// - 都不行就返回 nil（这个按法弹不了）。
enum FingerAssigner {
    static func assign(frets: [Int]) -> (fingers: [Int], barre: ChordVoicing.Barre?)? {
        let fretted = frets.indices.filter { frets[$0] > 0 }
        var fingers = [Int](repeating: 0, count: frets.count)
        if fretted.isEmpty { return (fingers, nil) }

        func order(_ idx: [Int]) -> [Int] {
            idx.sorted { frets[$0] != frets[$1] ? frets[$0] < frets[$1] : $0 < $1 }
        }

        if fretted.count <= 4 {
            // 只按 1~2 个音时按习惯“指号 ≈ 品位”（Em 用 2、3 指，尤克里里 C 用 3 指），其余从 1 指起
            let n = fretted.count
            let first = n <= 2 ? max(1, min(frets[fretted.min { frets[$0] < frets[$1] }!], 5 - n)) : 1
            for (k, i) in order(fretted).enumerated() { fingers[i] = first + k }
            return (fingers, nil)
        }

        let f0 = fretted.map { frets[$0] }.min()!
        let atF0 = fretted.filter { frets[$0] == f0 }
        guard atF0.count >= 2, let lo = atF0.first, let hi = atF0.last else { return nil }
        for i in lo...hi where frets[i] < f0 { return nil }        // 横按范围内不能有空弦或不弹的弦
        let rest = fretted.filter { frets[$0] > f0 }
        guard rest.count <= 3 else { return nil }
        for i in lo...hi where frets[i] == f0 { fingers[i] = 1 }
        for (n, i) in order(rest).enumerated() { fingers[i] = n + 2 }
        return (fingers, ChordVoicing.Barre(fret: f0, fromString: lo, toString: hi, finger: 1))
    }
}

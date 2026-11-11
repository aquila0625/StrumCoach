import Foundation

/// 给一组按弦品位分配手指（1…4），必要时用 1 指横按。
///
/// 规则：
/// - 按弦数 ≤ 4 时，先看要不要像标准和弦图那样用食指小横按（见 `smallBarre`）；
///   不要的话每个音一根手指，按（品位，弦序）从小到大依次用 1、2、3、4；
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
            if let small = smallBarre(frets: frets, fretted: fretted) { return small }
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

    /// 按弦不超过 4 个时，像和弦图上的标准按法那样用食指小横按：
    /// - 最低品上有 3 根以上的弦，而且还有别的音要按（尤克里里 D7 2223、C# 1114），或者全部弦都在同一品（Bm7 2222）；
    /// - 最低品上正好是最细的两根相邻弦，而且还有别的音要按（尤克里里 Bb 3211、吉他 Dm7 xx0211）。
    /// 横按范围里每根弦都要按（不能夹空弦或不弹的弦）。其余的音按“一指一品”分 2、3、4 指（同一品的几根弦依次往后排）。
    /// 不符合就返回 nil，照旧每个音一根手指（尤克里里 D 2220、吉他 A x02220 仍是 1、2、3 指）。
    static func smallBarre(frets: [Int], fretted: [Int]) -> (fingers: [Int], barre: ChordVoicing.Barre?)? {
        let f0 = fretted.map { frets[$0] }.min()!
        let atF0 = fretted.filter { frets[$0] == f0 }
        let rest = fretted.filter { frets[$0] > f0 }
            .sorted { frets[$0] != frets[$1] ? frets[$0] < frets[$1] : $0 < $1 }
        guard let lo = atF0.first, let hi = atF0.last else { return nil }
        let useBarre = (atF0.count >= 3 && (!rest.isEmpty || atF0.count == frets.count))
            || (atF0.count == 2 && hi == lo + 1 && hi == frets.count - 1 && !rest.isEmpty)
        guard useBarre else { return nil }
        for i in lo...hi where frets[i] < f0 { return nil }
        var fingers = [Int](repeating: 0, count: frets.count)
        for i in lo...hi where frets[i] == f0 { fingers[i] = 1 }
        var previous = 1
        for i in rest {
            let finger = max(1 + (frets[i] - f0), previous + 1)
            guard finger <= 4 else { return nil }
            fingers[i] = finger
            previous = finger
        }
        return (fingers, ChordVoicing.Barre(fret: f0, fromString: lo, toString: hi, finger: 1, small: true))
    }
}

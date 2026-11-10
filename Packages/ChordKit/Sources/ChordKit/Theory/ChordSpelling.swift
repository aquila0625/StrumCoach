import Foundation

/// 和弦的拼法：同一个音级可以写成升音（C♯）或降音（D♭），这里决定显示哪一种。
///
/// - 根音用乐理上常用的写法：C♯、E♭、F♯、A♭、B♭。
/// - 组成音按音名字母推算（根音是 E♭，三度就写 G、五度写 B♭），保证和根音的升降一致，
///   例如 E♭ 大三是 E♭ G B♭，F 小三是 F A♭ C。
/// - 推算出 E♯、B♯、F♭、C♭ 或重升重降这类少见写法时，整个和弦退回统一的升号或降号写法，
///   例如 C♯ 大三写成 C♯ F G♯，B♭ 减三写成 B♭ D♭ E。
public enum ChordSpelling {
    /// 根音的惯用拼法是否用降号。
    public static func rootUsesFlats(_ pitchClass: Int) -> Bool {
        [3, 8, 10].contains(((pitchClass % 12) + 12) % 12)
    }

    /// 和弦里每个音（与 `type.intervals` 对应）是否写成降号。
    public static func flats(for chord: Chord) -> [Bool] {
        let naturals = [0, 2, 4, 5, 7, 9, 11]                 // C D E F G A B 的音级
        let rootLetter = [0, 0, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6][chord.root]   // 根音的字母序号（C=0 … B=6）
        var result: [Bool] = []
        var usual = true
        for (pc, degree) in zip(chord.pitchClasses, chord.type.degrees) {
            let digits = degree.filter(\.isNumber)
            let step = ((Int(digits) ?? 1) - 1) % 7
            let letter = (rootLetter + step) % 7
            let diff = ((pc - naturals[letter] + 18) % 12) - 6            // −6…5
            let unusual = abs(diff) > 1
                || (diff == 1 && (letter == 2 || letter == 6))             // E♯ B♯
                || (diff == -1 && (letter == 3 || letter == 0))            // F♭ C♭
            if unusual { usual = false }
            result.append(diff < 0)
        }
        if usual { return result }
        // 少见写法：统一用升号，或（F、E♭、A♭、B♭ 这些偏降号的根音）统一用降号
        let allFlats = rootUsesFlats(chord.root) || chord.root == 5
        return [Bool](repeating: allFlats, count: result.count)
    }

    /// 某个音级在这个和弦里是否写成降号；不是和弦音时按根音的倾向。
    public static func usesFlat(pitchClass: Int, in chord: Chord) -> Bool {
        let pc = ((pitchClass % 12) + 12) % 12
        if let i = chord.pitchClasses.firstIndex(of: pc) { return flats(for: chord)[i] }
        return rootUsesFlats(chord.root)
    }
}

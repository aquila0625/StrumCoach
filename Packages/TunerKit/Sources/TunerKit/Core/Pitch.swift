import Foundation

/// 调音器的全局常量。
public enum TunerDefaults {
    /// 标准音 A4 的默认频率。
    public static let a4: Double = 440
    /// 标准音 A4 允许调整的范围。
    public static let a4Range: ClosedRange<Double> = 415...466
    /// 判定“已准”的音分阈值（±5 音分）。
    public static let inTuneCents: Double = 5
}

/// 一个音高：用 MIDI 音符号表示（C4 = 60，A4 = 69），与标准音 A4 的频率无关。
///
/// 乐器定弦、和弦指法图都用它描述“这根弦是什么音”。
public struct Pitch: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let midi: Int

    public init(midi: Int) { self.midi = midi }

    /// 从 "E2"、"F#3"、"Bb1"、"A♯4" 这样的写法解析。
    public init?(_ text: String) {
        let chars = Array(text.trimmingCharacters(in: .whitespaces))
        guard chars.count >= 2 else { return nil }
        let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard var pc = base[Character(chars[0].uppercased())] else { return nil }
        var index = 1
        while index < chars.count {
            if chars[index] == "#" || chars[index] == "♯" {
                pc += 1
            } else if chars[index] == "b" || chars[index] == "♭" {
                pc -= 1
            } else { break }
            index += 1
        }
        guard let octave = Int(String(chars[index...])) else { return nil }
        self.midi = (octave + 1) * 12 + pc
    }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }

    /// 0...11，C = 0。
    public var pitchClass: Int { ((midi % 12) + 12) % 12 }
    /// 科学音高记法的八度（C4 = 中央 C）。
    public var octave: Int { Int((Double(midi) / 12).rounded(.down)) - 1 }

    public static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    public static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    /// 音名，不含八度，例如 "A♯"。
    public var name: String { Pitch.sharpNames[pitchClass] }
    public func name(useFlats: Bool) -> String {
        (useFlats ? Pitch.flatNames : Pitch.sharpNames)[pitchClass]
    }
    /// 音名加八度，例如 "A♯2"。
    public var fullName: String { "\(name)\(octave)" }
    public var description: String { fullName }

    /// 在给定标准音下的频率（Hz）。
    public func frequency(a4: Double = TunerDefaults.a4) -> Double {
        a4 * pow(2, Double(midi - 69) / 12)
    }

    public func transposed(by semitones: Int) -> Pitch { Pitch(midi: midi + semitones) }

    /// 频率对应的“连续 MIDI 音符号”，例如 440 Hz → 69.0，A4 偏高 25 音分 → 69.25。
    public static func fractionalMIDI(frequency: Double, a4: Double = TunerDefaults.a4) -> Double {
        69 + 12 * log2(frequency / a4)
    }

    /// 离频率最近的音，以及相对该音的偏差（音分，−50…+50）。
    public static func nearest(frequency: Double, a4: Double = TunerDefaults.a4) -> (pitch: Pitch, cents: Double) {
        let m = fractionalMIDI(frequency: frequency, a4: a4)
        let rounded = m.rounded()
        return (Pitch(midi: Int(rounded)), (m - rounded) * 100)
    }

    /// 两个频率之间的音分差（f1 相对 f2）。
    public static func cents(from f2: Double, to f1: Double) -> Double {
        1200 * log2(f1 / f2)
    }
}

/// 一次检测的结果：检测出的频率，以及它离哪个音最近、偏差多少音分。
public struct PitchReading: Equatable, Sendable {
    public let frequency: Double
    /// 置信度 0…1（越接近 1 越像一个干净的周期信号）。
    public let clarity: Double
    /// 计算音名时使用的标准音。
    public let a4: Double
    /// 最近的半音。
    public let pitch: Pitch
    /// 相对 `pitch` 的偏差，−50…+50 音分；正数表示偏高。
    public let cents: Double

    public init(frequency: Double, clarity: Double, a4: Double = TunerDefaults.a4) {
        self.frequency = frequency
        self.clarity = clarity
        self.a4 = a4
        let n = Pitch.nearest(frequency: frequency, a4: a4)
        self.pitch = n.pitch
        self.cents = n.cents
    }

    public var noteName: String { pitch.name }
    public var octave: Int { pitch.octave }
}

import Foundation
import SwiftUI

/// 音名的显示方式：字母（C D E）或唱名（Do Re Mi）。调音器、和弦库所有显示音名的地方都用它。
///
/// - 唱名按语言拼写：法语 Do Ré Mi，葡萄牙语 Dó Ré Mi，俄语 До Ре Ми，其余 Do Re Mi。
/// - 德语用字母时，B 显示为 H，B♭ 显示为 B。
/// 由 App 通过环境值 `\.noteNaming` 注入；不注入时是字母写法（和原来一样）。
public struct NoteNaming: Hashable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case letters, solfege
    }

    public var style: Style
    /// 界面语言（"de"、"fr"、"pt-BR" 等），决定唱名拼写和德语 H。
    public var languageCode: String

    public init(style: Style, languageCode: String) {
        self.style = style
        self.languageCode = languageCode
    }

    /// 字母写法，不做任何语言处理。
    public static let letters = NoteNaming(style: .letters, languageCode: "en")

    /// 法、意、西、葡、俄默认用唱名，其他语言默认用字母。
    public static func defaultStyle(forLanguage code: String) -> Style {
        ["fr", "it", "es", "pt", "ru"].contains(baseLanguage(code)) ? .solfege : .letters
    }

    private static func baseLanguage(_ code: String) -> String {
        String(code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }

    private var base: String { Self.baseLanguage(languageCode) }

    private var solfegeSyllables: [String] {
        switch base {
        case "fr": return ["Do", "Ré", "Mi", "Fa", "Sol", "La", "Si"]
        case "pt": return ["Dó", "Ré", "Mi", "Fá", "Sol", "Lá", "Si"]
        case "ru": return ["До", "Ре", "Ми", "Фа", "Соль", "Ля", "Си"]
        default: return ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"]
        }
    }

    /// 0…11 的音级 → 音名。
    /// - useFlats: 用降号写法（B♭）还是升号写法（A♯）。
    /// - ascii: 升降号写成 # / b（和弦库沿用的写法），否则 ♯ / ♭。
    public func name(pitchClass: Int, useFlats: Bool = false, ascii: Bool = false) -> String {
        let pc = ((pitchClass % 12) + 12) % 12
        let sharp = ascii ? "#" : "♯", flat = ascii ? "b" : "♭"
        // 每个音级：自然音的序号（C=0 … B=6）和升降
        let sharpSpelling: [(Int, Int)] = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)]
        let flatSpelling: [(Int, Int)] = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)]
        let (step, accidental) = (useFlats ? flatSpelling : sharpSpelling)[pc]
        let mark = accidental > 0 ? sharp : (accidental < 0 ? flat : "")
        switch style {
        case .solfege:
            return solfegeSyllables[step] + mark
        case .letters:
            let letters = ["C", "D", "E", "F", "G", "A", "B"]
            if base == "de" && step == 6 {
                // 德语：B → H，B♭ → B
                return accidental < 0 ? "B" : "H" + mark
            }
            return letters[step] + mark
        }
    }

    public func name(_ pitch: Pitch, useFlats: Bool = false) -> String {
        name(pitchClass: pitch.pitchClass, useFlats: useFlats)
    }

    /// 音名加八度，例如 "A4"、"La4"。
    public func fullName(_ pitch: Pitch) -> String { "\(name(pitch))\(pitch.octave)" }
}

private struct NoteNamingKey: EnvironmentKey {
    static let defaultValue = NoteNaming.letters
}

extension EnvironmentValues {
    /// 音名显示方式。App 按“音名显示”设置注入。
    public var noteNaming: NoteNaming {
        get { self[NoteNamingKey.self] }
        set { self[NoteNamingKey.self] = newValue }
    }
}

import Foundation
import TunerKit

/// 贝斯上的和弦音位置：不按和弦指法，而是在一个把位框（5 品）里标出
/// 根音、三度、五度和八度在指板上的位置，方便弹分解和弦或琶音。
public struct BassPositions: Hashable, Codable, Sendable {
    public enum Role: String, Codable, Sendable { case root, third, fifth, octave }

    public struct Marker: Hashable, Codable, Sendable {
        /// 弦的物理序号，与定弦一致（0 = 最粗的一根）。
        public let string: Int
        /// 品位，0 = 空弦。
        public let fret: Int
        public let role: Role
        public let pitch: Pitch
        /// 在界面上显示的短标：根音 "R"、三度写它的级数（"3"、"♭3"、"2"、"4"）、五度 "5"/"♭5"/"♯5"、八度 "8"。
        public let label: String
    }

    public let chord: Chord
    /// 把位框的起点：0 表示含空弦（画琴枕，格子从 1 品起），否则就是第一行的品位。
    public let startFret: Int
    /// 把位框包含几格（几品，不含空弦）。
    public let fretCount: Int
    public let stringCount: Int
    public let markers: [Marker]
    /// 作为参照的那个根音（把位框就围绕它定）。
    public let anchor: Marker?

    public var showsNut: Bool { startFret == 0 }
    /// 第一行格子的品位。
    public var firstRow: Int { max(startFret, 1) }

    /// 本和弦在这个把位里用到的角色顺序（图例用）。
    public var roles: [Role] { [.root, .third, .fifth, .octave] }

    public static let defaultFretCount = 5

    /// 生成贝斯的和弦音位置。
    ///
    /// 参照点：品位最低的根音（并列取更粗的弦），但要保证高一个八度的根音也在框里，
    /// 否则换下一个。框从参照点前一品开始，参照点是空弦时框从空弦开始。框里每根弦上的和弦音都会标出来。
    public static func make(chord: Chord, tuning: Tuning, fretCount: Int = defaultFretCount) -> BassPositions? {
        guard !tuning.isChromatic, !tuning.strings.isEmpty else { return nil }
        let strings = tuning.strings
        let type = chord.type
        let rootPC = chord.root

        // 参照根音：从低品位往高品位找（并列取更粗的弦），第一个让八度也落在框里的
        var candidates: [(string: Int, fret: Int)] = []
        for (i, s) in strings.enumerated() {
            let base = ((rootPC - s.pitch.pitchClass) % 12 + 12) % 12
            for fret in stride(from: base, through: 12, by: 12) { candidates.append((i, fret)) }
        }
        candidates.sort { $0.fret != $1.fret ? $0.fret < $1.fret : strings[$0.string].pitch < strings[$1.string].pitch }
        func window(_ fret: Int) -> (start: Int, firstRow: Int, lastRow: Int) {
            let start = fret == 0 ? 0 : max(1, fret - 1)
            let first = max(start, 1)
            return (start, first, first + fretCount - 1)
        }
        func containsOctave(_ c: (string: Int, fret: Int)) -> Bool {
            let target = strings[c.string].pitch.transposed(by: c.fret + 12)
            let w = window(c.fret)
            return strings.enumerated().contains { i, s in
                (w.start...w.lastRow).contains(target.midi - s.pitch.midi)
            }
        }
        guard let anchorPos = candidates.first(where: containsOctave) ?? candidates.first else { return nil }
        let anchorPitch = strings[anchorPos.string].pitch.transposed(by: anchorPos.fret)
        let w = window(anchorPos.fret)
        let start = w.start
        let lastRow = w.lastRow

        let thirdPC = (rootPC + type.intervals[1]) % 12
        let fifthPC = type.intervals.count > 2 ? (rootPC + type.intervals[2]) % 12 : rootPC

        var markers: [Marker] = []
        for (i, s) in strings.enumerated() {
            for fret in start...lastRow {
                let p = s.pitch.transposed(by: fret)
                let pc = p.pitchClass
                var role: Role?
                var label = ""
                if pc == rootPC {
                    role = p == anchorPitch ? .root : .octave
                    label = role == .root ? "R" : "8"
                } else if pc == thirdPC {
                    role = .third; label = type.degrees[1]
                } else if pc == fifthPC, type.intervals.count > 2 {
                    role = .fifth; label = type.degrees[2]
                }
                if let role { markers.append(Marker(string: i, fret: fret, role: role, pitch: p, label: label)) }
            }
        }
        let anchor = markers.first { $0.string == anchorPos.string && $0.fret == anchorPos.fret }
        return BassPositions(chord: chord, startFret: start, fretCount: fretCount, stringCount: strings.count,
                             markers: markers, anchor: anchor)
    }

    /// 某个角色的所有位置。
    public func markers(for role: Role) -> [Marker] { markers.filter { $0.role == role } }
}

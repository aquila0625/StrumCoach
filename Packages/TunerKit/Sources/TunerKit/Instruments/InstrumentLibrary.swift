import Foundation

/// 内置的乐器与定弦数据。要加乐器或定弦，只需在这里加一条。
public enum InstrumentLibrary {
    public static let auto = Instrument(
        id: "auto", family: .chromatic, name: "自动", englishName: "Auto",
        tunings: [Tuning(id: "chromatic", name: "半音阶", englishName: "Chromatic", pitches: [])])

    public static let guitar = Instrument(
        id: "guitar", family: .guitar, name: "吉他", englishName: "Guitar",
        tunings: [
            Tuning(id: "standard", name: "标准", englishName: "Standard", notes: "E2 A2 D3 G3 B3 E4"),
            Tuning(id: "dropD", name: "Drop D", englishName: "Drop D", notes: "D2 A2 D3 G3 B3 E4"),
            Tuning(id: "halfDown", name: "降半音 E♭", englishName: "Half step down", notes: "Eb2 Ab2 Db3 Gb3 Bb3 Eb4"),
            Tuning(id: "dadgad", name: "DADGAD", englishName: "DADGAD", notes: "D2 A2 D3 G3 A3 D4"),
        ])

    public static let bass = Instrument(
        id: "bass", family: .bass, name: "贝斯", englishName: "Bass",
        tunings: [
            Tuning(id: "4string", name: "4 弦 EADG", englishName: "4-string EADG", notes: "E1 A1 D2 G2"),
            Tuning(id: "5string", name: "5 弦 BEADG", englishName: "5-string BEADG", notes: "B0 E1 A1 D2 G2"),
        ])

    public static let ukulele = Instrument(
        id: "ukulele", family: .ukulele, name: "尤克里里", englishName: "Ukulele",
        tunings: [
            Tuning(id: "highG", name: "标准 GCEA", englishName: "Standard GCEA", notes: "G4 C4 E4 A4"),
            Tuning(id: "lowG", name: "低音 G 版", englishName: "Low G", notes: "G3 C4 E4 A4"),
        ])

    public static let violin = Instrument(
        id: "violin", family: .violin, name: "小提琴", englishName: "Violin",
        tunings: [Tuning(id: "standard", name: "标准 GDAE", englishName: "Standard GDAE", notes: "G3 D4 A4 E5")])

    public static let viola = Instrument(
        id: "viola", family: .viola, name: "中提琴", englishName: "Viola",
        tunings: [Tuning(id: "standard", name: "标准 CGDA", englishName: "Standard CGDA", notes: "C3 G3 D4 A4")])

    public static let cello = Instrument(
        id: "cello", family: .cello, name: "大提琴", englishName: "Cello",
        tunings: [Tuning(id: "standard", name: "标准 CGDA", englishName: "Standard CGDA", notes: "C2 G2 D3 A3")])

    /// 列表顺序即界面显示顺序。
    public static let all: [Instrument] = [auto, guitar, bass, ukulele, violin, viola, cello]

    public static func instrument(id: String) -> Instrument? { all.first { $0.id == id } }
}

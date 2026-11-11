package com.example.strumcoach.tuner

/** 乐器大类。调音器和和弦库共用。 */
enum class InstrumentFamily(val id: String) {
    /** 半音阶（自动识别任意音，没有琴弦）。 */
    CHROMATIC("chromatic"),
    GUITAR("guitar"), BASS("bass"), UKULELE("ukulele"),
    VIOLIN("violin"), VIOLA("viola"), CELLO("cello");

    companion object {
        fun fromId(id: String) = entries.firstOrNull { it.id == id }
    }
}

/** 一根弦。 */
data class InstrumentString(
    /** 在定弦里的位置，0 = 物理排列的第一根（吉他上是最粗的 6 弦）。 */
    val index: Int,
    /** 常规的弦号：吉他 6…1（6 弦最粗）。回弦乐器（如尤克里里）按物理位置编号。 */
    val number: Int,
    val pitch: Pitch,
)

/**
 * 一种定弦，例如“吉他 · 标准 EADGBE”。
 * `strings` 按物理顺序排列（从最粗的一根到最细的一根），**不保证音高递增**：
 * 尤克里里的高音 G 定弦（G4 C4 E4 A4）第一根弦就比第二根高。
 */
data class Tuning(
    val id: String,
    val name: String,
    val englishName: String,
    val strings: List<InstrumentString>,
) {
    constructor(id: String, name: String, englishName: String, notes: String) :
        this(id, name, englishName, stringsOf(notes.split(' ').filter { it.isNotEmpty() }.mapNotNull { Pitch.parse(it) }))

    val stringCount: Int get() = strings.size
    val isChromatic: Boolean get() = strings.isEmpty()

    /** 去掉八度的音名简写，例如 "E A D G B E"。 */
    fun shortLabel(useFlats: Boolean = false) = strings.joinToString(" ") { it.pitch.name(useFlats) }

    companion object {
        /** 按物理顺序给每根弦编号：第一根（最粗）的弦号最大。 */
        fun stringsOf(pitches: List<Pitch>): List<InstrumentString> =
            pitches.mapIndexed { i, p -> InstrumentString(i, pitches.size - i, p) }
    }
}

/** 一件乐器，带它的若干种定弦。 */
data class Instrument(
    val id: String,
    val family: InstrumentFamily,
    val name: String,
    val englishName: String,
    val tunings: List<Tuning>,
    /** 默认定弦的 id（取 `tunings` 中的一个）。 */
    val defaultTuningID: String = tunings[0].id,
) {
    val defaultTuning: Tuning get() = tuning(defaultTuningID) ?: tunings[0]
    fun tuning(id: String): Tuning? = tunings.firstOrNull { it.id == id }
    val isChromatic: Boolean get() = family == InstrumentFamily.CHROMATIC
}

/** “选了哪件乐器、哪种定弦”：调音器和和弦库共用。 */
data class InstrumentSelection(val instrumentID: String, val tuningID: String) {
    /** 解析为具体对象；id 失效时回退到该乐器的默认定弦，再回退到“自动”。 */
    fun resolve(library: List<Instrument> = InstrumentLibrary.all): Pair<Instrument, Tuning> {
        val inst = library.firstOrNull { it.id == instrumentID } ?: library[0]
        return inst to (inst.tuning(tuningID) ?: inst.defaultTuning)
    }

    companion object {
        val Default = InstrumentSelection("auto", "chromatic")
    }
}

/** 内置的乐器与定弦数据。要加乐器或定弦，只需在这里加一条。 */
object InstrumentLibrary {
    val auto = Instrument(
        "auto", InstrumentFamily.CHROMATIC, "自动", "Auto",
        listOf(Tuning("chromatic", "半音阶", "Chromatic", "")),
    )

    val guitar = Instrument(
        "guitar", InstrumentFamily.GUITAR, "吉他", "Guitar",
        listOf(
            Tuning("standard", "标准", "Standard", "E2 A2 D3 G3 B3 E4"),
            Tuning("dropD", "Drop D", "Drop D", "D2 A2 D3 G3 B3 E4"),
            Tuning("halfDown", "降半音 E♭", "Half step down", "Eb2 Ab2 Db3 Gb3 Bb3 Eb4"),
            Tuning("dadgad", "DADGAD", "DADGAD", "D2 A2 D3 G3 A3 D4"),
        ),
    )

    val bass = Instrument(
        "bass", InstrumentFamily.BASS, "贝斯", "Bass",
        listOf(
            Tuning("4string", "4 弦 EADG", "4-string EADG", "E1 A1 D2 G2"),
            Tuning("5string", "5 弦 BEADG", "5-string BEADG", "B0 E1 A1 D2 G2"),
        ),
    )

    val ukulele = Instrument(
        "ukulele", InstrumentFamily.UKULELE, "尤克里里", "Ukulele",
        listOf(
            Tuning("highG", "标准 GCEA", "Standard GCEA", "G4 C4 E4 A4"),
            Tuning("lowG", "低音 G 版", "Low G", "G3 C4 E4 A4"),
        ),
    )

    val violin = Instrument(
        "violin", InstrumentFamily.VIOLIN, "小提琴", "Violin",
        listOf(Tuning("standard", "标准 GDAE", "Standard GDAE", "G3 D4 A4 E5")),
    )

    val viola = Instrument(
        "viola", InstrumentFamily.VIOLA, "中提琴", "Viola",
        listOf(Tuning("standard", "标准 CGDA", "Standard CGDA", "C3 G3 D4 A4")),
    )

    val cello = Instrument(
        "cello", InstrumentFamily.CELLO, "大提琴", "Cello",
        listOf(Tuning("standard", "标准 CGDA", "Standard CGDA", "C2 G2 D3 A3")),
    )

    /** 列表顺序即界面显示顺序。 */
    val all: List<Instrument> = listOf(auto, guitar, bass, ukulele, violin, viola, cello)

    fun instrument(id: String): Instrument? = all.firstOrNull { it.id == id }
}

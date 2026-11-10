package com.example.tunebeatchord.chord

/** 12 个根音（升号写法）。 */
object ChordRoot {
    val names = listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
    val all = (0 until 12).toList()

    /** 0…11 → "C#" 等；越界会先折回。 */
    fun name(pitchClass: Int): String = names[((pitchClass % 12) + 12) % 12]
}

/**
 * 一种和弦类型：由距根音的半音数（`intervals`）定义。
 *
 * **加新类型**：在 [builtins] 里加一条即可，指法生成、组成音、界面网格都按数据工作。
 */
data class ChordType(
    /** 稳定的标识，会被存进收藏，不要改已发布的 id。 */
    val id: String,
    /** 接在根音后面的和弦记号，例如 "maj7"；大三和弦为空串。 */
    val symbol: String,
    /** 界面按钮上的短名。 */
    val shortName: String,
    val name: String,
    val englishName: String,
    /** 各组成音距根音的半音数，第一个必须是 0（根音）。 */
    val intervals: List<Int>,
    /** 各组成音的级数写法，与 `intervals` 一一对应，例如 ["1", "♭3", "5", "♭7"]。 */
    val degrees: List<String>,
    /** 在弦不够用时允许省略的音（半音数）。通常是七和弦类的纯五度。 */
    val optionalIntervals: List<Int> = emptyList(),
) {
    init {
        require(intervals.firstOrNull() == 0 && intervals.size == degrees.size) { "和弦类型定义不合法：$id" }
    }

    /** 允许省略的音（折回八度内）。 */
    val optionalPitchClasses: Set<Int> get() = optionalIntervals.map { it % 12 }.toSet()

    companion object {
        val Major = ChordType("major", "", "大三", "大三和弦", "Major", listOf(0, 4, 7), listOf("1", "3", "5"))
        val Minor = ChordType("minor", "m", "小三", "小三和弦", "Minor", listOf(0, 3, 7), listOf("1", "♭3", "5"))
        val Dominant7 = ChordType(
            "dom7", "7", "7", "属七和弦", "Dominant 7th",
            listOf(0, 4, 7, 10), listOf("1", "3", "5", "♭7"), listOf(7),
        )
        val Major7 = ChordType(
            "maj7", "maj7", "maj7", "大七和弦", "Major 7th",
            listOf(0, 4, 7, 11), listOf("1", "3", "5", "7"), listOf(7),
        )
        val Minor7 = ChordType(
            "m7", "m7", "m7", "小七和弦", "Minor 7th",
            listOf(0, 3, 7, 10), listOf("1", "♭3", "5", "♭7"), listOf(7),
        )
        val Sus2 = ChordType("sus2", "sus2", "sus2", "挂二和弦", "Suspended 2nd", listOf(0, 2, 7), listOf("1", "2", "5"))
        val Sus4 = ChordType("sus4", "sus4", "sus4", "挂四和弦", "Suspended 4th", listOf(0, 5, 7), listOf("1", "4", "5"))
        val Diminished = ChordType("dim", "dim", "dim", "减三和弦", "Diminished", listOf(0, 3, 6), listOf("1", "♭3", "♭5"))
        val Augmented = ChordType("aug", "aug", "aug", "增三和弦", "Augmented", listOf(0, 4, 8), listOf("1", "3", "♯5"))
        val Add9 = ChordType(
            "add9", "add9", "add9", "加九和弦", "Add 9",
            listOf(0, 4, 7, 14), listOf("1", "3", "5", "9"), listOf(7),
        )

        /** 内置类型，顺序即界面网格的显示顺序。 */
        val builtins = listOf(Major, Minor, Dominant7, Major7, Minor7, Sus2, Sus4, Diminished, Augmented, Add9)

        fun byId(id: String): ChordType? = builtins.firstOrNull { it.id == id }
    }
}

/** 一个和弦：根音 + 类型。 */
data class Chord(val rootPitchClass: Int, val type: ChordType) {
    /** 根音的音级，0…11，C = 0。 */
    val root: Int = ((rootPitchClass % 12) + 12) % 12

    val id: String get() = "$root-${type.id}"
    val rootName: String get() = ChordRoot.name(root)

    /** 完整的和弦名，例如 "Cmaj7"、"F#m"、"G"。 */
    val name: String get() = rootName + type.symbol

    /** 组成音的音级（0…11），顺序与 `type.intervals` 一致。 */
    val pitchClasses: List<Int> get() = type.intervals.map { (root + it) % 12 }

    /** 组成音的音名，例如 ["C", "E", "G", "B"]。 */
    val toneNames: List<String> get() = pitchClasses.map(ChordRoot::name)

    /** 音级 → 它在和弦里的级数序号（0 = 根音）。 */
    fun degreeIndex(pitchClass: Int): Int? =
        pitchClasses.indexOf(((pitchClass % 12) + 12) % 12).takeIf { it >= 0 }

    override fun equals(other: Any?) = other is Chord && other.root == root && other.type == type
    override fun hashCode() = 31 * root + type.hashCode()

    companion object {
        /** 例如 `Chord.of("C#", ChordType.Minor7)`；根音写 "C#" 或 "C♯" 或 "Db" 都行，不认识返回 null。 */
        fun of(rootName: String, type: ChordType): Chord? = pitchClassOf(rootName)?.let { Chord(it, type) }

        fun pitchClassOf(name: String): Int? {
            val text = name.trim()
            val first = text.firstOrNull() ?: return null
            val base = mapOf('C' to 0, 'D' to 2, 'E' to 4, 'F' to 5, 'G' to 7, 'A' to 9, 'B' to 11)
            var pc = base[first.uppercaseChar()] ?: return null
            for (c in text.drop(1)) {
                when (c) {
                    '#', '♯' -> pc += 1
                    'b', '♭' -> pc -= 1
                    else -> return null
                }
            }
            return ((pc % 12) + 12) % 12
        }
    }
}

/**
 * 和弦的拼法：同一个音级可以写成升音（C♯）或降音（D♭），这里决定显示哪一种。
 *
 * - 根音用乐理上常用的写法：C♯、E♭、F♯、A♭、B♭。
 * - 组成音按音名字母推算，保证和根音的升降一致，例如 E♭ 大三是 E♭ G B♭，F 小三是 F A♭ C。
 * - 推算出 E♯、B♯、F♭、C♭ 或重升重降这类少见写法时，整个和弦退回统一的升号或降号写法。
 */
object ChordSpelling {
    /** 根音的惯用拼法是否用降号。 */
    fun rootUsesFlats(pitchClass: Int) = (((pitchClass % 12) + 12) % 12) in setOf(3, 8, 10)

    /** 和弦里每个音（与 `type.intervals` 对应）是否写成降号。 */
    fun flats(chord: Chord): List<Boolean> {
        val naturals = listOf(0, 2, 4, 5, 7, 9, 11)                           // C D E F G A B 的音级
        val rootLetter = listOf(0, 0, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6)[chord.root]  // 根音的字母序号（C=0 … B=6）
        val result = ArrayList<Boolean>()
        var usual = true
        for ((pc, degree) in chord.pitchClasses.zip(chord.type.degrees)) {
            val digits = degree.filter { it.isDigit() }
            val step = ((digits.toIntOrNull() ?: 1) - 1) % 7
            val letter = (rootLetter + step) % 7
            val diff = ((pc - naturals[letter] + 18) % 12) - 6                 // −6…5
            val unusual = Math.abs(diff) > 1 ||
                (diff == 1 && (letter == 2 || letter == 6)) ||                // E♯ B♯
                (diff == -1 && (letter == 3 || letter == 0))                  // F♭ C♭
            if (unusual) usual = false
            result.add(diff < 0)
        }
        if (usual) return result
        // 少见写法：统一用升号，或（F、E♭、A♭、B♭ 这些偏降号的根音）统一用降号
        val allFlats = rootUsesFlats(chord.root) || chord.root == 5
        return List(result.size) { allFlats }
    }

    /** 某个音级在这个和弦里是否写成降号；不是和弦音时按根音的倾向。 */
    fun usesFlat(pitchClass: Int, chord: Chord): Boolean {
        val pc = ((pitchClass % 12) + 12) % 12
        val i = chord.pitchClasses.indexOf(pc)
        return if (i >= 0) flats(chord)[i] else rootUsesFlats(chord.root)
    }
}

/** 一条收藏：哪件乐器上的哪个和弦的第几个把位。 */
data class ChordFavorite(
    val instrumentID: String,
    val tuningID: String,
    /** 根音音级 0…11。 */
    val root: Int,
    val typeID: String,
    /** `ChordLibrary.voicings` 返回数组里的序号；贝斯固定为 0。 */
    val voicingIndex: Int,
) {
    val id: String get() = "$instrumentID/$tuningID/$root/$typeID/$voicingIndex"
    val chord: Chord? get() = ChordType.byId(typeID)?.let { Chord(root, it) }
}

/** 收藏夹：新收藏排在最前，不重复。 */
data class ChordFavorites(val items: List<ChordFavorite> = emptyList()) {
    operator fun contains(f: ChordFavorite) = f in items
    fun add(f: ChordFavorite) = if (f in items) this else ChordFavorites(listOf(f) + items)
    fun remove(f: ChordFavorite) = ChordFavorites(items.filter { it != f })

    /** 已收藏则取消，否则加入。 */
    fun toggle(f: ChordFavorite) = if (f in items) remove(f) else add(f)
}

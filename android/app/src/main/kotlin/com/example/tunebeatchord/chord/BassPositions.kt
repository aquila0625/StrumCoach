package com.example.tunebeatchord.chord

import com.example.tunebeatchord.tuner.Pitch
import com.example.tunebeatchord.tuner.Tuning

/**
 * 贝斯上的和弦音位置：不按和弦指法，而是在一个把位框（5 品）里标出根音、三度、五度和八度在指板上的位置，
 * 方便弹分解和弦或琶音。
 */
class BassPositions private constructor(
    val chord: Chord,
    /** 把位框的起点：0 表示含空弦（画琴枕，格子从 1 品起），否则就是第一行的品位。 */
    val startFret: Int,
    /** 把位框包含几格（几品，不含空弦）。 */
    val fretCount: Int,
    val stringCount: Int,
    val markers: List<Marker>,
    /** 作为参照的那个根音（把位框就围绕它定）。 */
    val anchor: Marker?,
) {
    enum class Role { ROOT, THIRD, FIFTH, OCTAVE }

    data class Marker(
        /** 弦的物理序号，与定弦一致（0 = 最粗的一根）。 */
        val string: Int,
        /** 品位，0 = 空弦。 */
        val fret: Int,
        val role: Role,
        val pitch: Pitch,
        /** 界面上的短标：根音 "R"、三度写它的级数、五度 "5"/"♭5"/"♯5"、八度 "8"。 */
        val label: String,
    )

    val showsNut get() = startFret == 0

    /** 第一行格子的品位。 */
    val firstRow get() = maxOf(startFret, 1)

    val roles = listOf(Role.ROOT, Role.THIRD, Role.FIFTH, Role.OCTAVE)

    fun markers(role: Role) = markers.filter { it.role == role }

    companion object {
        const val DEFAULT_FRET_COUNT = 5

        /**
         * 生成贝斯的和弦音位置。参照点：品位最低的根音（并列取更粗的弦），但要保证高一个八度的根音也在框里，否则换下一个。
         * 框从参照点前一品开始，参照点是空弦时框从空弦开始。框里每根弦上的和弦音都会标出来。
         */
        fun make(chord: Chord, tuning: Tuning, fretCount: Int = DEFAULT_FRET_COUNT): BassPositions? {
            if (tuning.isChromatic || tuning.strings.isEmpty()) return null
            val strings = tuning.strings
            val type = chord.type
            val rootPC = chord.root

            data class Cand(val string: Int, val fret: Int)

            val candidates = ArrayList<Cand>()
            for ((i, s) in strings.withIndex()) {
                val base = ((rootPC - s.pitch.pitchClass) % 12 + 12) % 12
                var fret = base
                while (fret <= 12) {
                    candidates.add(Cand(i, fret)); fret += 12
                }
            }
            candidates.sortWith { a, b ->
                if (a.fret != b.fret) a.fret.compareTo(b.fret)
                else strings[a.string].pitch.compareTo(strings[b.string].pitch)
            }

            fun window(fret: Int): Triple<Int, Int, Int> {
                val start = if (fret == 0) 0 else maxOf(1, fret - 1)
                val first = maxOf(start, 1)
                return Triple(start, first, first + fretCount - 1)
            }

            fun containsOctave(c: Cand): Boolean {
                val target = strings[c.string].pitch.transposed(c.fret + 12)
                val w = window(c.fret)
                return strings.any { s -> (target.midi - s.pitch.midi) in w.first..w.third }
            }

            val anchorPos = candidates.firstOrNull { containsOctave(it) } ?: candidates.firstOrNull() ?: return null
            val anchorPitch = strings[anchorPos.string].pitch.transposed(anchorPos.fret)
            val w = window(anchorPos.fret)
            val start = w.first
            val lastRow = w.third

            val thirdPC = (rootPC + type.intervals[1]) % 12
            val fifthPC = if (type.intervals.size > 2) (rootPC + type.intervals[2]) % 12 else rootPC

            val markers = ArrayList<Marker>()
            for ((i, s) in strings.withIndex()) {
                for (fret in start..lastRow) {
                    val p = s.pitch.transposed(fret)
                    val pc = p.pitchClass
                    var role: Role? = null
                    var label = ""
                    if (pc == rootPC) {
                        role = if (p == anchorPitch) Role.ROOT else Role.OCTAVE
                        label = if (role == Role.ROOT) "R" else "8"
                    } else if (pc == thirdPC) {
                        role = Role.THIRD; label = type.degrees[1]
                    } else if (pc == fifthPC && type.intervals.size > 2) {
                        role = Role.FIFTH; label = type.degrees[2]
                    }
                    if (role != null) markers.add(Marker(i, fret, role, p, label))
                }
            }
            val anchor = markers.firstOrNull { it.string == anchorPos.string && it.fret == anchorPos.fret }
            return BassPositions(chord, start, fretCount, strings.size, markers, anchor)
        }
    }
}

package com.example.tunebeatchord.tuner

import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

/** 调音器的全局常量。 */
object TunerDefaults {
    /** 标准音 A4 的默认频率。 */
    const val A4 = 440.0

    /** 标准音 A4 允许调整的范围。 */
    val a4Range = 415.0..466.0

    /** 判定“已准”的音分阈值（±5 音分）。 */
    const val IN_TUNE_CENTS = 5.0
}

private fun log2(x: Double) = ln(x) / ln(2.0)

/**
 * 一个音高：用 MIDI 音符号表示（C4 = 60，A4 = 69），与标准音 A4 的频率无关。
 * 乐器定弦、和弦指法图都用它描述“这根弦是什么音”。
 */
data class Pitch(val midi: Int) : Comparable<Pitch> {

    override fun compareTo(other: Pitch) = midi.compareTo(other.midi)

    /** 0…11，C = 0。 */
    val pitchClass: Int get() = ((midi % 12) + 12) % 12

    /** 科学音高记法的八度（C4 = 中央 C）。 */
    val octave: Int get() = Math.floorDiv(midi, 12) - 1

    /** 音名，不含八度，例如 "A♯"。 */
    val name: String get() = sharpNames[pitchClass]

    fun name(useFlats: Boolean): String = (if (useFlats) flatNames else sharpNames)[pitchClass]

    /** 音名加八度，例如 "A♯2"。 */
    val fullName: String get() = "$name$octave"

    override fun toString() = fullName

    /** 在给定标准音下的频率（Hz）。 */
    fun frequency(a4: Double = TunerDefaults.A4): Double = a4 * 2.0.pow((midi - 69) / 12.0)

    fun transposed(semitones: Int) = Pitch(midi + semitones)

    companion object {
        val sharpNames = listOf("C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B")
        val flatNames = listOf("C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B")

        private val base = mapOf('C' to 0, 'D' to 2, 'E' to 4, 'F' to 5, 'G' to 7, 'A' to 9, 'B' to 11)

        /** 从 "E2"、"F#3"、"Bb1"、"A♯4" 这样的写法解析；不合法返回 null。 */
        fun parse(text: String): Pitch? {
            val chars = text.trim()
            if (chars.length < 2) return null
            var pc = base[chars[0].uppercaseChar()] ?: return null
            var index = 1
            while (index < chars.length) {
                when (chars[index]) {
                    '#', '♯' -> pc += 1
                    'b', '♭' -> pc -= 1
                    else -> break
                }
                index++
            }
            val octave = chars.substring(index).toIntOrNull() ?: return null
            return Pitch((octave + 1) * 12 + pc)
        }

        /** 频率对应的“连续 MIDI 音符号”，例如 440 Hz → 69.0。 */
        fun fractionalMidi(frequency: Double, a4: Double = TunerDefaults.A4): Double =
            69 + 12 * log2(frequency / a4)

        /** 离频率最近的音，以及相对该音的偏差（音分，−50…+50）。 */
        fun nearest(frequency: Double, a4: Double = TunerDefaults.A4): Pair<Pitch, Double> {
            val m = fractionalMidi(frequency, a4)
            val rounded = floor(m + 0.5)
            return Pitch(rounded.toInt()) to (m - rounded) * 100
        }

        /** 两个频率之间的音分差（`to` 相对 `from`）。 */
        fun cents(from: Double, to: Double): Double = 1200 * log2(to / from)
    }
}

/** 一次检测的结果：检测出的频率，以及它离哪个音最近、偏差多少音分。 */
data class PitchReading(
    val frequency: Double,
    /** 置信度 0…1（越接近 1 越像一个干净的周期信号）。 */
    val clarity: Double,
    /** 计算音名时使用的标准音。 */
    val a4: Double = TunerDefaults.A4,
) {
    /** 最近的半音。 */
    val pitch: Pitch
    /** 相对 `pitch` 的偏差，−50…+50 音分；正数表示偏高。 */
    val cents: Double

    init {
        val (p, c) = Pitch.nearest(frequency, a4)
        pitch = p
        cents = c
    }

    val noteName: String get() = pitch.name
    val octave: Int get() = pitch.octave
}

internal fun Double.roundedInt(): Int = roundToInt()

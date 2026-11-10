package com.example.tunebeatchord.tuner

/**
 * 音名的显示方式：字母（C D E）或唱名（Do Re Mi）。调音器、和弦库所有显示音名的地方都用它。
 *
 * - 唱名按语言拼写：法语 Do Ré Mi，葡萄牙语 Dó Ré Mi，俄语 До Ре Ми，其余 Do Re Mi。
 * - 德语用字母时，B 显示为 H，B♭ 显示为 B。
 */
data class NoteNaming(val style: Style, val languageCode: String) {
    enum class Style { LETTERS, SOLFEGE }

    private val base: String get() = baseLanguage(languageCode)

    private val solfegeSyllables: List<String>
        get() = when (base) {
            "fr" -> listOf("Do", "Ré", "Mi", "Fa", "Sol", "La", "Si")
            "pt" -> listOf("Dó", "Ré", "Mi", "Fá", "Sol", "Lá", "Si")
            "ru" -> listOf("До", "Ре", "Ми", "Фа", "Соль", "Ля", "Си")
            else -> listOf("Do", "Re", "Mi", "Fa", "Sol", "La", "Si")
        }

    /**
     * 0…11 的音级 → 音名。
     * @param useFlats 用降号写法（B♭）还是升号写法（A♯）。
     * @param ascii 升降号写成 # / b（和弦库沿用的写法），否则 ♯ / ♭。
     */
    fun name(pitchClass: Int, useFlats: Boolean = false, ascii: Boolean = false): String {
        val pc = ((pitchClass % 12) + 12) % 12
        val sharp = if (ascii) "#" else "♯"
        val flat = if (ascii) "b" else "♭"
        val (step, accidental) = (if (useFlats) flatSpelling else sharpSpelling)[pc]
        val mark = when {
            accidental > 0 -> sharp
            accidental < 0 -> flat
            else -> ""
        }
        return when (style) {
            Style.SOLFEGE -> solfegeSyllables[step] + mark
            Style.LETTERS -> {
                if (base == "de" && step == 6) {
                    // 德语：B → H，B♭ → B
                    if (accidental < 0) "B" else "H$mark"
                } else letters[step] + mark
            }
        }
    }

    fun name(pitch: Pitch, useFlats: Boolean = false) = name(pitch.pitchClass, useFlats)

    /** 音名加八度，例如 "A4"、"La4"。 */
    fun fullName(pitch: Pitch) = "${name(pitch)}${pitch.octave}"

    companion object {
        /** 字母写法，不做任何语言处理。 */
        val Letters = NoteNaming(Style.LETTERS, "en")

        /** 法、意、西、葡、俄默认用唱名，其他语言默认用字母。 */
        fun defaultStyle(languageCode: String): Style =
            if (baseLanguage(languageCode) in setOf("fr", "it", "es", "pt", "ru")) Style.SOLFEGE else Style.LETTERS

        private fun baseLanguage(code: String) = code.split('-', '_').firstOrNull().orEmpty().lowercase()

        private val letters = listOf("C", "D", "E", "F", "G", "A", "B")
        private val sharpSpelling = listOf(
            0 to 0, 0 to 1, 1 to 0, 1 to 1, 2 to 0, 3 to 0, 3 to 1, 4 to 0, 4 to 1, 5 to 0, 5 to 1, 6 to 0,
        )
        private val flatSpelling = listOf(
            0 to 0, 1 to -1, 1 to 0, 2 to -1, 2 to 0, 3 to 0, 4 to -1, 4 to 0, 5 to -1, 5 to 0, 6 to -1, 6 to 0,
        )
    }
}

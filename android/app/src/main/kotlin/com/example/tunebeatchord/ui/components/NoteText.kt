package com.example.tunebeatchord.ui.components

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import com.example.tunebeatchord.R

/**
 * 升降号（♯ ♭ ♮）用内置的小字体画。有些手机的系统字体没有这几个符号，回退字体又宽又歪，
 * 在窄按钮里会被裁掉（只剩下字母），所以不依赖系统字体。字体是 Noto Sans Symbols 的子集（SIL OFL 1.1），只含这三个字形。
 */
val AccidentalFont = FontFamily(Font(R.font.note_accidentals))

private val accidentals = setOf('♯', '♭', '♮')

fun String.hasAccidental() = any { it in accidentals }

/** 把字符串里的升降号换成内置字体；其余字符保持原字体。`size` 不为 null 时升降号用这个相对大小（em）。 */
fun noteAnnotated(text: String, accidentalScale: Float = 1f): AnnotatedString = buildAnnotatedString {
    for (ch in text) {
        if (ch in accidentals) {
            pushStyle(SpanStyle(fontFamily = AccidentalFont, fontSize = androidx.compose.ui.unit.TextUnit.Unspecified))
            append(ch)
            pop()
        } else append(ch)
    }
}

/** 和弦名：根音大、后缀小，升降号用内置字体，例如 "E♭m7" → 大 E♭ + 小 m7。 */
fun chordAnnotated(root: String, suffix: String, rootSize: androidx.compose.ui.unit.TextUnit, suffixSize: androidx.compose.ui.unit.TextUnit): AnnotatedString =
    buildAnnotatedString {
        pushStyle(SpanStyle(fontSize = rootSize))
        append(noteAnnotated(root))
        pop()
        pushStyle(SpanStyle(fontSize = suffixSize))
        append(noteAnnotated(suffix))
        pop()
    }

/** Canvas 里画音名：字母用系统字体，升降号用内置字体，整体居中在 `cx`，基线在 `baseline`。 */
class NotePaints(context: Context) {
    private val accidentalFace: Typeface = androidx.core.content.res.ResourcesCompat.getFont(context, R.font.note_accidentals) ?: Typeface.DEFAULT

    fun draw(canvas: android.graphics.Canvas, text: String, cx: Float, baseline: Float, size: Float, color: Int, bold: Boolean) {
        val letters = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color; textSize = size
            typeface = Typeface.create(Typeface.DEFAULT, if (bold) Typeface.BOLD else Typeface.NORMAL)
        }
        val symbols = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; textSize = size * 0.95f; typeface = accidentalFace }
        // 先量总宽，再从左到右一段一段画
        val parts = ArrayList<Pair<String, Paint>>()
        val sb = StringBuilder()
        for (ch in text) {
            if (ch in accidentals) {
                if (sb.isNotEmpty()) { parts.add(sb.toString() to letters); sb.clear() }
                parts.add(ch.toString() to symbols)
            } else sb.append(ch)
        }
        if (sb.isNotEmpty()) parts.add(sb.toString() to letters)
        val total = parts.sumOf { it.second.measureText(it.first).toDouble() }.toFloat()
        var x = cx - total / 2
        for ((s, p) in parts) {
            canvas.drawText(s, x, baseline, p)
            x += p.measureText(s)
        }
    }
}

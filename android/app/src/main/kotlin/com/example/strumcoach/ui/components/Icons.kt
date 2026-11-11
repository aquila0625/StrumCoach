package com.example.strumcoach.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.strumcoach.rhythm.Subdivision

/** 一个音符：符杠数（0 = 四分音符不带符杠），是否附点。 */
class GlyphNote(val beams: Int, val dotted: Boolean = false)

/** 一拍里的切分写成音符（设计稿 parts1.js 的 N 表），和 iOS 版的 NoteGlyph 逐点一致。 */
class SubdivisionGlyph(val notes: List<GlyphNote>, val tuplet: Int? = null)

val Subdivision.glyph: SubdivisionGlyph
    get() = when (this) {
        Subdivision.QUARTER -> SubdivisionGlyph(listOf(GlyphNote(0)))
        Subdivision.EIGHTH -> SubdivisionGlyph(listOf(GlyphNote(1), GlyphNote(1)))
        Subdivision.TRIPLET -> SubdivisionGlyph(listOf(GlyphNote(1), GlyphNote(1), GlyphNote(1)), 3)
        Subdivision.SIXTEENTH -> SubdivisionGlyph(List(4) { GlyphNote(2) })
        Subdivision.DOTTED -> SubdivisionGlyph(listOf(GlyphNote(1, dotted = true), GlyphNote(2)))
        Subdivision.EIGHTH_SIXTEENTH -> SubdivisionGlyph(listOf(GlyphNote(1), GlyphNote(2), GlyphNote(2)))
        Subdivision.SIXTEENTH_EIGHTH -> SubdivisionGlyph(listOf(GlyphNote(2), GlyphNote(2), GlyphNote(1)))
        Subdivision.SYNCOPATION -> SubdivisionGlyph(listOf(GlyphNote(2), GlyphNote(1), GlyphNote(2)))
    }

/** 切分用的音符图（符头、符干、符杠、附点、三连音的 3）。画布 22 + (n−1)×11 宽、38 高，往上留 6 给连音数字。 */
@Composable
fun NoteGlyph(glyph: SubdivisionGlyph, color: Color, modifier: Modifier = Modifier, gap: Float = 11f) {
    val n = glyph.notes.size
    val w = (n - 1) * gap + 22
    Canvas(modifier.width(w.dp).height(38.dp)) {
        val d = density
        translate(0f, 6 * d) {
            val h = 30f
            val top = 6f
            val xs = (0 until n).map { 5 + it * gap }
            for ((i, note) in glyph.notes.withIndex()) {
                val x = xs[i]
                // 椭圆符头，倾斜 −20°
                rotate(-20f, pivot = Offset(x * d, (h - 3) * d)) {
                    drawOval(color, Offset((x - 4.6f) * d, (h - 3 - 3.4f) * d), Size(9.2f * d, 6.8f * d))
                }
                drawRect(color, Offset((x + 3.4f) * d, top * d), Size(1.6f * d, (h - 3 - top) * d))
                if (note.dotted) drawCircle(color, 1.6f * d, Offset((x + 9) * d, (h - 3) * d))
            }
            fun sx(i: Int) = xs[i] + 4.2f
            if (n > 1) {
                drawRect(color, Offset((sx(0) - 0.8f) * d, top * d), Size((sx(n - 1) - sx(0) + 1.6f) * d, 3.4f * d))
                for (i in 0 until n) if (glyph.notes[i].beams >= 2) {
                    val joinsNext = i + 1 < n && glyph.notes[i + 1].beams >= 2
                    if (joinsNext) {
                        drawRect(color, Offset((sx(i) - 0.8f) * d, (top + 5.5f) * d), Size((sx(i + 1) - sx(i) + 1.6f) * d, 3.4f * d))
                    } else if (!(i > 0 && glyph.notes[i - 1].beams >= 2)) {
                        val pointsLeft = i == n - 1
                        val len = 6f
                        drawRect(color, Offset((if (pointsLeft) sx(i) - len else sx(i) - 0.8f) * d, (top + 5.5f) * d), Size((len + 0.8f) * d, 3.4f * d))
                    }
                }
            }
            glyph.tuplet?.let { t ->
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    this.color = color.toArgb()
                    textSize = 9 * d
                    textAlign = android.graphics.Paint.Align.CENTER
                    typeface = android.graphics.Typeface.DEFAULT_BOLD
                }
                drawContext.canvas.nativeCanvas.drawText("$t", ((sx(0) + sx(n - 1)) / 2) * d, (top - 3) * d, paint)
            }
        }
    }
}

/** 行尾的“>”（向右的小箭头）。 */
@Composable
fun ChevronRight(color: Color, size: Dp = 14.dp) {
    Canvas(Modifier.width(size).height(size)) {
        val s = this.size.minDimension
        val p = Path().apply { moveTo(s * 0.32f, s * 0.15f); lineTo(s * 0.7f, s * 0.5f); lineTo(s * 0.32f, s * 0.85f) }
        drawPath(p, color, style = Stroke(s * 0.14f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** 向下的小箭头（下拉）。 */
@Composable
fun ChevronDown(color: Color, size: Dp = 12.dp) {
    Canvas(Modifier.width(size).height(size)) {
        val s = this.size.minDimension
        val p = Path().apply { moveTo(s * 0.12f, s * 0.32f); lineTo(s * 0.5f, s * 0.7f); lineTo(s * 0.88f, s * 0.32f) }
        drawPath(p, color, style = Stroke(s * 0.14f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** 播放三角、暂停两竖。 */
@Composable
fun PlayPauseIcon(playing: Boolean, color: Color, size: Dp = 34.dp) {
    Canvas(Modifier.width(size).height(size)) {
        val w = this.size.width
        val h = this.size.height
        if (playing) {
            drawRoundRect(color, Offset(w * 0.18f, h * 0.08f), Size(w * 0.24f, h * 0.84f), CornerRadius(w * 0.05f))
            drawRoundRect(color, Offset(w * 0.58f, h * 0.08f), Size(w * 0.24f, h * 0.84f), CornerRadius(w * 0.05f))
        } else {
            val p = Path().apply { moveTo(w * 0.26f, h * 0.08f); lineTo(w * 0.92f, h * 0.5f); lineTo(w * 0.26f, h * 0.92f); close() }
            drawPath(p, color)
        }
    }
}

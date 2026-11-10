package com.example.tunebeatchord.ui.chords

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.tunebeatchord.chord.BassPositions
import com.example.tunebeatchord.chord.Chord
import com.example.tunebeatchord.chord.ChordVoicing
import com.example.tunebeatchord.ui.components.NotePaints
import com.example.tunebeatchord.ui.theme.AppTheme

// 版式（dp）：和 iOS 版的指法图一致
private const val GAP_X = 34f
private const val GAP_Y = 31f
private const val ROWS = 5
private const val X0 = 30f
private const val Y0 = 32f
private const val RADIUS = 14f

private fun nativePaint(color: Color, sizePx: Float, bold: Boolean = false) = android.graphics.Paint().apply {
    isAntiAlias = true
    this.color = color.toArgb()
    textSize = sizePx
    textAlign = android.graphics.Paint.Align.CENTER
    typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, if (bold) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
}

/** 吉他、尤克里里的指法图。弦从左到右按定弦的物理顺序排，左手模式下镜像。 */
@Composable
fun ChordDiagram(
    voicing: ChordVoicing,
    chord: Chord,
    leftHanded: Boolean,
    noteName: (Int) -> String,
    description: String,
    modifier: Modifier = Modifier,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val c = AppTheme.colors
    val notePaints = androidx.compose.runtime.remember { NotePaints(context) }
    val n = voicing.stringCount
    val w = X0 * 2 + GAP_X * (n - 1)
    val h = Y0 + GAP_Y * ROWS + 34
    Canvas(modifier.width(w.dp).height(h.dp).semantics { contentDescription = description }) {
        val d = density
        fun x(i: Int) = (X0 + GAP_X * (if (leftHanded) n - 1 - i else i)) * d
        fun rowY(fret: Int) = (Y0 + ((fret - voicing.baseFret) + 0.5f) * GAP_Y) * d
        val left = x(if (leftHanded) n - 1 else 0)
        val right = x(if (leftHanded) 0 else n - 1)

        for (r in 0..ROWS) {
            val y = (Y0 + r * GAP_Y) * d
            if (r == 0 && voicing.showsNut) {
                drawLine(c.text, Offset(left, y), Offset(right, y), strokeWidth = 6 * d, cap = StrokeCap.Round)
            } else {
                drawLine(c.dim, Offset(left, y), Offset(right, y), strokeWidth = 1.5f * d, cap = StrokeCap.Round)
            }
        }
        if (!voicing.showsNut) {
            val lx = if (leftHanded) right + 17 * d else left - 17 * d
            drawContext.canvas.nativeCanvas.drawText("${voicing.baseFret}", lx, (Y0 + GAP_Y / 2) * d + 5 * d, nativePaint(c.sub, 13 * d, bold = true))
        }
        for (i in 0 until n) {
            val width = (1.2f + (n - 1 - i) * 0.25f) * d
            drawLine(c.dim, Offset(x(i), Y0 * d), Offset(x(i), (Y0 + GAP_Y * ROWS) * d), strokeWidth = width)
        }
        voicing.barre?.let { b ->
            val a = x(b.fromString)
            val z = x(b.toString)
            drawRoundRect(
                c.text, topLeft = Offset(minOf(a, z) - RADIUS * d, rowY(b.fret) - RADIUS * d),
                size = Size(kotlin.math.abs(a - z) + RADIUS * 2 * d, RADIUS * 2 * d), cornerRadius = CornerRadius(RADIUS * d),
            )
        }
        for (i in 0 until n) {
            val f = voicing.frets[i]
            val cx = x(i)
            when {
                f < 0 -> {
                    val s = Stroke(width = 2 * d, cap = StrokeCap.Round)
                    drawLine(c.sub, Offset(cx - 6 * d, (Y0 - 22) * d), Offset(cx + 6 * d, (Y0 - 10) * d), strokeWidth = s.width, cap = StrokeCap.Round)
                    drawLine(c.sub, Offset(cx + 6 * d, (Y0 - 22) * d), Offset(cx - 6 * d, (Y0 - 10) * d), strokeWidth = s.width, cap = StrokeCap.Round)
                }
                f == 0 -> drawCircle(c.text, radius = 6.5f * d, center = Offset(cx, (Y0 - 16) * d), style = Stroke(2 * d))
                else -> {
                    val isRoot = voicing.pitches[i]?.pitchClass == chord.root
                    val cy = rowY(f)
                    val barre = voicing.barre
                    val inBarre = barre != null && f == barre.fret && i >= barre.fromString && i <= barre.toString
                    if (!inBarre || isRoot) drawCircle(if (isRoot) c.accent else c.text, radius = RADIUS * d, center = Offset(cx, cy))
                    val numberString = if (barre != null) (if (leftHanded) barre.toString else barre.fromString) else -1
                    val showNumber = !inBarre || isRoot || i == numberString
                    if (showNumber && voicing.fingers[i] > 0) {
                        val onDot = if (isRoot) c.onAccent else if (c.isLight) Color.White else Color(0xFF1A1C21)
                        drawContext.canvas.nativeCanvas.drawText("${voicing.fingers[i]}", cx, cy + 5 * d, nativePaint(onDot, 14 * d, bold = true))
                    }
                }
            }
        }
        // 弦下面的音名，和弦根音用主色
        for (i in 0 until n) {
            val p = voicing.pitches[i] ?: continue
            val isRoot = p.pitchClass == chord.root
            notePaints.draw(
                drawContext.canvas.nativeCanvas, noteName(p.pitchClass), x(i), (Y0 + GAP_Y * ROWS + 24) * d, 14 * d,
                (if (isRoot) c.accent else c.sub).toArgb(), isRoot,
            )
        }
    }
}

/** 贝斯：一个把位框里的根音、三度、五度、八度。 */
@Composable
fun BassDiagram(
    positions: BassPositions,
    leftHanded: Boolean,
    description: String,
    modifier: Modifier = Modifier,
) {
    val c = AppTheme.colors
    val n = positions.stringCount
    val rows = positions.fretCount
    val w = X0 * 2 + GAP_X * (n - 1)
    val h = Y0 + GAP_Y * rows + 20
    Canvas(modifier.width(w.dp).height(h.dp).semantics { contentDescription = description }) {
        val d = density
        fun x(i: Int) = (X0 + GAP_X * (if (leftHanded) n - 1 - i else i)) * d
        fun rowY(fret: Int) = (Y0 + ((fret - positions.firstRow) + 0.5f) * GAP_Y) * d
        val left = minOf(x(0), x(n - 1))
        val right = maxOf(x(0), x(n - 1))
        for (r in 0..rows) {
            val y = (Y0 + r * GAP_Y) * d
            if (r == 0 && positions.showsNut) drawLine(c.text, Offset(left, y), Offset(right, y), strokeWidth = 6 * d, cap = StrokeCap.Round)
            else drawLine(c.dim, Offset(left, y), Offset(right, y), strokeWidth = 1.5f * d, cap = StrokeCap.Round)
        }
        if (!positions.showsNut) {
            drawContext.canvas.nativeCanvas.drawText("${positions.firstRow}", left - 17 * d, (Y0 + GAP_Y / 2) * d + 5 * d, nativePaint(c.sub, 13 * d, bold = true))
        }
        // 弦从上到下：这里弦竖着画，最粗的弦在左边
        for (i in 0 until n) {
            drawLine(c.dim, Offset(x(i), Y0 * d), Offset(x(i), (Y0 + GAP_Y * rows) * d), strokeWidth = (1.2f + (n - 1 - i) * 0.35f) * d)
        }
        for (m in positions.markers) {
            val cx = x(m.string)
            if (m.fret == 0) {
                drawCircle(if (m.role == BassPositions.Role.ROOT) c.accent else c.text, 7 * d, Offset(cx, (Y0 - 14) * d), style = Stroke(2 * d))
                continue
            }
            val cy = rowY(m.fret)
            val fill = when (m.role) {
                BassPositions.Role.ROOT -> c.accent
                BassPositions.Role.OCTAVE -> c.accent.copy(alpha = 0.55f)
                BassPositions.Role.THIRD -> c.text
                BassPositions.Role.FIFTH -> c.sub
            }
            drawCircle(fill, RADIUS * d, Offset(cx, cy))
            val onDot = if (m.role == BassPositions.Role.ROOT) c.onAccent else if (c.isLight) Color.White else Color(0xFF1A1C21)
            drawContext.canvas.nativeCanvas.drawText(m.label, cx, cy + 5 * d, nativePaint(onDot, 13 * d, bold = true))
        }
    }
}

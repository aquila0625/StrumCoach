package com.example.strumcoach.ui.tuner

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.strumcoach.tuner.InstrumentFamily

/** 乐器图标：吉他、贝斯、尤克里里、提琴三兄弟画成线条，“自动”是声波；坐标和 iOS 版（InstrumentIcon.swift）一致，画布 28 × 28。 */
@Composable
fun InstrumentIcon(family: InstrumentFamily, color: Color, size: Dp = 28.dp) {
    Canvas(Modifier.size(size)) {
        val s = this.size.width / 28f
        withTransform({ scale(s, s, pivot = Offset.Zero) }) { draw(family, color) }
    }
}

private fun circle(x: Float, y: Float, r: Float) = Path().apply { addOval(Rect(x - r, y - r, x + r, y + r)) }
private fun ellipse(x: Float, y: Float, rx: Float, ry: Float) = Path().apply { addOval(Rect(x - rx, y - ry, x + rx, y + ry)) }
private fun union(a: Path, b: Path) = Path.combine(PathOperation.Union, a, b)

private fun DrawScope.draw(family: InstrumentFamily, color: Color) {
    val stroke = Stroke(1.9f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val thin = Stroke(1.1f, cap = StrokeCap.Round)
    when (family) {
        InstrumentFamily.CHROMATIC -> {
            // 声波：五根竖条
            val heights = listOf(6f, 12f, 18f, 12f, 6f)
            heights.forEachIndexed { i, h ->
                val x = 5f + i * 4.5f
                drawLine(color, Offset(x, 14 - h / 2), Offset(x, 14 + h / 2), strokeWidth = 2.2f, cap = StrokeCap.Round)
            }
        }
        InstrumentFamily.GUITAR, InstrumentFamily.UKULELE, InstrumentFamily.BASS -> {
            // 斜放，绕中心转 35°
            rotate(35f, pivot = Offset(14f, 14f)) {
                // 琴体：上下两个圆合成葫芦形；尤克里里琴体更小、琴颈更短；贝斯琴颈更长、琴体更窄
                val (upper, lower, neckTop) = when (family) {
                    InstrumentFamily.UKULELE -> Triple(Triple(14f, 17f, 3.7f), Triple(14f, 22.2f, 4.7f), 6f)
                    InstrumentFamily.BASS -> Triple(Triple(14f, 17.5f, 3.2f), Triple(14f, 22.4f, 4.4f), 1.5f)
                    else -> Triple(Triple(14f, 16.2f, 4.1f), Triple(14f, 21.8f, 5.3f), 3f)
                }
                val body = union(circle(upper.first, upper.second, upper.third), circle(lower.first, lower.second, lower.third))
                drawPath(body, color, style = stroke)
                val neckBottom = upper.second - upper.third + 0.6f
                drawLine(color, Offset(14f, neckTop + 1.6f), Offset(14f, neckBottom), strokeWidth = 2.2f, cap = StrokeCap.Round)
                drawRoundRect(color, Offset(12.4f, neckTop - 1.2f), Size(3.2f, 2.8f), CornerRadius(0.8f))
                if (family == InstrumentFamily.BASS) {
                    // 四个弦钮
                    for ((x, y) in listOf(11.4f to neckTop - 0.6f, 11.4f to neckTop + 1.2f, 16.6f to neckTop - 0.6f, 16.6f to neckTop + 1.2f)) {
                        drawCircle(color, 0.55f, Offset(x, y))
                    }
                } else {
                    // 音孔
                    drawCircle(color, if (family == InstrumentFamily.UKULELE) 1.3f else 1.6f, Offset(14f, upper.second + upper.third * 0.45f), style = thin)
                }
                // 琴桥
                val bridgeY = lower.second + lower.third * 0.35f
                drawLine(color, Offset(12f, bridgeY), Offset(16f, bridgeY), strokeWidth = 1.4f, cap = StrokeCap.Round)
            }
        }
        InstrumentFamily.VIOLIN, InstrumentFamily.VIOLA, InstrumentFamily.CELLO -> {
            // 提琴：上下两个椭圆合成带腰的琴体，琴头是涡卷，f 孔两道；大提琴更大、底下有尾柱
            val scale = when (family) { InstrumentFamily.CELLO -> 1.12f; InstrumentFamily.VIOLA -> 1.04f; else -> 0.96f }
            val cy = if (family == InstrumentFamily.CELLO) 15.5f else 16.5f
            fun y(v: Float) = cy + (v - 16.5f) * scale
            val body = union(ellipse(14f, y(13.6f), 4.3f * scale, 3.7f * scale), ellipse(14f, y(20.6f), 5.2f * scale, 4.4f * scale))
            drawPath(body, color, style = stroke)
            val top = y(13.6f) - 3.7f * scale
            drawLine(color, Offset(14f, top + 0.3f), Offset(14f, top - 6f * scale), strokeWidth = 1.9f, cap = StrokeCap.Round)
            drawCircle(color, 1.2f, Offset(14f, top - 6.8f * scale), style = thin)
            // f 孔
            for (x in listOf(11.6f, 16.4f)) {
                val dir = if (x < 14) 1.2f else -1.2f
                val f = Path().apply {
                    moveTo(x, y(15.6f))
                    cubicTo(x + dir, y(17.2f), x - dir, y(18.8f), x, y(20.4f))
                }
                drawPath(f, color, style = thin)
            }
            if (family == InstrumentFamily.CELLO) {
                val bottom = y(20.6f) + 4.4f * scale
                drawLine(color, Offset(14f, bottom), Offset(14f, minOf(27.6f, bottom + 2.4f)), strokeWidth = 1.5f, cap = StrokeCap.Round)
            }
        }
    }
}

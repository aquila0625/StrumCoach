package com.example.strumcoach.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

enum class TabIcon { TRAIN, METRONOME, TUNER, CHORD, ME }

/** 底部标签的线条图标（自己画，不依赖图标库）。 */
@Composable
fun TabIconView(kind: TabIcon, color: Color, size: Dp = 26.dp) {
    Canvas(Modifier.size(size)) {
        val s = this.size.minDimension
        val st = Stroke(width = s * 0.075f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        fun p(x: Float, y: Float) = Offset(x * s, y * s)
        when (kind) {
            TabIcon.TRAIN -> {
                for ((i, h) in listOf(0.3f, 0.55f, 0.8f).withIndex()) {
                    drawRoundRect(color, p(0.14f + i * 0.28f, 0.9f - h * 0.8f), Size(s * 0.18f, h * 0.8f * s), cornerRadius = androidx.compose.ui.geometry.CornerRadius(s * 0.03f))
                }
            }
            TabIcon.METRONOME -> {
                val body = Path().apply {
                    moveTo(s * 0.38f, s * 0.1f); lineTo(s * 0.62f, s * 0.1f); lineTo(s * 0.84f, s * 0.9f); lineTo(s * 0.16f, s * 0.9f); close()
                }
                drawPath(body, color, style = st)
                drawLine(color, p(0.5f, 0.72f), p(0.66f, 0.28f), strokeWidth = st.width, cap = StrokeCap.Round)
            }
            TabIcon.TUNER -> {
                val fork = Path().apply {
                    moveTo(s * 0.3f, s * 0.1f); lineTo(s * 0.3f, s * 0.45f)
                    cubicTo(s * 0.3f, s * 0.62f, s * 0.7f, s * 0.62f, s * 0.7f, s * 0.45f); lineTo(s * 0.7f, s * 0.1f)
                    moveTo(s * 0.5f, s * 0.58f); lineTo(s * 0.5f, s * 0.92f)
                }
                drawPath(fork, color, style = st)
            }
            TabIcon.CHORD -> {
                drawRoundRect(color, p(0.2f, 0.12f), Size(s * 0.6f, s * 0.76f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(s * 0.06f), style = st)
                for (i in 1..2) drawLine(color, p(0.2f + i * 0.2f, 0.12f), p(0.2f + i * 0.2f, 0.88f), strokeWidth = st.width * 0.7f)
                for (i in 1..3) drawLine(color, p(0.2f, 0.12f + i * 0.19f), p(0.8f, 0.12f + i * 0.19f), strokeWidth = st.width * 0.7f)
            }
            TabIcon.ME -> {
                drawCircle(color, s * 0.18f, p(0.5f, 0.3f), style = st)
                val shoulders = Path().apply { moveTo(s * 0.16f, s * 0.9f); cubicTo(s * 0.16f, s * 0.58f, s * 0.84f, s * 0.58f, s * 0.84f, s * 0.9f) }
                drawPath(shoulders, color, style = st)
            }
        }
    }
}

package com.example.tunebeatchord.ui.training

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.chord.StrumCell
import com.example.tunebeatchord.chord.StrumRhythm
import com.example.tunebeatchord.chord.chordName
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.strum.StrumTrainer
import com.example.tunebeatchord.ui.components.noteAnnotated
import com.example.tunebeatchord.ui.theme.AppTheme

/** 训练页顶上的扫弦卡片（iOS 版的 StrumHeroCard）：标题、当前节奏型和速度、一小节的格子（箭头加报数）、节奏型页点、和弦进行、上次和最高成绩、“听一听”和“开始练习”。 */
@Composable
fun StrumHeroCard(trainer: StrumTrainer, settings: Settings, onOpenStrum: (start: Boolean) -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val naming = settings.noteNaming()
    val rhythm = trainer.rhythm
    val previewing = trainer.phase == StrumTrainer.Phase.DEMO
    var clock by remember { mutableLongStateOf(0L) }
    LaunchedEffect(previewing) { while (previewing) androidx.compose.runtime.withFrameNanos { clock = it } }
    val active = if (previewing) trainer.position(clock / 1e9)?.second else null
    val rhythms = StrumRhythm.presets(trainer.instrument.family)
    val shape = RoundedCornerShape(24.dp)

    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(c.accent.copy(alpha = if (c.isLight) 0.16f else 0.22f), c.accent.copy(alpha = if (c.isLight) 0.06f else 0.08f))))
            .border(1.dp, c.accent.copy(alpha = 0.45f), shape).padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(46.dp).clip(RoundedCornerShape(13.dp)).background(c.accentBrush), contentAlignment = Alignment.Center) { StrummingIcon(Color.White) }
            Column(Modifier.weight(1f)) {
                Text(tr("扫弦节奏型"), color = c.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                Text(tr("跟着节奏扫，麦克风帮你打分"), color = c.sub, fontSize = 13.sp, maxLines = 1)
            }
        }
        Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(strings.t(rhythm.title), color = c.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text("${trainer.bpm} BPM", color = c.sub, fontSize = 14.sp)
        }
        // 一小节的格子
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            rhythm.cells.forEachIndexed { i, cell ->
                val on = active == i
                val rest = cell == StrumCell.REST
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.fillMaxWidth().height(58.dp).clip(RoundedCornerShape(9.dp))
                            .background(if (on) c.accent else if (rest) Color.Transparent else c.card2)
                            .then(if (rest) Modifier.border(1.dp, c.dim.copy(alpha = 0.7f), RoundedCornerShape(9.dp)) else Modifier),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (!rest) Text(cell.arrow, color = if (on) c.onAccent else c.text, fontSize = if (rhythm.cells.size > 8) 17.sp else 26.sp, fontWeight = FontWeight.Bold)
                    }
                    Text(rhythm.countLabel(i), color = if (on) c.accent else c.sub, fontSize = 12.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
        // 节奏型页点：点一个切换到那个节奏型
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            rhythms.forEach { r ->
                Box(Modifier.padding(horizontal = 3.dp).size(if (r.id == rhythm.id) 9.dp else 7.dp).clip(CircleShape).background(if (r.id == rhythm.id) c.accent else c.weak).clickable { trainer.select(r) })
            }
        }
        // 和弦进行
        Row(Modifier.fillMaxWidth().padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("和弦进行"), color = c.sub, fontSize = 13.sp, modifier = Modifier.weight(1f))
            Box(Modifier.size(32.dp).clickable { onOpenStrum(false) }, contentAlignment = Alignment.Center) { PencilIcon(c.accent) }
        }
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            trainer.progression.chords.take(8).forEach { pc ->
                Box(Modifier.clip(RoundedCornerShape(9.dp)).background(c.card2).padding(horizontal = 12.dp, vertical = 8.dp)) {
                    Text(noteAnnotated(naming.chordName(pc.chord)), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        }
        // 上次、最高
        val last = trainer.history.last
        if (last != null) {
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ScorePill(strings.t("上次"), strings.t("%lld 分", last.score))
                trainer.history.best(rhythm.id)?.let { ScorePill(strings.t("最高"), strings.t("%lld 分", it)) }
            }
        } else {
            Text(tr("还没练过，先听一听再开始"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp))
        }
        Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.18f))
                    .clickable { if (previewing) trainer.stopDemo() else trainer.startDemo() },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                SpeakerIcon(c.accent)
                Text(if (previewing) tr("停止") else tr("听一听"), color = c.accent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp))
            }
            Row(
                Modifier.weight(1.4f).height(52.dp).clip(RoundedCornerShape(14.dp)).background(c.accentBrush).clickable { trainer.stopAll(); onOpenStrum(true) },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                MicIcon(Color.White)
                Text(tr("开始练习"), color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

@Composable
private fun ScorePill(caption: String, value: String) {
    val c = AppTheme.colors
    Row(Modifier.clip(RoundedCornerShape(50)).background(c.card2).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(caption, color = c.sub, fontSize = 13.sp)
        Text(value, color = c.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun StrummingIcon(color: Color) {
    Canvas(Modifier.size(28.dp)) {
        val s = size.width
        for (i in 0 until 4) {
            val x = s * (0.18f + i * 0.21f)
            drawLine(color, Offset(x, s * 0.2f), Offset(x, s * 0.8f), strokeWidth = s * 0.07f, cap = StrokeCap.Round)
        }
        drawLine(color, Offset(s * 0.08f, s * 0.9f), Offset(s * 0.92f, s * 0.9f), strokeWidth = s * 0.07f, cap = StrokeCap.Round)
    }
}

@Composable
private fun PencilIcon(color: Color) {
    Canvas(Modifier.size(16.dp)) {
        val s = size.width
        drawLine(color, Offset(s * 0.2f, s * 0.8f), Offset(s * 0.8f, s * 0.2f), strokeWidth = s * 0.16f, cap = StrokeCap.Round)
        drawLine(color, Offset(s * 0.12f, s * 0.9f), Offset(s * 0.3f, s * 0.9f), strokeWidth = s * 0.08f, cap = StrokeCap.Round)
    }
}

@Composable
private fun SpeakerIcon(color: Color) {
    Canvas(Modifier.size(20.dp)) {
        val s = size.width
        val p = androidx.compose.ui.graphics.Path().apply {
            moveTo(s * 0.1f, s * 0.38f); lineTo(s * 0.32f, s * 0.38f); lineTo(s * 0.55f, s * 0.15f); lineTo(s * 0.55f, s * 0.85f); lineTo(s * 0.32f, s * 0.62f); lineTo(s * 0.1f, s * 0.62f); close()
        }
        drawPath(p, color)
        drawArc(color, -40f, 80f, false, Offset(s * 0.5f, s * 0.3f), androidx.compose.ui.geometry.Size(s * 0.4f, s * 0.4f), style = Stroke(s * 0.09f, cap = StrokeCap.Round))
    }
}

@Composable
private fun MicIcon(color: Color) {
    Canvas(Modifier.size(20.dp)) {
        val s = size.width
        drawRoundRect(color, Offset(s * 0.35f, s * 0.05f), androidx.compose.ui.geometry.Size(s * 0.3f, s * 0.55f), androidx.compose.ui.geometry.CornerRadius(s * 0.15f))
        drawArc(color, 0f, 180f, false, Offset(s * 0.2f, s * 0.3f), androidx.compose.ui.geometry.Size(s * 0.6f, s * 0.5f), style = Stroke(s * 0.09f, cap = StrokeCap.Round))
        drawLine(color, Offset(s * 0.5f, s * 0.8f), Offset(s * 0.5f, s * 0.95f), strokeWidth = s * 0.09f, cap = StrokeCap.Round)
    }
}

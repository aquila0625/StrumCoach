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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import com.example.tunebeatchord.chord.ChordLibraryState
import com.example.tunebeatchord.chord.ChordPlayer
import com.example.tunebeatchord.strum.RhythmMarks
import com.example.tunebeatchord.ui.chords.CustomRhythmEditor
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
fun StrumHeroCard(trainer: StrumTrainer, settings: Settings, chords: ChordLibraryState, player: ChordPlayer, onOpenStrum: (start: Boolean) -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val naming = settings.noteNaming()
    val rhythm = trainer.rhythm
    val previewing = trainer.phase == StrumTrainer.Phase.DEMO
    var clock by remember { mutableLongStateOf(0L) }
    LaunchedEffect(previewing) { while (previewing) androidx.compose.runtime.withFrameNanos { clock = it } }
    val active = if (previewing) trainer.position(clock / 1e9)?.second else null
    val visible = trainer.visiblePatterns
    val pageCount = visible.size + (if (visible.isEmpty()) 1 else 0) + 1      // 节奏型们（筛选后为空时一页提示）+ 最后一页“自定义…”
    val pager = rememberPagerState { pageCount }
    var editor by remember { mutableStateOf(false) }
    val currentVisible by rememberUpdatedState(visible)
    // 选中的节奏型变了（点格子、保存新的、换筛选）就翻到它那一页
    LaunchedEffect(trainer.rhythm.id, trainer.filter, visible.map { it.id }) {
        val i = visible.indexOfFirst { it.id == trainer.rhythm.id }
        if (i >= 0 && i != pager.currentPage && !pager.isScrollInProgress) pager.scrollToPage(i)
    }
    // 滑到哪页就选哪个
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { p -> currentVisible.getOrNull(p)?.let { if (it.id != trainer.rhythm.id) trainer.select(it) } }
    }
    // 当前选中的自定义节奏型被删掉了：回到第一个
    LaunchedEffect(trainer.patterns) { if (trainer.rhythm !in trainer.patterns) trainer.select(trainer.patterns[0]) }
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
                Text(tr("跟着节奏扫，麦克风帮你打分"), color = c.sub, fontSize = 13.sp, maxLines = 2)
            }
            FilterMenu(trainer, enabled = !previewing)
        }
        HorizontalPager(pager, Modifier.fillMaxWidth().padding(top = 14.dp), userScrollEnabled = !previewing, verticalAlignment = Alignment.Top) { page ->
            val r = visible.getOrNull(page)
            when {
                r != null -> RhythmPage(trainer, r, active = if (r.id == rhythm.id) active else null, naming = naming)
                page == pageCount - 1 -> CustomPage { editor = true }
                else -> EmptyPage(trainer)
            }
        }
        // 页点：当前页拉长，最后一个是“＋”
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            for (i in 0 until pageCount) {
                val on = pager.currentPage == i
                if (i == pageCount - 1) Text("+", color = if (on) c.accent else c.dim, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 4.dp))
                else Box(Modifier.padding(horizontal = 3.dp).height(6.dp).width(if (on) 16.dp else 6.dp).clip(CircleShape).background(if (on) c.accent else c.dim.copy(alpha = 0.5f)))
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
    if (editor) CustomRhythmEditor(
        chords, player, editing = null, family = trainer.instrument.family, selectsOnSave = false,
        onSave = { saved -> saved.rhythm?.let { trainer.select(it) } },
        onClose = { editor = false },
    )
}

/** 一页：节奏型名字（自定义的带小标签）、速度、星标和已掌握按钮，下面是一小节的格子。 */
@Composable
private fun RhythmPage(trainer: StrumTrainer, r: StrumRhythm, active: Int?, naming: com.example.tunebeatchord.tuner.NoteNaming) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
        Row(Modifier.height(36.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val name = if (r.isCustom) r.title.ifEmpty { r.arrows } else strings.t(r.title)
            Text(name, color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            if (r.isCustom && r.title.isNotEmpty() && name != strings.t("自定义")) {
                Text(tr("自定义"), color = c.sub, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.card2).padding(horizontal = 5.dp, vertical = 1.dp))
            }
            Box(Modifier.weight(1f))
            Text("${trainer.bpm} BPM", color = c.sub, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            MarkButtons(trainer, r)
        }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            r.cells.forEachIndexed { i, cell ->
                val on = active == i
                val rest = cell == StrumCell.REST
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.fillMaxWidth().height(58.dp).clip(RoundedCornerShape(9.dp))
                            .background(if (on) c.accent else if (rest) Color.Transparent else c.card2)
                            .then(if (rest) Modifier.border(1.dp, c.dim.copy(alpha = 0.7f), RoundedCornerShape(9.dp)) else Modifier),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (!rest) Text(cell.arrow, color = if (on) c.onAccent else c.text, fontSize = if (r.cells.size > 8) 17.sp else 26.sp, fontWeight = FontWeight.Bold)
                    }
                    Text(r.countLabel(i), color = if (on) c.accent else c.sub, fontSize = 12.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}

/** 星标（收藏）和勾（已掌握）两个小圆按钮。 */
@Composable
internal fun MarkButtons(trainer: StrumTrainer, r: StrumRhythm) {
    val c = AppTheme.colors
    val favorite = trainer.isFavorite(r)
    val mastered = trainer.isMastered(r)
    val label1 = if (favorite) tr("取消收藏") else tr("收藏")
    val label2 = if (mastered) tr("取消已掌握") else tr("标记为已掌握")
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(
            Modifier.size(32.dp).clip(CircleShape).background(c.card2).clickable { trainer.setFavorite(!favorite, r) }
                .androidx_semantics(label1),
            contentAlignment = Alignment.Center,
        ) { Text(if (favorite) "★" else "☆", color = if (favorite) Color(0xFFFAB81A) else c.sub, fontSize = 17.sp) }
        Box(
            Modifier.size(32.dp).clip(CircleShape).background(c.card2).clickable { trainer.setMastered(!mastered, r) }
                .androidx_semantics(label2),
            contentAlignment = Alignment.Center,
        ) { Text(if (mastered) "✓" else "✓", color = if (mastered) c.green else c.dim, fontSize = 16.sp, fontWeight = FontWeight.Bold) }
    }
}

private fun Modifier.androidx_semantics(label: String): Modifier =
    this.then(Modifier.semantics { contentDescription = label })

/** 筛选：全部 / 收藏 / 未掌握。 */
@Composable
internal fun FilterMenu(trainer: StrumTrainer, enabled: Boolean) {
    val c = AppTheme.colors
    var open by remember { mutableStateOf(false) }
    val title = { f: RhythmMarks.Filter -> when (f) { RhythmMarks.Filter.ALL -> "全部"; RhythmMarks.Filter.FAVORITES -> "收藏"; RhythmMarks.Filter.LEARNING -> "未掌握" } }
    Box {
        Row(
            Modifier.height(26.dp).clip(RoundedCornerShape(50)).background(c.card2.copy(alpha = 0.8f)).clickable(enabled = enabled) { open = true }.padding(horizontal = 9.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text("≡", color = if (trainer.filter == RhythmMarks.Filter.ALL) c.sub else c.accent, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Text(tr(title(trainer.filter)), color = if (trainer.filter == RhythmMarks.Filter.ALL) c.sub else c.accent, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
        DropdownMenu(open, { open = false }, containerColor = c.sheet) {
            RhythmMarks.Filter.entries.forEach { f ->
                DropdownMenuItem(
                    text = { Text((if (f == trainer.filter) "✓  " else "     ") + tr(title(f)), color = c.text) },
                    onClick = { trainer.updateFilter(f); open = false },
                )
            }
        }
    }
}

/** 筛选后一个都没有（比如还没收藏）。 */
@Composable
private fun EmptyPage(trainer: StrumTrainer) {
    val c = AppTheme.colors
    Column(Modifier.fillMaxWidth().height(128.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(if (trainer.filter == RhythmMarks.Filter.FAVORITES) "☆" else "✓", color = c.accent, fontSize = 24.sp)
        Text(
            if (trainer.filter == RhythmMarks.Filter.FAVORITES) tr("还没有收藏的节奏型：点星标收藏。") else tr("这件乐器的节奏型都已掌握。"),
            color = c.sub, fontSize = 13.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(top = 6.dp),
        )
        Text(tr("显示全部"), color = c.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { trainer.updateFilter(RhythmMarks.Filter.ALL) }.padding(top = 8.dp))
    }
}

/** 最后一页：新建自定义节奏型。 */
@Composable
private fun CustomPage(onClick: () -> Unit) {
    val c = AppTheme.colors
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).height(120.dp).clip(shape).border(1.2.dp, c.accent.copy(alpha = 0.5f), shape).clickable(onClick = onClick).padding(horizontal = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Text("＋  " + tr("自定义…"), color = c.accent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text(tr("用 D（下扫）U（上扫）X（闷音）·（空拍）写出自己的节奏型，和弦库里也能用"), color = c.sub, fontSize = 12.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
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

package com.example.tunebeatchord.ui.chords

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.chord.ChordLibrary
import com.example.tunebeatchord.chord.ChordLibraryState
import com.example.tunebeatchord.chord.ChordPlayer
import com.example.tunebeatchord.chord.ChordRoot
import com.example.tunebeatchord.chord.ChordType
import com.example.tunebeatchord.chord.StrumCell
import com.example.tunebeatchord.chord.chordName
import com.example.tunebeatchord.chord.rootName
import com.example.tunebeatchord.chord.toneName
import com.example.tunebeatchord.chord.toneNames
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.tuner.NoteNaming
import com.example.tunebeatchord.ui.components.CardBox
import com.example.tunebeatchord.ui.components.ChevronDown
import com.example.tunebeatchord.ui.components.chordAnnotated
import com.example.tunebeatchord.ui.components.noteAnnotated
import com.example.tunebeatchord.ui.metronome.AppSheet
import com.example.tunebeatchord.ui.theme.AppTheme

/** 和弦库，布局和 iOS 版（ChordLibraryView）一致：标题和星标菜单、乐器切换、和弦卡片（和弦名、播放、节奏型与速度、格子条、可滑动的指法图）、根音和类型。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChordLibraryScreen(state: ChordLibraryState, settings: Settings, player: ChordPlayer, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val naming = settings.noteNaming()
    val strings = LocalStrings.current

    // 当前格高亮：播放时每帧按时钟更新
    var clock by remember { mutableLongStateOf(0L) }
    LaunchedEffect(player.isPlaying) { while (player.isPlaying) androidx.compose.runtime.withFrameNanos { clock = it } }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { player.stop() } }

    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        TopBar(state, settings, naming)
        InstrumentControl(state)
        Box(Modifier.padding(horizontal = 20.dp)) {
            CardBox(Modifier.fillMaxWidth(), radius = 24.dp) {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 12.dp)) {
                    // 和弦名、组成音、播放键
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(
                                chordAnnotated(naming.rootName(state.chord), state.chord.type.symbol, 34.sp, 22.sp),
                                color = c.text, fontWeight = FontWeight.Bold,
                            )
                            Text(noteAnnotated(strings.t("组成音") + " " + naming.toneNames(state.chord).joinToString(" · ")), color = c.sub, fontSize = 13.sp)
                        }
                        Box(
                            Modifier.size(48.dp).clip(CircleShape).background(c.accent).clickable { player.toggle() }
                                .semantics { contentDescription = if (player.isPlaying) strings.t("停止") else strings.t("试听") },
                            contentAlignment = Alignment.Center,
                        ) { PlayStopIcon(player.isPlaying, c.onAccent) }
                    }
                    PlayModeRow(state, player, clock / 1e9)
                    Box(Modifier.fillMaxWidth().padding(top = 4.dp), contentAlignment = Alignment.Center) { DiagramGallery(state, settings, naming) }
                    if (state.isBass) BassLegend() else VoicingPager(state)
                }
            }
        }
        SectionLabel(tr("根音"), Modifier.padding(top = 14.dp))
        RootGrid(state, naming)
        SectionLabel(tr("类型"), Modifier.padding(top = 14.dp))
        TypeGrid(state, naming)
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier) {
    Text(text, color = AppTheme.colors.sub, fontSize = 13.sp, modifier = modifier.padding(horizontal = 20.dp).padding(bottom = 8.dp))
}

// 顶栏：标题 + 星标菜单（收藏当前按法 / 左手模式 / 已收藏）-------------------------

@Composable
private fun TopBar(state: ChordLibraryState, settings: Settings, naming: NoteNaming) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(tr("和弦库"), color = c.text, fontSize = 34.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        Box {
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(c.card).clickable { menu = true }.semantics { contentDescription = strings.t("已收藏") },
                contentAlignment = Alignment.Center,
            ) { StarIcon(filled = state.isFavorite, size = 20.dp) }
            DropdownMenu(menu, { menu = false }, containerColor = c.sheet) {
                DropdownMenuItem(
                    text = { Text(if (state.isFavorite) strings.t("取消收藏") else strings.t("收藏当前按法"), color = c.text) },
                    onClick = { state.toggleFavorite(); menu = false },
                )
                Row(Modifier.width(260.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(strings.t("左手模式"), color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    Switch(settings.leftHanded, { settings.updateLeftHanded(it) })
                }
                Text(strings.t("已收藏"), color = c.sub, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                val items = state.favorites.items
                if (items.isEmpty()) Text(strings.t("还没有收藏"), color = c.sub, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                items.forEach { f ->
                    val inst = ChordLibrary.instruments.firstOrNull { it.id == f.instrumentID }?.let { strings.t(it.name) } ?: f.instrumentID
                    val name = f.chord?.let { naming.chordName(it) } ?: "?"
                    DropdownMenuItem(
                        text = { Text(noteAnnotated(if (f.instrumentID == "bass") "$name · $inst" else "$name · $inst · ${f.voicingIndex + 1}"), color = c.text) },
                        onClick = { state.goTo(f); menu = false },
                    )
                }
            }
        }
    }
}

/** 乐器：卡片底、圆角 14 的分段，选中的是主色圆角 11（和 iOS 版的 instrumentControl 一致）。 */
@Composable
private fun InstrumentControl(state: ChordLibraryState) {
    val c = AppTheme.colors
    Box(Modifier.padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.card).padding(3.dp)) {
            ChordLibrary.instruments.forEach { inst ->
                val on = inst.id == state.instrument.id
                Box(
                    Modifier.weight(1f).height(38.dp).clip(RoundedCornerShape(11.dp)).background(if (on) c.accent else androidx.compose.ui.graphics.Color.Transparent)
                        .clickable { state.select(inst) },
                    contentAlignment = Alignment.Center,
                ) { Text(tr(inst.name), color = if (on) c.onAccent else c.sub, fontSize = 16.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium) }
            }
        }
    }
}

// 试听方式：节奏型按钮、速度、格子条 ------------------------------------------

@Composable
internal fun StepCircle(symbol: String, enabled: Boolean, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(Modifier.size(36.dp).clip(CircleShape).background(c.card2).clickable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Text(symbol, color = if (enabled) c.text else c.dim, fontSize = 20.sp)
    }
}

/** 一小节的格子条：箭头是这一格的扫法，空拍是虚线框；播放时走到的那一格变主色。 */
@Composable
internal fun CellStrip(cells: List<StrumCell>, cellsPerBeat: Int, active: Int?) {
    val c = AppTheme.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(if (cells.size > 8) 3.dp else 4.dp)) {
        cells.forEachIndexed { i, cell ->
            val on = active == i
            val rest = cell == StrumCell.REST
            Box(
                Modifier.weight(1f).height(30.dp).clip(RoundedCornerShape(7.dp))
                    .background(if (on) c.accent else if (rest) androidx.compose.ui.graphics.Color.Transparent else c.card2)
                    .then(
                        if (rest) Modifier.drawBehindDashed(c.dim) else Modifier,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                if (!rest) Text(cell.arrow, color = if (on) c.onAccent else c.text, fontSize = if (cells.size > 8) 13.sp else 16.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

internal fun Modifier.drawBehindDashed(color: androidx.compose.ui.graphics.Color): Modifier = this.then(
    Modifier.border(1.dp, color.copy(alpha = 0.7f), RoundedCornerShape(7.dp)),
)

// 指法图：可左右滑动的画廊 + 页码 ------------------------------------------------

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DiagramGallery(state: ChordLibraryState, settings: Settings, naming: NoteNaming) {
    val strings = LocalStrings.current
    val chord = state.chord
    val name = naming.chordName(chord)
    val voicings = state.voicings
    val bass = state.bassPositions
    if (voicings.isNotEmpty()) {
        val pager = rememberPagerState(initialPage = state.voicingIndex.coerceIn(0, voicings.size - 1)) { voicings.size }
        // 滑动 → 选中；按钮或收藏跳转 → 翻页
        LaunchedEffect(pager.settledPage) { if (pager.settledPage != state.voicingIndex) state.selectVoicing(pager.settledPage) }
        LaunchedEffect(state.voicingIndex, voicings.size) { if (pager.currentPage != state.voicingIndex && state.voicingIndex < voicings.size) pager.animateScrollToPage(state.voicingIndex) }
        HorizontalPager(pager, Modifier.fillMaxWidth(), key = { "${state.instrument.id}-${state.tuning.id}-${chord.id}-$it" }) { page ->
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                ChordDiagram(
                    voicings[page], chord, settings.leftHanded, noteName = { pc -> naming.toneName(pc, chord) },
                    description = strings.t("%@ 指法", name) + "，" + voicings[page].shorthand,
                )
            }
        }
    } else if (bass != null) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            BassDiagram(bass, settings.leftHanded, strings.t("%@ 贝斯和弦音位置", name))
        }
    }
}

@Composable
private fun BassLegend() {
    val c = AppTheme.colors
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
        listOf("根音" to "R", "三度" to "3", "五度" to "5", "八度" to "8").forEach { (key, mark) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(mark, color = c.accent, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Text(tr(key), color = c.sub, fontSize = 12.sp)
            }
        }
    }
    Text(tr("一个把位里的和弦音"), color = c.dim, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
}

@Composable
private fun VoicingPager(state: ChordLibraryState) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val n = state.voicingCount
    val label = state.voicing?.let { v ->
        when {
            v.isOpenPosition -> strings.t("开放把位")
            v.barre != null -> strings.t("横按 · %lld 品", v.minFret)
            else -> strings.t("%lld 品把位", v.minFret)
        }
    } ?: ""
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        ArrowButton(left = true, enabled = state.voicingIndex > 0, description = tr("上一个把位")) { state.previousVoicing() }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            if (n > 1) {
                Text("$label · ${state.voicingIndex + 1} / $n", color = c.sub, fontSize = 14.sp)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    repeat(n) { i -> Box(Modifier.size(7.dp).clip(CircleShape).background(if (i == state.voicingIndex) c.accent else c.weak)) }
                }
            }
        }
        ArrowButton(left = false, enabled = state.voicingIndex < n - 1, description = tr("下一个把位")) { state.nextVoicing() }
    }
}

@Composable
private fun ArrowButton(left: Boolean, enabled: Boolean, description: String, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(
        Modifier.size(44.dp).clip(CircleShape).clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(14.dp, 20.dp)) {
            val p = Path().apply {
                if (left) { moveTo(size.width, 0f); lineTo(0f, size.height / 2); lineTo(size.width, size.height) }
                else { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height) }
            }
            drawPath(p, if (enabled) c.sub else c.dim.copy(alpha = 0.4f), style = Stroke(2.5f * density, cap = StrokeCap.Round))
        }
    }
}

// 根音、类型 ---------------------------------------------------------------

@Composable
private fun RootGrid(state: ChordLibraryState, naming: NoteNaming) {
    val c = AppTheme.colors
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ChordRoot.all.chunked(6).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { pc ->
                    val on = state.root == pc
                    Box(
                        Modifier.weight(1f).height(46.dp).clip(RoundedCornerShape(50)).background(if (on) c.accent else c.card2).clickable { state.selectRoot(pc) },
                        contentAlignment = Alignment.Center,
                    ) { Text(noteAnnotated(naming.rootName(pc)), color = if (on) c.onAccent else c.text, fontSize = 16.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, maxLines = 1, softWrap = false) }
                }
            }
        }
    }
}

@Composable
private fun TypeGrid(state: ChordLibraryState, naming: NoteNaming) {
    val c = AppTheme.colors
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ChordType.builtins.chunked(5).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { t ->
                    val on = state.type.id == t.id
                    Box(
                        Modifier.weight(1f).height(46.dp).clip(RoundedCornerShape(50)).background(if (on) c.accent else c.card2).clickable { state.selectType(t) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(noteAnnotated(naming.chordName(state.root, t)), color = if (on) c.onAccent else c.text, fontSize = 13.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, maxLines = 1, softWrap = false)
                    }
                }
            }
        }
    }
}

// 小图标 -------------------------------------------------------------------

@Composable
private fun PlayStopIcon(playing: Boolean, color: androidx.compose.ui.graphics.Color) {
    Canvas(Modifier.size(20.dp)) {
        if (playing) drawRoundRect(color, Offset(size.width * 0.15f, size.height * 0.15f), androidx.compose.ui.geometry.Size(size.width * 0.7f, size.height * 0.7f), androidx.compose.ui.geometry.CornerRadius(3f))
        else drawPath(Path().apply { moveTo(size.width * 0.22f, 0f); lineTo(size.width, size.height / 2); lineTo(size.width * 0.22f, size.height); close() }, color)
    }
}

@Composable
internal fun ListIcon(color: androidx.compose.ui.graphics.Color) {
    Canvas(Modifier.size(18.dp)) {
        for (i in 0 until 3) {
            val y = size.height * (0.2f + i * 0.3f)
            drawCircle(color, size.width * 0.06f, Offset(size.width * 0.1f, y))
            drawLine(color, Offset(size.width * 0.3f, y), Offset(size.width * 0.92f, y), strokeWidth = size.width * 0.09f, cap = StrokeCap.Round)
        }
    }
}

@Composable
fun StarIcon(filled: Boolean, size: Dp) {
    val c = AppTheme.colors
    Canvas(Modifier.size(size)) {
        val r = this.size.minDimension / 2
        val center = Offset(this.size.width / 2, this.size.height / 2)
        val path = Path()
        for (i in 0 until 10) {
            val rad = if (i % 2 == 0) r else r * 0.45f
            val a = Math.toRadians((-90 + i * 36).toDouble())
            val pt = Offset(center.x + (rad * Math.cos(a)).toFloat(), center.y + (rad * Math.sin(a)).toFloat())
            if (i == 0) path.moveTo(pt.x, pt.y) else path.lineTo(pt.x, pt.y)
        }
        path.close()
        if (filled) drawPath(path, c.accent) else drawPath(path, c.text, style = Stroke(2f * density, cap = StrokeCap.Round))
    }
}

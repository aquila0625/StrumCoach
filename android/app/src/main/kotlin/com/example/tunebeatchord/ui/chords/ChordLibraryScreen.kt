package com.example.tunebeatchord.ui.chords

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.chord.ChordLibrary
import com.example.tunebeatchord.chord.ChordLibraryState
import com.example.tunebeatchord.chord.ChordRoot
import com.example.tunebeatchord.chord.ChordType
import com.example.tunebeatchord.chord.chordName
import com.example.tunebeatchord.chord.rootName
import com.example.tunebeatchord.chord.toneName
import com.example.tunebeatchord.chord.toneNames
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.tuner.NoteNaming
import com.example.tunebeatchord.ui.components.Card
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.ScreenTitle
import com.example.tunebeatchord.ui.components.Section
import com.example.tunebeatchord.ui.components.Segmented
import com.example.tunebeatchord.ui.components.chordAnnotated
import com.example.tunebeatchord.ui.components.noteAnnotated
import com.example.tunebeatchord.ui.theme.AppTheme

/** 和弦库：选乐器、根音、类型，看指法图，翻把位，收藏。 */
@Composable
fun ChordLibraryScreen(
    state: ChordLibraryState,
    settings: Settings,
    onPlay: ((ChordLibraryState) -> Unit)? = null,
    playing: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val naming = settings.noteNaming()
    val instruments = ChordLibrary.instruments
    var showFavorites by remember { mutableStateOf(false) }

    Column(modifier.verticalScroll(rememberScrollState())) {
        ScreenTitle(tr("和弦库")) {
            Box(
                Modifier.size(44.dp).clip(CircleShape).background(c.card).clickable { showFavorites = !showFavorites },
                contentAlignment = Alignment.Center,
            ) {
                StarIcon(filled = showFavorites, size = 22.dp)
            }
        }
        Box(Modifier.padding(horizontal = 20.dp)) {
            Segmented(
                items = instruments.map { tr(it.name) },
                selectedIndex = instruments.indexOfFirst { it.id == state.instrument.id }.coerceAtLeast(0),
                onSelect = { state.select(instruments[it]) },
            )
        }
        if (showFavorites) {
            FavoritesList(state, naming) { showFavorites = false }
        } else {
            Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                Card(Modifier.fillMaxWidth()) {
                    Column {
                        ChordHeader(state, naming, onPlay, playing)
                        Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
                            Diagram(state, settings, naming)
                        }
                        VoicingPager(state)
                    }
                }
            }
        }
        Section(tr("根音")) {
            RootGrid(state, naming)
        }
        Section(tr("类型")) {
            TypeGrid(state, naming)
        }
        Box(Modifier.height(24.dp))
    }
}

@Composable
private fun ChordHeader(state: ChordLibraryState, naming: NoteNaming, onPlay: ((ChordLibraryState) -> Unit)?, playing: Boolean) {
    val c = AppTheme.colors
    val favLabel = if (state.isFavorite) tr("取消收藏") else tr("收藏当前按法")
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(
                chordAnnotated(naming.rootName(state.chord), state.chord.type.symbol, 40.sp, 28.sp),
                color = c.text, fontWeight = FontWeight.Bold,
            )
            Text(
                noteAnnotated(tr("组成音") + " " + naming.toneNames(state.chord).joinToString(" · ")),
                color = c.sub, fontSize = 14.sp,
            )
        }
        Box(
            Modifier.size(44.dp).clip(CircleShape).clickable { state.toggleFavorite() }
                .semantics { contentDescription = favLabel },
            contentAlignment = Alignment.Center,
        ) { StarIcon(filled = state.isFavorite, size = 22.dp) }
        Box(
            Modifier.size(52.dp).clip(CircleShape).background(c.accentBrush)
                .clickable(enabled = onPlay != null) { onPlay?.invoke(state) },
            contentAlignment = Alignment.Center,
        ) {
            if (playing) {
                Box(Modifier.size(16.dp).background(c.onAccent, androidx.compose.foundation.shape.RoundedCornerShape(3.dp)))
            } else {
                Canvas(Modifier.size(22.dp)) {
                    val p = Path().apply {
                        moveTo(size.width * 0.2f, 0f); lineTo(size.width, size.height / 2); lineTo(size.width * 0.2f, size.height); close()
                    }
                    drawPath(p, c.onAccent)
                }
            }
        }
    }
}

@Composable
private fun Diagram(state: ChordLibraryState, settings: Settings, naming: NoteNaming) {
    val strings = LocalStrings.current
    val chord = state.chord
    val name = naming.chordName(chord)
    val voicing = state.voicing
    val bass = state.bassPositions
    when {
        voicing != null -> ChordDiagram(
            voicing, chord, settings.leftHanded,
            noteName = { pc -> naming.toneName(pc, chord) },
            description = strings.t("%@ 指法", name) + "，" + voicing.shorthand,
        )
        bass != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(tr("一个把位里的和弦音"), color = AppTheme.colors.sub, fontSize = 13.sp, modifier = Modifier.padding(bottom = 6.dp))
            BassDiagram(bass, settings.leftHanded, strings.t("%@ 贝斯和弦音位置", name))
        }
    }
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
                    repeat(n) { i ->
                        Box(Modifier.size(7.dp).clip(CircleShape).background(if (i == state.voicingIndex) c.accent else c.weak))
                    }
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
        Modifier.size(44.dp).clip(CircleShape).clickable(enabled = enabled, onClick = onClick)
            .androidSemantics(description),
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

private fun Modifier.androidSemantics(description: String): Modifier =
    this.then(Modifier.semantics { contentDescription = description })

@Composable
private fun RootGrid(state: ChordLibraryState, naming: NoteNaming) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ChordRoot.all.chunked(6).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { pc ->
                    Chip(naming.rootName(pc), state.root == pc, { state.selectRoot(pc) }, Modifier.weight(1f), height = 46.dp)
                }
            }
        }
    }
}

@Composable
private fun TypeGrid(state: ChordLibraryState, naming: NoteNaming) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ChordType.builtins.chunked(5).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { t ->
                    Chip(naming.chordName(state.root, t), state.type.id == t.id, { state.selectType(t) }, Modifier.weight(1f), height = 46.dp, fontSize = 13, horizontalPadding = 2.dp)
                }
            }
        }
    }
}

@Composable
private fun FavoritesList(state: ChordLibraryState, naming: NoteNaming, onClose: () -> Unit) {
    val c = AppTheme.colors
    Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
        Card(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(tr("已收藏"), color = c.text, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                val items = state.favorites.items
                if (items.isEmpty()) {
                    Text(tr("还没有收藏"), color = c.sub, fontSize = 15.sp)
                }
                items.forEach { f ->
                    val chord = f.chord ?: return@forEach
                    val inst = ChordLibrary.instruments.firstOrNull { it.id == f.instrumentID }
                    Row(
                        Modifier.fillMaxWidth().clip(androidx.compose.foundation.shape.RoundedCornerShape(14.dp)).background(c.card2)
                            .clickable { state.goTo(f); onClose() }.padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(naming.chordName(chord), color = c.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        Text(inst?.let { tr(it.name) } ?: "", color = c.sub, fontSize = 14.sp)
                        Box(Modifier.padding(start = 12.dp).size(32.dp).clickable { state.removeFavorite(f) }, contentAlignment = Alignment.Center) {
                            StarIcon(filled = true, size = 20.dp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun StarIcon(filled: Boolean, size: androidx.compose.ui.unit.Dp) {
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

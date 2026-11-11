package com.example.strumcoach.ui.chords

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.strumcoach.chord.ArpeggioInput
import com.example.strumcoach.chord.ChordLibraryState
import com.example.strumcoach.chord.ChordPlayer
import com.example.strumcoach.chord.CustomArpeggio
import com.example.strumcoach.chord.CustomStrumRhythm
import com.example.strumcoach.chord.StrumInput
import com.example.strumcoach.i18n.LocalStrings
import com.example.strumcoach.i18n.tr
import com.example.strumcoach.ui.components.CardBox
import com.example.strumcoach.ui.metronome.AppSheet
import com.example.strumcoach.ui.theme.AppTheme

/** 正在编辑的自定义内容；item 为 null 是新建。 */
private sealed interface EditorTarget {
    data class Arpeggio(val item: CustomArpeggio?) : EditorTarget
    data class Rhythm(val item: CustomStrumRhythm?) : EditorTarget
}

/**
 * 和弦卡片里的“弹奏方式”一行（iOS 版的 playModeRow）：扫弦 / 分解的切换、列表按钮、当前指法或节奏型的名字、速度；
 * 扫弦时下面一行是一小节的格子条。贝斯没有扫弦，只有分解。
 */
@Composable
fun PlayModeRow(state: ChordLibraryState, player: ChordPlayer, nowSeconds: Double) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var picker by remember { mutableStateOf(false) }
    var tempoMenu by remember { mutableStateOf(false) }
    var editor by remember { mutableStateOf<EditorTarget?>(null) }
    val arpeggio = state.effectivePlayMode == ChordLibraryState.PlayMode.ARPEGGIO
    val rhythm = state.strumRhythm
    val caption = if (arpeggio) (state.arpeggioPattern?.digits ?: "") else (if (rhythm.isCustom) rhythm.displayName() else strings.t(rhythm.title))
    // 名字比较长时挪到第二行，和 iOS 窄屏时的排法一样
    val captionBelow = caption.length > 8

    @Composable
    fun Caption(modifier: Modifier) = Text(
        caption, color = c.sub, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1,
        fontFamily = if (arpeggio) FontFamily.Monospace else FontFamily.Default, modifier = modifier,
    )

    Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (state.supportsStrum) ModeSwitch(arpeggio) { state.select(if (it) ChordLibraryState.PlayMode.ARPEGGIO else ChordLibraryState.PlayMode.STRUM) }
            Box(
                Modifier.size(32.dp).clip(RoundedCornerShape(16.dp)).background(c.card2).clickable { picker = true }
                    .semantics { contentDescription = strings.t(if (arpeggio) "分解指法" else "扫弦节奏型") },
                contentAlignment = Alignment.Center,
            ) { ListIcon(c.text) }
            if (!captionBelow) Caption(Modifier.weight(1f)) else Box(Modifier.weight(1f))
            Box {
                Row(
                    Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).background(c.card2).clickable { tempoMenu = true }.padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("♩", color = c.sub, fontSize = 14.sp)
                    Text("${player.effectiveBpm.toInt()}", color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
                DropdownMenu(tempoMenu, { tempoMenu = false }, containerColor = c.sheet) {
                    Row(Modifier.width(260.dp).padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        StepCircle("−", !state.followsMetronome) { state.updateTempo(state.tempo - 5) }
                        Text(strings.t("速度 %lld BPM", player.effectiveBpm.toInt()), color = c.text, fontSize = 15.sp, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                        StepCircle("+", !state.followsMetronome) { state.updateTempo(state.tempo + 5) }
                    }
                    Row(Modifier.width(260.dp).padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(strings.t("跟随节拍器"), color = c.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        Switch(state.followsMetronome, { state.updateFollowsMetronome(it) })
                    }
                }
            }
        }
        if (captionBelow) Caption(Modifier.fillMaxWidth())
        if (!arpeggio) CellStrip(rhythm.cells, rhythm.cellsPerBeat, player.activeCell(nowSeconds))
    }

    if (picker) {
        if (arpeggio) ArpeggioPicker(state, onClose = { picker = false }, onNew = { picker = false; editor = EditorTarget.Arpeggio(null) },
            onEdit = { picker = false; editor = EditorTarget.Arpeggio(it) })
        else RhythmPicker(state, onClose = { picker = false }, onNew = { picker = false; editor = EditorTarget.Rhythm(null) },
            onEdit = { picker = false; editor = EditorTarget.Rhythm(it) })
    }
    when (val e = editor) {
        is EditorTarget.Arpeggio -> CustomArpeggioEditor(state, player, e.item) { editor = null }
        is EditorTarget.Rhythm -> CustomRhythmEditor(state, player, e.item) { editor = null }
        null -> {}
    }
}

private fun com.example.strumcoach.chord.StrumRhythm.displayName() = title.ifEmpty { arrows }

/** 扫弦 / 分解 的胶囊切换（iOS 的 modeSwitch）。 */
@Composable
private fun ModeSwitch(arpeggio: Boolean, onChange: (Boolean) -> Unit) {
    val c = AppTheme.colors
    val label = tr("弹奏方式")
    Row(Modifier.clip(RoundedCornerShape(50)).background(c.card2).padding(2.dp).semantics { contentDescription = label }) {
        listOf(false to tr("扫弦"), true to tr("分解")).forEach { (isArp, label) ->
            val on = isArp == arpeggio
            Box(
                Modifier.height(28.dp).widthIn(min = 52.dp).clip(RoundedCornerShape(50)).background(if (on) c.accent else androidx.compose.ui.graphics.Color.Transparent)
                    .clickable { onChange(isArp) }.padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) { Text(label, color = if (on) c.onAccent else c.sub, fontSize = 13.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, maxLines = 1) }
        }
    }
}

// 选择面板 ------------------------------------------------------------------

@Composable
private fun PickerRowItem(selected: Boolean, isCustom: Boolean, onSelect: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).heightIn(min = 52.dp).clickable(onClick = onSelect).padding(start = 16.dp, end = if (isCustom) 4.dp else 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { content() }
            if (selected) Text("✓", color = c.accent, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
        if (isCustom) Box {
            Box(Modifier.size(44.dp).clickable { menu = true }, contentAlignment = Alignment.Center) { Text("⋯", color = c.sub, fontSize = 22.sp, fontWeight = FontWeight.Bold) }
            DropdownMenu(menu, { menu = false }, containerColor = c.sheet) {
                DropdownMenuItem(text = { Text(tr("编辑"), color = c.text) }, onClick = { menu = false; onEdit() })
                DropdownMenuItem(text = { Text(tr("删除"), color = androidx.compose.ui.graphics.Color(0xFFE5484D)) }, onClick = { menu = false; onDelete() })
            }
        }
    }
}

@Composable
private fun NewRow(canAdd: Boolean, onNew: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    if (canAdd) Row(Modifier.fillMaxWidth().height(52.dp).clickable(onClick = onNew).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("＋", color = c.accent, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Text(tr("自定义…"), color = c.accent, fontSize = 16.sp, fontWeight = FontWeight.Medium)
    } else Text(strings.t("每种乐器最多保存 %lld 个", 10), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(16.dp))
}

@Composable
private fun ArpeggioPicker(state: ChordLibraryState, onClose: () -> Unit, onNew: () -> Unit, onEdit: (CustomArpeggio) -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val selected = state.arpeggioPattern?.id
    AppSheet(strings.t("分解指法"), onClose) {
        CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
            Column {
                state.arpeggioPatterns.forEachIndexed { i, p ->
                    if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                    val custom = state.customArpeggios().firstOrNull { ArpeggioPatternId.of(it) == p.id }
                    PickerRowItem(p.id == selected, p.isCustom, { state.select(p); onClose() }, { custom?.let(onEdit) }, { custom?.let { state.deleteCustomArpeggio(it.id) } }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(p.digits, color = if (p.id == selected) c.accent else c.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace, maxLines = 1)
                            val summary = if (p.isCustom) p.summary else strings.t(p.summary)
                            if (summary.isNotEmpty()) {
                                Text("·", color = c.dim)
                                Text(summary, color = c.sub, fontSize = 14.sp, maxLines = 1)
                            }
                        }
                    }
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                NewRow(state.canAddCustomArpeggio, onNew)
            }
        }
        state.rootStringNumber?.let {
            Text(strings.t("数字是弦号，5 代表根音弦（当前和弦是 %lld 弦）", it), color = c.sub, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp, start = 4.dp))
        }
    }
}

/** 自定义指法在列表里的 id。 */
private object ArpeggioPatternId {
    fun of(item: CustomArpeggio) = com.example.strumcoach.chord.ArpeggioPattern.CUSTOM_PREFIX + item.id
}

@Composable
private fun RhythmPicker(state: ChordLibraryState, onClose: () -> Unit, onNew: () -> Unit, onEdit: (CustomStrumRhythm) -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val selected = state.strumRhythm.id
    AppSheet(strings.t("扫弦节奏型"), onClose) {
        CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
            Column {
                state.strumRhythms.forEachIndexed { i, r ->
                    if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                    val custom = state.customRhythms(state.instrument.family).firstOrNull { com.example.strumcoach.chord.StrumRhythm.CUSTOM_PREFIX + it.id == r.id }
                    PickerRowItem(r.id == selected, r.isCustom, { state.select(r); onClose() }, { custom?.let(onEdit) }, { custom?.let { state.deleteCustomRhythm(it.id) } }) {
                        Column(Modifier.padding(vertical = 6.dp)) {
                            val name = if (r.isCustom) r.title else strings.t(r.title)
                            if (name.isNotEmpty()) Text(name, color = c.sub, fontSize = 13.sp, maxLines = 1)
                            Text(r.arrows, color = if (r.id == selected) c.accent else c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        }
                    }
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                NewRow(state.canAddCustomRhythm(), onNew)
            }
        }
    }
}

internal const val MAX_STEPS_FOR_HELP = ArpeggioInput.MAX_STEPS
internal const val MAX_BEATS_FOR_HELP = StrumInput.MAX_BEATS

package com.example.strumcoach.ui.training

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.strumcoach.chord.ChordLibrary
import com.example.strumcoach.chord.ChordRoot
import com.example.strumcoach.chord.ChordLibraryState
import com.example.strumcoach.chord.ChordPlayer
import com.example.strumcoach.chord.StrumRhythm
import com.example.strumcoach.chord.chordName
import com.example.strumcoach.chord.rootName
import com.example.strumcoach.i18n.LocalStrings
import com.example.strumcoach.i18n.tr
import com.example.strumcoach.strum.ChordProgression
import com.example.strumcoach.strum.PracticeRun
import com.example.strumcoach.strum.ProgressionChord
import com.example.strumcoach.strum.StrumTrainer
import com.example.strumcoach.tuner.NoteNaming
import com.example.strumcoach.ui.chords.CustomRhythmEditor
import com.example.strumcoach.ui.chords.EditorSheet
import com.example.strumcoach.ui.components.CardBox
import com.example.strumcoach.ui.components.Segmented
import com.example.strumcoach.ui.components.noteAnnotated
import com.example.strumcoach.ui.theme.AppTheme
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToInt

// 和弦进行 ----------------------------------------------------------------------

/**
 * 一行和弦块（横向滚动）：点一下修改，长按拖动排序，末尾“+”添加；下面是常用进行、我的进行、保存、练习遍数。
 * 标题行右边是乐器切换（吉他 / 尤克里里）。和 iOS 版的 ProgressionCard 一致。
 */
@Composable
fun ProgressionCard(trainer: StrumTrainer, naming: NoteNaming, enabled: Boolean) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var editing by remember { mutableStateOf<ProgressionChord?>(null) }
    var adding by remember { mutableStateOf(false) }
    var showLibrary by remember { mutableStateOf(false) }
    var showSave by remember { mutableStateOf(false) }
    var presetMenu by remember { mutableStateOf(false) }
    val instruments = ChordLibrary.strummableInstruments

    CardBox(Modifier.fillMaxWidth(), radius = 20.dp) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(tr("和弦进行"), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(strings.plural("%lld 小节", trainer.progression.totalBars), color = c.sub, fontSize = 12.sp, modifier = Modifier.weight(1f))
                Box(Modifier.widthIn(max = 190.dp)) {
                    Segmented(instruments.map { tr(it.name) }, instruments.indexOfFirst { it.id == trainer.instrument.id }.coerceAtLeast(0), { if (enabled) trainer.select(instruments[it]) })
                }
            }
            ChordBlocksRow(trainer, naming, enabled, onEdit = { editing = it }, onAdd = { adding = true })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box {
                    Pill(tr("常用进行"), "♪") { if (enabled) presetMenu = true }
                    DropdownMenu(presetMenu, { presetMenu = false }, containerColor = c.sheet) {
                        ChordProgression.presets.forEach { p ->
                            val label = if (p.name == ChordProgression.BLUES_KEY) strings.t(p.name) else p.name
                            DropdownMenuItem(text = { Text(label, color = c.text) }, onClick = { trainer.updateProgression(p.copy(id = UUID.randomUUID().toString())); presetMenu = false })
                        }
                    }
                }
                Pill(tr("我的进行"), "▤") { if (enabled) showLibrary = true }
                Pill(tr("保存"), "⤓") { if (enabled) showSave = true }
            }
            PracticeTargetField(trainer, enabled)
        }
    }

    editing?.let { pc ->
        ProgressionChordSheet(
            pc, naming, isNew = false, canDelete = trainer.progression.chords.size > 1, onClose = { editing = null },
            onSave = { trainer.updateProgression(trainer.progression.update(it)) },
            onDelete = { trainer.updateProgression(trainer.progression.delete(pc.id)) },
            onDuplicate = { trainer.progression.duplicate(pc.id)?.let { trainer.updateProgression(it.first) } },
        )
    }
    if (adding) {
        val last = trainer.progression.chords.lastOrNull()
        ProgressionChordSheet(
            ProgressionChord(last?.root ?: 0, last?.type ?: com.example.strumcoach.chord.ChordType.Major, 1), naming, isNew = true, canDelete = false, onClose = { adding = false },
            onSave = { trainer.updateProgression(trainer.progression.append(it.copy(id = UUID.randomUUID().toString()))) }, onDelete = {}, onDuplicate = {},
        )
    }
    if (showLibrary) SavedProgressionsSheet(trainer, naming) { showLibrary = false }
    if (showSave) {
        val initial = trainer.progression.name.ifEmpty { trainer.progression.label { naming.chordName(it) } }
        SaveDialog(initial, onDismiss = { showSave = false }) { name -> trainer.saveProgression(name); showSave = false }
    }
}

@Composable
private fun Pill(label: String, icon: String, onClick: () -> Unit) {
    val c = AppTheme.colors
    Row(
        Modifier.height(30.dp).clip(RoundedCornerShape(50)).background(c.accent.copy(alpha = 0.14f)).clickable(onClick = onClick).padding(horizontal = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(icon, color = c.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Text(label, color = c.accent, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

/** 一个和弦块：和弦名加持续几小节。`current` 是正在弹的，`flash` 是即将换到它。 */
@Composable
fun ChordBlock(name: String, bars: Int, modifier: Modifier = Modifier, current: Boolean = false) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier.widthIn(min = 52.dp).height(58.dp).clip(shape).then(if (current) Modifier.background(c.accent) else Modifier.background(c.card2)).padding(horizontal = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Text(noteAnnotated(name), color = if (current) androidx.compose.ui.graphics.Color.White else c.text, fontSize = 19.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text(strings.plural("%lld 小节", bars), color = if (current) androidx.compose.ui.graphics.Color.White.copy(alpha = 0.85f) else c.sub, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

/** 和弦块一行：点修改，长按后左右拖动排序（拖过相邻的块就换位置）。 */
@Composable
private fun ChordBlocksRow(trainer: StrumTrainer, naming: NoteNaming, enabled: Boolean, onEdit: (ProgressionChord) -> Unit, onAdd: () -> Unit) {
    val c = AppTheme.colors
    val gap = with(androidx.compose.ui.platform.LocalDensity.current) { 8.dp.toPx() }
    var draggingId by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val widths = remember { mutableStateMapOf<String, Int>() }
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        trainer.progression.chords.forEach { pc ->
            key(pc.id) {
                val dragging = draggingId == pc.id
                ChordBlock(
                    naming.chordName(pc.chord), pc.bars,
                    Modifier.onSizeChanged { widths[pc.id] = it.width }
                        .offset { IntOffset(if (dragging) dragOffset.roundToInt() else 0, 0) }
                        .alpha(if (dragging) 0.6f else 1f)
                        .pointerInput(pc.id, enabled) {
                            if (!enabled) return@pointerInput
                            detectDragGesturesAfterLongPress(
                                onDragStart = { draggingId = pc.id; dragOffset = 0f },
                                onDrag = { change, amount ->
                                    change.consume()
                                    dragOffset += amount.x
                                    val list = trainer.progression.chords
                                    val i = list.indexOfFirst { it.id == pc.id }
                                    val neighbor = (if (dragOffset > 0) list.getOrNull(i + 1) else list.getOrNull(i - 1)) ?: return@detectDragGesturesAfterLongPress
                                    val step = (widths[neighbor.id] ?: 0) + gap
                                    if (abs(dragOffset) > step * 0.6f) {
                                        trainer.updateProgression(trainer.progression.move(pc.id, neighbor.id))
                                        dragOffset -= if (dragOffset > 0) step else -step
                                    }
                                },
                                onDragEnd = { draggingId = null; dragOffset = 0f },
                                onDragCancel = { draggingId = null; dragOffset = 0f },
                            )
                        }
                        .clickable(enabled = enabled) { onEdit(pc) },
                )
            }
        }
        Box(
            Modifier.size(width = 52.dp, height = 58.dp).clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.14f)).clickable(enabled = enabled, onClick = onAdd),
            contentAlignment = Alignment.Center,
        ) { Text("+", color = c.accent, fontSize = 24.sp, fontWeight = FontWeight.SemiBold) }
    }
}

/** 改一个和弦：根音、类型、持续几小节；已有的还能复制、删除。 */
@Composable
private fun ProgressionChordSheet(
    start: ProgressionChord, naming: NoteNaming, isNew: Boolean, canDelete: Boolean, onClose: () -> Unit,
    onSave: (ProgressionChord) -> Unit, onDelete: () -> Unit, onDuplicate: () -> Unit,
) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var root by remember { mutableStateOf(start.root) }
    var type by remember { mutableStateOf(start.type) }
    var bars by remember { mutableStateOf(start.bars) }
    EditorSheet(
        title = naming.chordName(root, type), canSave = true, onCancel = onClose, saveLabel = if (isNew) tr("添加") else tr("完成"),
        onSave = { onSave(start.copy(root = root, typeID = type.id, bars = bars)); onClose() },
    ) {
        Text(tr("根音"), color = c.sub, fontSize = 13.sp)
        ChordRoot.all.chunked(6).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { pc -> GridChip(naming.rootName(pc), root == pc, Modifier.weight(1f)) { root = pc } }
            }
        }
        Text(tr("类型"), color = c.sub, fontSize = 13.sp)
        com.example.strumcoach.chord.ChordType.builtins.chunked(5).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { t -> GridChip(naming.chordName(root, t), type.id == t.id, Modifier.weight(1f)) { type = t } }
                repeat(5 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
        Text(tr("持续"), color = c.sub, fontSize = 13.sp)
        Segmented(ProgressionChord.barChoices.map { strings.plural("%lld 小节", it) }, ProgressionChord.barChoices.indexOf(bars).coerceAtLeast(0), { bars = ProgressionChord.barChoices[it] })
        if (!isNew) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("⧉  " + tr("复制"), color = c.accent, fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.clickable { onDuplicate(); onClose() }.padding(vertical = 8.dp))
            Box(Modifier.weight(1f))
            if (canDelete) Text(tr("删除"), color = androidx.compose.ui.graphics.Color(0xFFE5484D), fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.clickable { onDelete(); onClose() }.padding(vertical = 8.dp))
        }
    }
}

@Composable
private fun GridChip(label: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(
        modifier.height(40.dp).clip(RoundedCornerShape(12.dp)).then(if (selected) Modifier.background(c.accent) else Modifier.background(c.card2)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(noteAnnotated(label), color = if (selected) androidx.compose.ui.graphics.Color.White else c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
}

/** 我的进行：点一下套用，右边的 × 删除。 */
@Composable
private fun SavedProgressionsSheet(trainer: StrumTrainer, naming: NoteNaming, onClose: () -> Unit) {
    val c = AppTheme.colors
    com.example.strumcoach.ui.metronome.AppSheet(tr("我的进行"), onClose) {
        if (trainer.saved.isEmpty()) {
            Text(tr("还没有保存的进行。编辑好和弦后点“保存”。"), color = c.sub, fontSize = 14.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp), textAlign = TextAlign.Center)
        } else {
            CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
                Column {
                    trainer.saved.reversed().forEachIndexed { i, p ->
                        if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                        Row(Modifier.fillMaxWidth().clickable { trainer.updateProgression(p.copy(id = UUID.randomUUID().toString())); onClose() }.padding(start = 16.dp, top = 10.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(p.name, color = c.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                Text(noteAnnotated(p.label { naming.chordName(it) }), color = c.sub, fontSize = 13.sp, maxLines = 2)
                            }
                            Box(Modifier.size(44.dp).clickable { trainer.deleteSaved(p) }, contentAlignment = Alignment.Center) { Text("✕", color = c.sub, fontSize = 15.sp) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SaveDialog(initial: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("保存和弦进行")) },
        text = { Column { TextField(name, { name = it.take(30) }, singleLine = true, label = { Text(tr("名字")) }); Text(tr("同名的会被覆盖。"), modifier = Modifier.padding(top = 8.dp), fontSize = 13.sp) } },
        confirmButton = { TextButton(enabled = name.isNotBlank(), onClick = { onSave(name) }) { Text(tr("保存")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } },
    )
}

/** 练几遍：数字 1–99，留空（或 0）表示一直练到点“结束”。 */
@Composable
private fun PracticeTargetField(trainer: StrumTrainer, enabled: Boolean) {
    val c = AppTheme.colors
    var text by remember { mutableStateOf(trainer.practiceTarget?.toString() ?: "") }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(tr("练习遍数"), color = c.text, fontSize = 14.sp)
        Box(Modifier.size(width = 58.dp, height = 34.dp).clip(RoundedCornerShape(9.dp)).background(c.card2), contentAlignment = Alignment.Center) {
            BasicTextField(
                text, { v ->
                    val digits = v.filter { it.isDigit() }.take(2)
                    text = digits
                    trainer.updatePracticeTarget(digits.toIntOrNull()?.takeIf { it >= PracticeRun.TARGET_RANGE.first })
                },
                enabled = enabled, singleLine = true,
                textStyle = TextStyle(color = c.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                cursorBrush = SolidColor(c.accent),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                decorationBox = { inner -> Box(contentAlignment = Alignment.Center) { if (text.isEmpty()) Text("∞", color = c.dim, fontSize = 16.sp); inner() } },
            )
        }
        Text(tr("留空表示一直练"), color = c.sub, fontSize = 12.sp, modifier = Modifier.weight(1f), maxLines = 2)
    }
}

// 节奏型 --------------------------------------------------------------------------

/** 节奏型一栏：标题和筛选，下面横向一排标签（名字、星标 / 已掌握小标记、箭头串）；点选，长按有收藏 / 已掌握 / 编辑 / 删除。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PatternPicker(trainer: StrumTrainer, chords: ChordLibraryState, player: ChordPlayer, enabled: Boolean) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var editor by remember { mutableStateOf<com.example.strumcoach.chord.CustomStrumRhythm?>(null) }
    var adding by remember { mutableStateOf(false) }
    val family = trainer.instrument.family
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("节奏型"), color = c.sub, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            FilterMenu(trainer, enabled)
        }
        if (trainer.visiblePatterns.isEmpty()) {
            Text(
                if (trainer.filter == com.example.strumcoach.strum.RhythmMarks.Filter.FAVORITES) tr("还没有收藏的节奏型：长按节奏型或点格子上方的星标收藏。") else tr("这件乐器的节奏型都已掌握。"),
                color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            trainer.visiblePatterns.forEach { p ->
                val selected = p.id == trainer.rhythm.id
                var menu by remember { mutableStateOf(false) }
                val shape = RoundedCornerShape(14.dp)
                val saved = if (p.isCustom) chords.customRhythms(family).firstOrNull { StrumRhythm.CUSTOM_PREFIX + it.id == p.id } else null
                Box {
                    Column(
                        Modifier.clip(shape).then(if (selected) Modifier.background(c.accent.copy(alpha = 0.14f)) else Modifier.background(c.card))
                            .border(1.5.dp, if (selected) c.accent else androidx.compose.ui.graphics.Color.Transparent, shape)
                            .combinedClickable(enabled = enabled, onClick = { trainer.select(p) }, onLongClick = { menu = true })
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            val name = if (p.isCustom) p.title.ifEmpty { p.arrows } else strings.t(p.title)
                            Text(name, color = if (selected) c.accent else c.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            if (p.isCustom && p.title.isNotEmpty()) Text(tr("自定义"), color = c.sub, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.card2).padding(horizontal = 5.dp, vertical = 1.dp))
                            if (trainer.isFavorite(p)) Text("★", color = androidx.compose.ui.graphics.Color(0xFFFAB81A), fontSize = 12.sp)
                            if (trainer.isMastered(p)) Text("✓", color = c.green, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                        Text(p.arrows, color = c.sub, fontSize = 13.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace, maxLines = 1)
                    }
                    DropdownMenu(menu, { menu = false }, containerColor = c.sheet) {
                        DropdownMenuItem(text = { Text(if (trainer.isFavorite(p)) tr("取消收藏") else tr("收藏"), color = c.text) }, onClick = { trainer.setFavorite(!trainer.isFavorite(p), p); menu = false })
                        DropdownMenuItem(text = { Text(if (trainer.isMastered(p)) tr("取消已掌握") else tr("标记为已掌握"), color = c.text) }, onClick = { trainer.setMastered(!trainer.isMastered(p), p); menu = false })
                        if (saved != null) {
                            DropdownMenuItem(text = { Text(tr("编辑…"), color = c.text) }, onClick = { menu = false; editor = saved })
                            DropdownMenuItem(text = { Text(tr("删除"), color = androidx.compose.ui.graphics.Color(0xFFE5484D)) }, onClick = { menu = false; chords.deleteCustomRhythm(saved.id, family) })
                        }
                    }
                }
            }
            // 自定义：和弦库里也能编辑，两边共用
            val dashShape = RoundedCornerShape(14.dp)
            Column(
                Modifier.clip(dashShape).border(1.dp, c.line, dashShape).clickable(enabled = enabled) { adding = true }.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(tr("自定义…"), color = c.accent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text("D U X ·", color = c.sub, fontSize = 13.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace)
            }
        }
    }
    if (adding || editor != null) {
        CustomRhythmEditor(chords, player, editing = editor, family = family, selectsOnSave = false, onSave = { saved -> saved.rhythm?.let { trainer.select(it) } }, onClose = { adding = false; editor = null })
    }
}

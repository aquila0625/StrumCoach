package com.example.strumcoach.ui.metronome

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.strumcoach.i18n.LocalStrings
import com.example.strumcoach.i18n.tr
import com.example.strumcoach.metronome.AccentPreset
import com.example.strumcoach.metronome.MetronomeController
import com.example.strumcoach.metronome.SoundGroup
import com.example.strumcoach.rhythm.Subdivision
import com.example.strumcoach.rhythm.TimeSignature
import com.example.strumcoach.ui.components.NoteGlyph
import com.example.strumcoach.ui.components.Segmented
import com.example.strumcoach.ui.components.glyph
import com.example.strumcoach.ui.theme.AppTheme
import kotlin.math.roundToInt

/** 底部面板：顶上一条把手，标题（20 粗体）和右边主色的“完成”，和 iOS 版的 BottomSheetHost 一样。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppSheet(title: String, onClose: () -> Unit, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    ModalBottomSheet(
        onDismissRequest = onClose, containerColor = c.sheet, scrimColor = c.scrim,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        dragHandle = {
            Box(Modifier.padding(top = 10.dp, bottom = 10.dp).width(40.dp).height(5.dp).clip(RoundedCornerShape(50)).background(c.weak))
        },
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 12.dp)) {
            Row(Modifier.fillMaxWidth().padding(bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, color = c.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.weight(1f))
                Text(tr("完成"), color = c.accent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { onClose() }.padding(start = 12.dp, top = 4.dp, bottom = 4.dp))
            }
            content()
        }
    }
}

@Composable
fun SectionLabel(title: String, note: String = "") {
    val c = AppTheme.colors
    Row(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = c.sub, fontSize = 13.sp, maxLines = 1)
        Box(Modifier.weight(1f))
        Text(note, color = c.sub, fontSize = 13.sp, maxLines = 2, textAlign = TextAlign.End)
    }
}

// 节奏设置 ---------------------------------------------------------------

@Composable
fun RhythmSheet(controller: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val cfg = controller.config
    val ts = cfg.timeSignature
    AppSheet(strings.t("节奏设置"), onClose) {
        SectionLabel(tr("拍号"), tr("每小节拍数 / 以几分音符为一拍"))
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.sheetCard).padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            NumberWheel(ts.beatsPerBar, TimeSignature.editorBeats) { controller.setTimeSignature(TimeSignature.of(it, ts.beatUnit)) }
            Text("/", color = c.sub, fontSize = 34.sp, fontWeight = FontWeight.ExtraLight)
            Box(Modifier.weight(1f)) {
                Segmented(
                    TimeSignature.ALLOWED_UNITS.map { "$it" }, TimeSignature.ALLOWED_UNITS.indexOf(ts.beatUnit),
                    onSelect = { controller.setTimeSignature(TimeSignature.of(ts.beatsPerBar, TimeSignature.ALLOWED_UNITS[it])) },
                )
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TimeSignature.quickPicks.forEach { pick ->
                val on = pick == ts
                Box(
                    Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(50)).background(c.sheetCard)
                        .then(if (on) Modifier.border(1.5.dp, c.accent, RoundedCornerShape(50)) else Modifier)
                        .semantics { contentDescription = strings.t("拍号 %lld %lld", pick.beatsPerBar, pick.beatUnit) }
                        .clickable { controller.setTimeSignature(pick) },
                    contentAlignment = Alignment.Center,
                ) { Text(pick.displayName, color = if (on) c.accent else c.sub, fontSize = 14.sp, maxLines = 1) }
            }
        }
        SectionLabel(tr("切分"))
        Subdivision.entries.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { sub ->
                    val on = sub == cfg.subdivision
                    Column(
                        Modifier.weight(1f).height(78.dp).clip(RoundedCornerShape(14.dp)).background(c.sheetCard)
                            .then(if (on) Modifier.border(2.dp, c.accent, RoundedCornerShape(14.dp)) else Modifier)
                            .semantics { contentDescription = strings.t(sub.title) }
                            .clickable { controller.setSubdivision(sub) },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        NoteGlyph(sub.glyph, if (on) c.accent else c.text)
                        Text(tr(sub.title), color = if (on) c.text else c.sub, fontSize = 11.5.sp, maxLines = 2, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 3.dp, vertical = 2.dp))
                    }
                }
            }
        }
        SectionLabel(tr("重音预设"))
        val matching = AccentPreset.entries.indexOfFirst { it.pattern(ts) == cfg.accents }
        Segmented(AccentPreset.entries.map { strings.t(it.title) }, matching, onSelect = { controller.setAccentPreset(AccentPreset.entries[it]) })
    }
}

/** 拍数滚轮：上下各露出一个数字，上下拖或点上下的数字改值。 */
@Composable
private fun NumberWheel(value: Int, range: IntRange, onChange: (Int) -> Unit) {
    val c = AppTheme.colors
    var base by remember { mutableIntStateOf(value) }
    var dragged by remember { mutableStateOf(0f) }
    Column(
        Modifier.width(84.dp).height(96.dp).pointerInput(range) {
            detectVerticalDragGestures(onDragStart = { base = value; dragged = 0f }) { _, dy ->
                dragged += dy
                val target = (base - (dragged / (24 * density)).roundToInt()).coerceIn(range.first, range.last)
                if (target != value) onChange(target)
            }
        }.semantics { contentDescription = "$value" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.fillMaxWidth().height(24.dp).clickable { if (value - 1 >= range.first) onChange(value - 1) }, contentAlignment = Alignment.Center) {
            Text(if (value > range.first) "${value - 1}" else " ", color = c.dim, fontSize = 16.sp)
        }
        Box(Modifier.fillMaxWidth().height(40.dp).clip(RoundedCornerShape(10.dp)).background(c.card2), contentAlignment = Alignment.Center) {
            Text("$value", color = c.text, fontSize = 30.sp, fontWeight = FontWeight.SemiBold)
        }
        Box(Modifier.fillMaxWidth().height(24.dp).clickable { if (value + 1 <= range.last) onChange(value + 1) }, contentAlignment = Alignment.Center) {
            Text(if (value < range.last) "${value + 1}" else " ", color = c.dim, fontSize = 16.sp)
        }
    }
}

// 音色与反馈 -------------------------------------------------------------

@Composable
fun SoundSheet(controller: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    AppSheet(strings.t("音色与反馈"), onClose) {
        SoundGroup.entries.forEachIndexed { index, group ->
            SectionLabel(tr(group.title), if (index == 0) tr("点一下试听，强 · 次强 · 弱各一个音") else "")
            group.sounds.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { sound ->
                        val on = controller.config.sound == sound
                        Box(
                            Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(14.dp)).background(c.sheetCard)
                                .then(if (on) Modifier.border(2.dp, c.accent, RoundedCornerShape(14.dp)) else Modifier)
                                .clickable { controller.setSound(sound) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(tr(sound.title), color = if (on) c.accent else c.text, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, textAlign = TextAlign.Center)
                        }
                    }
                    repeat(3 - row.size) { Box(Modifier.weight(1f)) }
                }
            }
        }
        SectionLabel(tr("切分音量"), strings.t("相对主拍 %@", "${(controller.config.subdivisionVolume * 100).roundToInt()}%"))
        Slider(
            value = controller.config.subdivisionVolume, onValueChange = { controller.setSubdivisionVolume((it * 20).roundToInt() / 20f) }, valueRange = 0f..1f,
            colors = SliderDefaults.colors(thumbColor = c.accent, activeTrackColor = c.accent, inactiveTrackColor = c.card2),
            modifier = Modifier.padding(horizontal = 14.dp),
        )
    }
}

// 输入速度 ---------------------------------------------------------------

@Composable
fun BpmSheet(controller: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    var text by remember { mutableStateOf(controller.bpm.roundToInt().toString()) }
    val value = text.toIntOrNull()
    val valid = value != null && value in 20..400
    AppSheet(tr("输入速度"), onClose = { if (valid) controller.setBpm(value!!.toDouble()); onClose() }) {
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            TextField(
                text, { text = it.filter(Char::isDigit).take(3) }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                textStyle = androidx.compose.ui.text.TextStyle(fontSize = 56.sp, fontWeight = FontWeight.Light, textAlign = TextAlign.Center, color = c.text),
                colors = TextFieldDefaults.colors(focusedContainerColor = c.sheetCard, unfocusedContainerColor = c.sheetCard, focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent),
                shape = RoundedCornerShape(16.dp), modifier = Modifier.width(200.dp),
            )
            Text(
                if (valid || text.isEmpty()) tr("范围 20–400 BPM") else tr("请输入 20–400 之间的数"),
                color = if (valid || text.isEmpty()) c.sub else c.accent, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 20.dp),
            )
        }
    }
}

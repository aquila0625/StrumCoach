package com.example.tunebeatchord.ui.metronome

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.metronome.AccentPreset
import com.example.tunebeatchord.metronome.MetronomeController
import com.example.tunebeatchord.metronome.SoundGroup
import com.example.tunebeatchord.rhythm.Subdivision
import com.example.tunebeatchord.rhythm.TimeSignature
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SheetFrame(title: String, onClose: () -> Unit, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    ModalBottomSheet(onDismissRequest = onClose, containerColor = c.sheet) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
            Text(title, color = c.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 12.dp))
            content()
        }
    }
}

@Composable
private fun Label(text: String) = Text(text, color = AppTheme.colors.sub, fontSize = 14.sp, modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))

/** 节奏设置：拍号、重音预设、切分、切分音量。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RhythmSheet(controller: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    val cfg = controller.config
    SheetFrame(tr("节奏设置"), onClose) {
        Label(tr("拍号"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            TimeSignature.presets.forEach { ts ->
                Chip(ts.displayName, cfg.timeSignature == ts, { controller.setTimeSignature(ts) }, height = 44.dp)
            }
        }
        Label(tr("每小节拍数 / 以几分音符为一拍"))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Chip("−", false, { controller.setTimeSignature(TimeSignature.of(cfg.timeSignature.beatsPerBar - 1, cfg.timeSignature.beatUnit)) }, Modifier.size(48.dp), 48.dp)
            Text("${cfg.timeSignature.beatsPerBar}", color = c.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 8.dp))
            Chip("+", false, { controller.setTimeSignature(TimeSignature.of((cfg.timeSignature.beatsPerBar + 1).coerceAtMost(16), cfg.timeSignature.beatUnit)) }, Modifier.size(48.dp), 48.dp)
            Text("/", color = c.sub, fontSize = 24.sp)
            TimeSignature.ALLOWED_UNITS.forEach { u ->
                Chip("$u", cfg.timeSignature.beatUnit == u, { controller.setTimeSignature(TimeSignature.of(cfg.timeSignature.beatsPerBar, u)) }, height = 44.dp)
            }
        }
        Label(tr("重音预设"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AccentPreset.entries.forEach { p ->
                Chip(tr(p.title), cfg.accents == p.pattern(cfg.timeSignature), { controller.setAccentPreset(p) }, height = 44.dp, fontSize = 15)
            }
        }
        Label(tr("切分"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Subdivision.entries.forEach { s ->
                Chip(tr(s.title), cfg.subdivision == s, { controller.setSubdivision(s) }, height = 44.dp, fontSize = 15)
            }
        }
        if (cfg.subdivision != Subdivision.QUARTER) {
            Label(LocalStrings.current.t("相对主拍 %@", "${(cfg.subdivisionVolume * 100).roundToInt()}%"))
            Slider(cfg.subdivisionVolume, { controller.setSubdivisionVolume(it) }, valueRange = 0.1f..1f)
        }
    }
}

/** 音色：按组列出，点一下选中。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SoundSheet(controller: MetronomeController, onClose: () -> Unit) {
    SheetFrame(tr("节拍音色"), onClose) {
        SoundGroup.entries.forEach { group ->
            Label(tr(group.title))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                group.sounds.forEach { s -> Chip(tr(s.title), controller.config.sound == s, { controller.setSound(s) }, height = 44.dp, fontSize = 15) }
            }
        }
        Box(Modifier.height(8.dp))
    }
}

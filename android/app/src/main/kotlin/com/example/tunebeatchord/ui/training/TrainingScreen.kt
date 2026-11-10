package com.example.tunebeatchord.ui.training

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.metronome.MetronomeController
import com.example.tunebeatchord.rhythm.RampSettings
import com.example.tunebeatchord.strum.StrumTrainer
import com.example.tunebeatchord.ui.components.Card
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.ScreenTitle
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.roundToInt

/** 训练页：扫弦跟练的入口，加上节拍器的渐进提速和静音训练（对节拍器全局生效）。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TrainingScreen(trainer: StrumTrainer, metronome: MetronomeController, onOpenStrum: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val o = metronome.options
    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        ScreenTitle(tr("训练"))
        Box(Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) {
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(c.accentBrush).clickable { onOpenStrum() }.padding(20.dp)) {
                Column {
                    Text(tr("扫弦节奏型"), color = c.onAccent, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    Text(tr("跟着节奏扫，麦克风帮你打分"), color = c.onAccent.copy(alpha = 0.85f), fontSize = 15.sp, modifier = Modifier.padding(top = 4.dp))
                    val last = trainer.history.last
                    Text(
                        if (last == null) tr("还没练过，先听一听再开始")
                        else strings.t("上次") + " " + strings.t("%lld 分", last.score) + (trainer.history.best(last.patternID)?.let { "  ·  " + strings.t("这个节奏型最好 %lld 分", it) } ?: ""),
                        color = c.onAccent.copy(alpha = 0.85f), fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp),
                    )
                    Box(Modifier.padding(top = 14.dp).clip(RoundedCornerShape(50)).background(c.onAccent.copy(alpha = 0.18f)).padding(horizontal = 18.dp, vertical = 10.dp)) {
                        Text(tr("开始练习"), color = c.onAccent, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        Text(tr("节拍器训练"), color = c.sub, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp))

        TrainingCard(tr("渐进提速"), o.rampEnabled, { v -> metronome.updateOptions { it.copy(rampEnabled = v) } }, subtitle = tr("目标比起始低就是渐进减速")) {
            Stepper(tr("起始"), "${o.rampStart} BPM", { metronome.updateOptions { it.copy(rampStart = (it.rampStart - 1).coerceAtLeast(20)) } }, { metronome.updateOptions { it.copy(rampStart = (it.rampStart + 1).coerceAtMost(400)) } })
            Stepper(tr("目标"), "${o.rampTarget} BPM", { metronome.updateOptions { it.copy(rampTarget = (it.rampTarget - 1).coerceAtLeast(20)) } }, { metronome.updateOptions { it.copy(rampTarget = (it.rampTarget + 1).coerceAtMost(400)) } })
            Stepper(tr("每档变化"), "${o.rampStep} BPM", { metronome.updateOptions { it.copy(rampStep = (it.rampStep - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(rampStep = (it.rampStep + 1).coerceAtMost(40)) } })
            Stepper(tr("每档持续"), strings.plural("%lld 小节", o.rampBars), { metronome.updateOptions { it.copy(rampBars = (it.rampBars - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(rampBars = (it.rampBars + 1).coerceAtMost(32)) } })
            Text(tr("到达目标后"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(RampSettings.EndBehavior.STOP to "到目标后停止", RampSettings.EndBehavior.HOLD to "保持目标速度", RampSettings.EndBehavior.LOOP to "从头循环").forEach { (e, key) ->
                    Chip(tr(key), o.rampEnd == e.id, { metronome.updateOptions { it.copy(rampEnd = e.id) } }, height = 38.dp, fontSize = 14)
                }
            }
        }
        TrainingCard(tr("静音训练"), o.muteEnabled, { v -> metronome.updateOptions { it.copy(muteEnabled = v) } }, subtitle = tr("静音时保持心里的节拍，恢复时检查有没有跑快或跑慢")) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip(tr("按小节"), o.muteKind == "bars", { metronome.updateOptions { it.copy(muteKind = "bars") } }, height = 38.dp, fontSize = 14)
                Chip(tr("随机静音"), o.muteKind == "random", { metronome.updateOptions { it.copy(muteKind = "random") } }, height = 38.dp, fontSize = 14)
            }
            if (o.muteKind == "bars") {
                Stepper(tr("有声"), strings.plural("%lld 小节", o.muteAudible), { metronome.updateOptions { it.copy(muteAudible = (it.muteAudible - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(muteAudible = (it.muteAudible + 1).coerceAtMost(16)) } })
                Stepper(tr("静音"), strings.plural("%lld 小节", o.muteMuted), { metronome.updateOptions { it.copy(muteMuted = (it.muteMuted - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(muteMuted = (it.muteMuted + 1).coerceAtMost(16)) } })
            } else {
                Stepper(tr("概率"), "${(o.muteProbability * 100).roundToInt()}%", { metronome.updateOptions { it.copy(muteProbability = (it.muteProbability - 0.05).coerceAtLeast(0.05)) } }, { metronome.updateOptions { it.copy(muteProbability = (it.muteProbability + 0.05).coerceAtMost(0.95)) } })
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(tr("每小节第一拍总是响"), color = c.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    Switch(o.muteKeepsDownbeat, { v -> metronome.updateOptions { it.copy(muteKeepsDownbeat = v) } })
                }
            }
        }
    }
}

@Composable
private fun TrainingCard(title: String, enabled: Boolean, onToggle: (Boolean) -> Unit, subtitle: String, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Box(Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) {
        Card(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(title, color = c.text, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Text(subtitle, color = c.sub, fontSize = 13.sp)
                    }
                    Switch(enabled, onToggle)
                }
                if (enabled) content()
            }
        }
    }
}

@Composable
private fun Stepper(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    val c = AppTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(label, color = c.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Chip("−", false, onMinus, Modifier.size(42.dp), 42.dp)
        Text(value, color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 10.dp))
        Chip("+", false, onPlus, Modifier.size(42.dp), 42.dp)
    }
}

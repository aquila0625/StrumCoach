package com.example.tunebeatchord.ui.training

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.chord.StrumCell
import com.example.tunebeatchord.chord.chordName
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.Strings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.metronome.MetronomeController
import com.example.tunebeatchord.metronome.TrainingOptions
import com.example.tunebeatchord.rhythm.RampSettings
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.strum.StrumTrainer
import com.example.tunebeatchord.ui.components.CardBox
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.ChevronRight
import com.example.tunebeatchord.ui.components.PlayPauseIcon
import com.example.tunebeatchord.ui.metronome.AppSheet
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

private enum class TrainingSheet { RAMP, MUTE, TIMER }

/** 训练页，布局和 iOS 版一致：标题、扫弦英雄卡片、“节拍器训练”下的渐进提速和静音小节两张卡片（开关、点卡片改参数）、底部大按钮“开始训练”。 */
@Composable
fun TrainingScreen(trainer: StrumTrainer, metronome: MetronomeController, settings: Settings, onOpenStrum: (start: Boolean) -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val o = metronome.options
    var sheet by remember { mutableStateOf<TrainingSheet?>(null) }
    var clock by remember { mutableLongStateOf(0L) }
    LaunchedEffect(metronome.isPlaying) { while (metronome.isPlaying) androidx.compose.runtime.withFrameNanos { clock = it; metronome.tick(it) } }

    Column(modifier) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("训练"), color = c.text, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            StrumHeroCard(trainer, settings, onOpenStrum)
            Text(tr("节拍器训练"), color = c.sub, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 4.dp).padding(top = 8.dp))
            RampCard(metronome, o, strings, onEdit = { sheet = TrainingSheet.RAMP })
            MuteCard(metronome, o, strings, onEdit = { sheet = TrainingSheet.MUTE })
            TimerCard(metronome, o, strings, onEdit = { sheet = TrainingSheet.TIMER })
        }
        Box(Modifier.padding(horizontal = 20.dp).padding(bottom = 14.dp)) {
            Row(
                Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(16.dp)).background(c.accentBrush).clickable { metronome.toggle() },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                PlayPauseIcon(metronome.isPlaying, Color.White, 22.dp)
                Text(if (metronome.isPlaying) tr("停止训练") else tr("开始训练"), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 10.dp))
            }
        }
    }

    when (sheet) {
        TrainingSheet.RAMP -> RampEditor(metronome) { sheet = null }
        TrainingSheet.MUTE -> MuteEditor(metronome) { sheet = null }
        TrainingSheet.TIMER -> TimerEditor(metronome) { sheet = null }
        null -> {}
    }
}

/** 训练卡片：标题和摘要、右上角开关，点卡片改参数。 */
@Composable
private fun TrainingCard(title: String, subtitle: String, isOn: Boolean, onToggle: (Boolean) -> Unit, onEdit: () -> Unit, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    CardBox(Modifier.fillMaxWidth(), radius = 20.dp, border = isOn) {
        Column(Modifier.fillMaxWidth().clickable { onEdit() }.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, color = c.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(subtitle, color = c.sub, fontSize = 13.sp, maxLines = 2, modifier = Modifier.weight(1f, fill = false))
                        ChevronRight(c.dim, 12.dp)
                    }
                }
                Switch(
                    isOn, onToggle,
                    colors = SwitchDefaults.colors(checkedTrackColor = c.green, checkedThumbColor = Color.White, checkedBorderColor = c.green, uncheckedTrackColor = c.card2, uncheckedBorderColor = c.card2, uncheckedThumbColor = Color.White),
                )
            }
            content()
        }
    }
}

private fun rampSummary(o: TrainingOptions, s: Strings): String {
    val sign = if (o.rampTarget >= o.rampStart) "+" else "−"
    return s.t("%lld → %lld BPM · 每 %@ %@%lld", o.rampStart, o.rampTarget, s.plural("%lld 小节", o.rampBars), sign, o.rampStep)
}

@Composable
private fun RampCard(metronome: MetronomeController, o: TrainingOptions, strings: Strings, onEdit: () -> Unit) {
    val c = AppTheme.colors
    val ramp = RampSettings(o.rampStart, o.rampTarget, o.rampStep, o.rampBars, RampSettings.EndBehavior.fromId(o.rampEnd))
    val bar = if (o.rampEnabled && metronome.isPlaying) metronome.liveBar else null
    val progress = ramp.progress(bar ?: 0)
    val current = if (o.rampEnabled && metronome.isPlaying) metronome.liveBpm.roundToInt() else ramp.startBPM
    TrainingCard(strings.t("渐进提速"), rampSummary(o, strings), o.rampEnabled, { v -> metronome.updateOptions { it.copy(rampEnabled = v) } }, onEdit) {
        Column {
            Row(Modifier.padding(top = 14.dp, bottom = 10.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("$current", color = c.text, fontSize = 48.sp, fontWeight = FontWeight.ExtraLight)
                Text(strings.t("BPM 当前速度"), color = c.sub, fontSize = 13.sp, modifier = Modifier.weight(1f).padding(bottom = 8.dp))
                Text("${(progress * 100).roundToInt()}%", color = c.accent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp))
            }
            Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)).background(c.line)) {
                Box(Modifier.fillMaxWidth(max(0.04f, progress.toFloat())).height(8.dp).clip(RoundedCornerShape(50)).background(c.accent))
            }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("${ramp.startBPM}", color = c.sub, fontSize = 12.sp)
                Text(
                    if (bar != null) strings.t("第 %lld 小节 · 还剩 %@", bar + 1, strings.plural("%lld 小节", max(0, ramp.barsToTarget - bar)))
                    else strings.t("%@后到达目标 · %@", strings.plural("%lld 小节", ramp.barsToTarget), strings.t(endTitle(ramp.endBehavior))),
                    color = c.sub, fontSize = 12.sp, maxLines = 1,
                )
                Text("${ramp.targetBPM}", color = c.sub, fontSize = 12.sp)
            }
        }
    }
}

private fun endTitle(e: RampSettings.EndBehavior) = when (e) {
    RampSettings.EndBehavior.STOP -> "到目标后停止"
    RampSettings.EndBehavior.HOLD -> "保持目标速度"
    RampSettings.EndBehavior.LOOP -> "从头循环"
}

@Composable
private fun MuteCard(metronome: MetronomeController, o: TrainingOptions, strings: Strings, onEdit: () -> Unit) {
    val c = AppTheme.colors
    val plan = o.plan(120)?.mute ?: com.example.tunebeatchord.rhythm.MuteSettings.bars(o.muteAudible, o.muteMuted)
    val bar = if (metronome.isPlaying) metronome.liveBar else 0
    val summary = if (o.muteKind == "bars") strings.t("有声 %@ · 静音 %@", strings.plural("%lld 小节", o.muteAudible), strings.plural("%lld 小节", o.muteMuted))
    else strings.t(if (o.muteKeepsDownbeat) "随机静音 %@ 的拍 · 保留首拍" else "随机静音 %@ 的拍", "${(o.muteProbability * 100).roundToInt()}%")
    TrainingCard(strings.t("静音小节"), summary, o.muteEnabled, { v -> metronome.updateOptions { it.copy(muteEnabled = v) } }, onEdit) {
        Column {
            Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val first = bar / 8 * 8
                for (i in 0 until 8) {
                    val muted = plan.isMuted(first + i, 0)
                    val current = metronome.isPlaying && bar == first + i
                    Box(
                        Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(8.dp))
                            .background(if (muted) Color.Transparent else if (current) c.accent else c.accentSoft)
                            .then(if (muted) Modifier.border(1.5.dp, c.dim, RoundedCornerShape(8.dp)) else Modifier),
                        contentAlignment = Alignment.Center,
                    ) { if (muted) Text("🔇", fontSize = 11.sp) }
                }
            }
            Text(strings.t("静音时保持心里的节拍，恢复时检查有没有跑快或跑慢"), color = c.sub, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

// 参数面板 ---------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RampEditor(metronome: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val o = metronome.options
    AppSheet(strings.t("渐进提速"), onClose) {
        Text(tr("目标比起始低就是渐进减速"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(bottom = 8.dp))
        EditorCard {
            StepperRow(tr("起始"), "${o.rampStart} BPM", { metronome.updateOptions { it.copy(rampStart = (it.rampStart - 1).coerceAtLeast(20)) } }, { metronome.updateOptions { it.copy(rampStart = (it.rampStart + 1).coerceAtMost(400)) } })
            StepperRow(tr("目标"), "${o.rampTarget} BPM", { metronome.updateOptions { it.copy(rampTarget = (it.rampTarget - 1).coerceAtLeast(20)) } }, { metronome.updateOptions { it.copy(rampTarget = (it.rampTarget + 1).coerceAtMost(400)) } })
            StepperRow(tr("每档变化"), "${o.rampStep} BPM", { metronome.updateOptions { it.copy(rampStep = (it.rampStep - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(rampStep = (it.rampStep + 1).coerceAtMost(40)) } })
            StepperRow(tr("每档持续"), strings.plural("%lld 小节", o.rampBars), { metronome.updateOptions { it.copy(rampBars = (it.rampBars - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(rampBars = (it.rampBars + 1).coerceAtMost(32)) } })
        }
        Text(tr("到达目标后"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 14.dp, bottom = 8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(RampSettings.EndBehavior.STOP, RampSettings.EndBehavior.HOLD, RampSettings.EndBehavior.LOOP).forEach { e ->
                Chip(strings.t(endTitle(e)), o.rampEnd == e.id, { metronome.updateOptions { it.copy(rampEnd = e.id) } }, Modifier.weight(1f), height = 44.dp, fontSize = 13, horizontalPadding = 4.dp)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MuteEditor(metronome: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val o = metronome.options
    AppSheet(strings.t("静音训练"), onClose) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip(tr("按小节"), o.muteKind == "bars", { metronome.updateOptions { it.copy(muteKind = "bars") } }, Modifier.weight(1f), height = 44.dp, fontSize = 15)
            Chip(tr("随机静音"), o.muteKind == "random", { metronome.updateOptions { it.copy(muteKind = "random") } }, Modifier.weight(1f), height = 44.dp, fontSize = 15)
        }
        Box(Modifier.height(12.dp))
        EditorCard {
            if (o.muteKind == "bars") {
                StepperRow(tr("有声"), strings.plural("%lld 小节", o.muteAudible), { metronome.updateOptions { it.copy(muteAudible = (it.muteAudible - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(muteAudible = (it.muteAudible + 1).coerceAtMost(16)) } })
                StepperRow(tr("静音"), strings.plural("%lld 小节", o.muteMuted), { metronome.updateOptions { it.copy(muteMuted = (it.muteMuted - 1).coerceAtLeast(1)) } }, { metronome.updateOptions { it.copy(muteMuted = (it.muteMuted + 1).coerceAtMost(16)) } })
            } else {
                StepperRow(tr("概率"), "${(o.muteProbability * 100).roundToInt()}%", { metronome.updateOptions { it.copy(muteProbability = (it.muteProbability - 0.05).coerceAtLeast(0.05)) } }, { metronome.updateOptions { it.copy(muteProbability = (it.muteProbability + 0.05).coerceAtMost(0.95)) } })
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(tr("每小节第一拍"), color = c.text, fontSize = 15.sp)
                        Text(tr("每小节第一拍总是响"), color = c.sub, fontSize = 12.sp)
                    }
                    Switch(o.muteKeepsDownbeat, { v -> metronome.updateOptions { it.copy(muteKeepsDownbeat = v) } }, colors = SwitchDefaults.colors(checkedTrackColor = c.green, checkedThumbColor = Color.White, checkedBorderColor = c.green))
                }
            }
        }
    }
}

@Composable
private fun EditorCard(content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.sheetCard).padding(horizontal = 14.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { content() }
}

@Composable
private fun StepperRow(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    val c = AppTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().height(50.dp)) {
        Text(label, color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Circle("−", onMinus)
        Text(value, color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(96.dp), textAlign = TextAlign.Center, maxLines = 1)
        Circle("+", onPlus)
    }
}

@Composable
private fun Circle(symbol: String, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(Modifier.size(36.dp).clip(CircleShape).background(c.card2).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Text(symbol, color = c.text, fontSize = 20.sp, fontWeight = FontWeight.Light)
    }
}


// 练习计时 -------------------------------------------------------------------

/** “20 分钟”“1 小时 30 分钟”：按应用当前语言写。 */
@Composable
private fun minutesText(v: Int): String {
    val locale = androidx.compose.ui.platform.LocalContext.current.resources.configuration.locales[0]
    val fmt = android.icu.text.MeasureFormat.getInstance(locale, android.icu.text.MeasureFormat.FormatWidth.SHORT)
    val hours = v / 60
    val minutes = v % 60
    val parts = buildList {
        if (hours > 0) add(android.icu.util.Measure(hours, android.icu.util.MeasureUnit.HOUR))
        if (minutes > 0 || hours == 0) add(android.icu.util.Measure(minutes, android.icu.util.MeasureUnit.MINUTE))
    }
    return fmt.formatMeasures(*parts.toTypedArray())
}

private fun clock(seconds: Int) =
    if (seconds >= 3600) String.format("%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) else String.format("%d:%02d", seconds / 60, seconds % 60)

@Composable
private fun TimerCard(metronome: MetronomeController, o: TrainingOptions, strings: Strings, onEdit: () -> Unit) {
    val c = AppTheme.colors
    val goal = o.timerMinutes * 60
    val done = metronome.todaySeconds
    val ratio = if (goal > 0) minOf(1.0, done.toDouble() / goal) else 0.0
    val goalText = minutesText(o.timerMinutes)
    val percent = java.text.NumberFormat.getPercentInstance(androidx.compose.ui.platform.LocalContext.current.resources.configuration.locales[0]).format(ratio)
    val summary = strings.t(if (o.timerAutoStop) "目标 %@，到时提醒并停止" else "目标 %@，到时提醒", goalText)
    TrainingCard(strings.t("练习计时"), summary, o.timerEnabled, { v -> metronome.updateOptions { it.copy(timerEnabled = v) } }, onEdit) {
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            androidx.compose.foundation.Canvas(Modifier.padding(5.dp).size(54.dp)) {
                val w = 7.dp.toPx()
                val inset = w / 2
                val arcSize = androidx.compose.ui.geometry.Size(size.width - w, size.height - w)
                drawArc(c.line, 0f, 360f, false, androidx.compose.ui.geometry.Offset(inset, inset), arcSize, style = androidx.compose.ui.graphics.drawscope.Stroke(w))
                drawArc(c.accent, -90f, (360 * ratio).toFloat(), false, androidx.compose.ui.geometry.Offset(inset, inset), arcSize, style = androidx.compose.ui.graphics.drawscope.Stroke(w, cap = androidx.compose.ui.graphics.StrokeCap.Round))
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(clock(done), color = c.text, fontSize = 30.sp, fontWeight = FontWeight.Light)
                    Text("/ ${clock(goal)}", color = c.sub, fontSize = 15.sp, modifier = Modifier.padding(bottom = 4.dp))
                }
                Text(strings.t("今天已练 %@", percent), color = c.sub, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun TimerEditor(metronome: MetronomeController, onClose: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val o = metronome.options
    AppSheet(strings.t("练习计时"), onClose) {
        com.example.tunebeatchord.ui.metronome.SectionLabel(tr("今天的目标"), tr("按当天累计的练习时间算"))
        EditorCard {
            StepperRow(
                tr("目标"), minutesText(o.timerMinutes),
                { metronome.updateOptions { it.copy(timerMinutes = (it.timerMinutes - 5).coerceAtLeast(5)) } },
                { metronome.updateOptions { it.copy(timerMinutes = (it.timerMinutes + 5).coerceAtMost(180)) } },
            )
        }
        com.example.tunebeatchord.ui.metronome.SectionLabel(tr("到时"))
        EditorCard {
            Row(Modifier.fillMaxWidth().height(60.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(tr("自动停止"), color = c.text, fontSize = 15.sp)
                    Text(tr("到点时先提醒，再停止节拍器"), color = c.sub, fontSize = 12.sp)
                }
                Switch(o.timerAutoStop, { v -> metronome.updateOptions { it.copy(timerAutoStop = v) } }, colors = SwitchDefaults.colors(checkedTrackColor = c.green, checkedThumbColor = Color.White, checkedBorderColor = c.green))
            }
        }
    }
}

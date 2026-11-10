package com.example.tunebeatchord.ui.metronome

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.metronome.MetronomeController
import com.example.tunebeatchord.metronome.TempoTerm
import com.example.tunebeatchord.rhythm.AccentLevel
import com.example.tunebeatchord.ui.components.Card
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.ScreenTitle
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.roundToInt

private enum class Sheet { RHYTHM, SOUND }

@Composable
fun MetronomeScreen(controller: MetronomeController, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    var editing by remember { mutableStateOf(false) }

    // 当前拍高亮：每一帧按音频时钟更新
    LaunchedEffect(controller.isPlaying) {
        while (controller.isPlaying) {
            androidx.compose.runtime.withFrameNanos { controller.tick(it) }
        }
    }
    LaunchedEffect(controller.notice) { }

    Column(modifier.verticalScroll(rememberScrollState())) {
        ScreenTitle(tr("节拍器"))
        controller.notice?.let { n ->
            val text = when (n) {
                MetronomeController.Notice.RAMP_FINISHED -> tr("渐进提速完成，已停止")
                MetronomeController.Notice.TIMER_REACHED -> tr("练习目标完成")
                MetronomeController.Notice.TIMER_REACHED_STOPPED -> tr("练习目标完成")
            }
            Box(Modifier.padding(horizontal = 20.dp, vertical = 4.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accentTint).clickable { controller.notice = null }.padding(12.dp)) {
                Text(text, color = c.accent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
            TempoDial(controller, onEdit = { editing = true })
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            RepeatButton("−", enabled = !controller.rampControlsTempo, description = tr("减慢")) { controller.nudgeBpm(-1) }
            Box(
                Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(26.dp)).background(c.card2)
                    .clickable(enabled = !controller.rampControlsTempo) { controller.tap() }
                    .semantics { contentDescription = strings.t("TAP 测速") },
                contentAlignment = Alignment.Center,
            ) { Text("TAP", color = if (controller.rampControlsTempo) c.dim else c.text, fontSize = 18.sp, fontWeight = FontWeight.Bold) }
            RepeatButton("+", enabled = !controller.rampControlsTempo, description = tr("加快")) { controller.nudgeBpm(1) }
        }
        BeatBoxes(controller)
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val cfg = controller.config
            Chip("${cfg.timeSignature.displayName}  ·  ${tr(cfg.subdivision.title)}", false, { sheet = Sheet.RHYTHM }, Modifier.weight(1f), height = 48.dp, fontSize = 15)
            Chip(tr(cfg.sound.title), false, { sheet = Sheet.SOUND }, Modifier.weight(1f), height = 48.dp, fontSize = 15)
        }
        Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
            val desc = if (controller.isPlaying) tr("暂停") else tr("播放")
            Box(
                Modifier.size(88.dp).clip(CircleShape).background(c.accentBrush)
                    .semantics { contentDescription = desc }.clickable { controller.toggle() },
                contentAlignment = Alignment.Center,
            ) {
                Canvas(Modifier.size(34.dp)) {
                    if (controller.isPlaying) {
                        drawRoundRect(c.onAccent, Offset(size.width * 0.12f, 0f), Size(size.width * 0.28f, size.height), androidx.compose.ui.geometry.CornerRadius(4f))
                        drawRoundRect(c.onAccent, Offset(size.width * 0.60f, 0f), Size(size.width * 0.28f, size.height), androidx.compose.ui.geometry.CornerRadius(4f))
                    } else {
                        drawPath(Path().apply { moveTo(size.width * 0.18f, 0f); lineTo(size.width, size.height / 2); lineTo(size.width * 0.18f, size.height); close() }, c.onAccent)
                    }
                }
            }
        }
        Box(Modifier.height(24.dp))
    }

    when (sheet) {
        Sheet.RHYTHM -> RhythmSheet(controller) { sheet = null }
        Sheet.SOUND -> SoundSheet(controller) { sheet = null }
        null -> {}
    }
    if (editing) BpmDialog(controller.bpm.roundToInt(), onDismiss = { editing = false }) { controller.setBpm(it.toDouble()); editing = false }
}

/** 长按连续加减的按钮。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RepeatButton(label: String, enabled: Boolean, description: String, onStep: () -> Unit) {
    val c = AppTheme.colors
    var pressed by remember { mutableStateOf(false) }
    LaunchedEffect(pressed) {
        if (pressed) {
            kotlinx.coroutines.delay(350)
            var interval = 140L
            while (pressed) {
                onStep(); kotlinx.coroutines.delay(interval); if (interval > 40) interval -= 10
            }
        }
    }
    Box(
        Modifier.size(52.dp).clip(CircleShape).background(c.card2).semantics { contentDescription = description }
            .pointerInput(enabled) {
                if (enabled) detectTapGestures(
                    onPress = { onStep(); pressed = true; try { tryAwaitRelease() } finally { pressed = false } },
                )
            },
        contentAlignment = Alignment.Center,
    ) { Text(label, color = if (enabled) c.text else c.dim, fontSize = 26.sp, fontWeight = FontWeight.Medium) }
}

/** 速度圆环：拖一圈是 60 BPM；点数字可以直接输入。 */
@Composable
private fun TempoDial(controller: MetronomeController, onEdit: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val enabled = !controller.rampControlsTempo
    val shown = if (controller.isPlaying) controller.liveBpm else controller.bpm
    var lastAngle by remember { mutableStateOf<Double?>(null) }
    var accumulated by remember { mutableStateOf(0.0) }
    Box(
        Modifier.size(260.dp).pointerInput(enabled) {
            if (!enabled) return@pointerInput
            detectDragGestures(
                onDragStart = { lastAngle = null; accumulated = 0.0 },
                onDragEnd = { lastAngle = null },
            ) { change, _ ->
                val center = Offset(size.width / 2f, size.height / 2f)
                val angle = atan2((change.position.y - center.y).toDouble(), (change.position.x - center.x).toDouble())
                val prev = lastAngle
                lastAngle = angle
                if (prev != null) {
                    var d = angle - prev
                    if (d > PI) d -= 2 * PI
                    if (d < -PI) d += 2 * PI
                    accumulated += d / (2 * PI) * 60
                    val steps = accumulated.toInt()
                    if (steps != 0) {
                        accumulated -= steps
                        controller.setBpm(Math.round(controller.bpm) + steps.toDouble())
                    }
                }
            }
        },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(260.dp)) {
            val stroke = 16.dp.toPx()
            val inset = stroke / 2
            drawCircle(c.track, radius = size.minDimension / 2 - inset, style = Stroke(stroke))
            val fraction = ((shown - 20) % 60) / 60.0
            drawArc(
                Brush.sweepGradient(listOf(c.accentLight, c.accentDark, c.accentLight)), startAngle = -90f, sweepAngle = (fraction * 360).toFloat().coerceAtLeast(4f), useCenter = false,
                topLeft = Offset(inset, inset), size = Size(size.width - stroke, size.height - stroke), style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                shown.roundToInt().toString(), color = c.text, fontSize = 72.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable(enabled = enabled) { onEdit() }.semantics { contentDescription = strings.t("%lld BPM，点按输入速度", shown.roundToInt()) },
            )
            Text("BPM", color = c.sub, fontSize = 15.sp)
            Text(TempoTerm.name(shown) { strings.t(it) }, color = c.accent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun BpmDialog(current: Int, onDismiss: () -> Unit, onConfirm: (Int) -> Unit) {
    var text by remember { mutableStateOf(current.toString()) }
    val value = text.toIntOrNull()
    val valid = value != null && value in 20..400
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("输入速度")) },
        text = {
            Column {
                TextField(text, { text = it.filter(Char::isDigit).take(3) }, singleLine = true, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number))
                Text(if (valid || text.isEmpty()) tr("范围 20–400 BPM") else tr("请输入 20–400 之间的数"), modifier = Modifier.padding(top = 8.dp), fontSize = 13.sp)
            }
        },
        confirmButton = { TextButton(enabled = valid, onClick = { onConfirm(value!!) }) { Text(tr("确定")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } },
    )
}

/** 一小节的拍子方块：点按循环 强→次强→弱→静音；方块里按切分分格，正在响的那一格保持原色、其余变淡。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BeatBoxes(controller: MetronomeController) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val cfg = controller.config
    val n = cfg.timeSignature.beatsPerBar
    val offsets = cfg.subdivision.offsets
    val weights = offsets.indices.map { i -> ((offsets.getOrNull(i + 1) ?: 1.0) - offsets[i]).toFloat() }
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        (0 until n).chunked(8).forEach { rowBeats ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (beat in rowBeats) {
                    val level = cfg.accents[beat]
                    val playingBeat = controller.isPlaying && controller.currentBeat == beat
                    val base: Color = when (level) {
                        AccentLevel.STRONG -> c.accent
                        AccentLevel.MEDIUM -> c.accent.copy(alpha = 0.6f)
                        AccentLevel.WEAK -> c.weak
                        AccentLevel.MUTED -> Color.Transparent
                    }
                    Row(
                        Modifier.weight(1f).height(if (n > 8) 56.dp else 72.dp).clip(RoundedCornerShape(14.dp))
                            .border(if (level == AccentLevel.MUTED) 1.5.dp else 0.dp, c.dim, RoundedCornerShape(14.dp))
                            .combinedClickable(onClick = { controller.cycleAccent(beat) })
                            .semantics { contentDescription = strings.t("第 %lld 拍，%@", beat + 1, strings.t(levelTitle(level))) },
                        horizontalArrangement = Arrangement.spacedBy(if (weights.size > 2 && n > 6) 1.dp else 2.dp),
                    ) {
                        weights.forEachIndexed { i, w ->
                            val sounding = playingBeat && (controller.currentSub == i)
                            val dim = controller.isPlaying && !sounding
                            Box(
                                Modifier.weight(w).height(if (n > 8) 56.dp else 72.dp).background(
                                    if (level == AccentLevel.MUTED) Color.Transparent else if (dim) base.copy(alpha = base.alpha * 0.45f) else base,
                                ),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (i == 0) Text("${beat + 1}", color = if (level == AccentLevel.MUTED) c.dim else if (level == AccentLevel.WEAK) c.text else c.onAccent, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
                repeat((if (n <= 8) n else 8) - rowBeats.size) { Box(Modifier.weight(1f)) }
            }
        }
        Text(tr("点按方块切换重音：强 · 次强 · 弱 · 静音"), color = c.dim, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp))
    }
}

internal fun levelTitle(level: AccentLevel) = when (level) {
    AccentLevel.STRONG -> "强"
    AccentLevel.MEDIUM -> "次强"
    AccentLevel.WEAK -> "弱"
    AccentLevel.MUTED -> "静音"
}

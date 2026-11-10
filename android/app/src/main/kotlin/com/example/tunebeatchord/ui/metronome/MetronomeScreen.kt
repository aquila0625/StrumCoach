package com.example.tunebeatchord.ui.metronome

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.metronome.MetronomeController
import com.example.tunebeatchord.metronome.TempoTerm
import com.example.tunebeatchord.rhythm.AccentLevel
import com.example.tunebeatchord.rhythm.Subdivision
import com.example.tunebeatchord.ui.components.CardBox
import com.example.tunebeatchord.ui.components.NoteGlyph
import com.example.tunebeatchord.ui.components.PlayPauseIcon
import com.example.tunebeatchord.ui.components.glyph
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

private enum class Sheet { RHYTHM, SOUND, BPM }

/** 节拍器主界面，布局和 iOS 版一致：标题、拍子方块卡片、速度圆环、三个卡片按钮（拍号 / 切分 / 音色）、TAP · 播放 · 计时。 */
@Composable
fun MetronomeScreen(controller: MetronomeController, onOpenTraining: () -> Unit = {}, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var sheet by remember { mutableStateOf<Sheet?>(null) }

    // 当前拍高亮和计时：每一帧按音频时钟更新
    LaunchedEffect(controller.isPlaying) {
        while (controller.isPlaying) androidx.compose.runtime.withFrameNanos { controller.tick(it) }
    }

    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
        TopBar(controller, onOpenTraining)
        BeatBlocks(controller)
        TempoDial(controller, onTapNumber = { sheet = Sheet.BPM })
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val cfg = controller.config
            ChipCard(tr("拍号"), { sheet = Sheet.RHYTHM }, Modifier.weight(1f)) {
                Text(cfg.timeSignature.displayName, color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
            ChipCard(strings.t("%@切分", strings.t(cfg.subdivision.title)), { sheet = Sheet.RHYTHM }, Modifier.weight(1f)) {
                Box(Modifier.height(36.dp), contentAlignment = Alignment.Center) { NoteGlyph(cfg.subdivision.glyph, c.text, gap = 9f) }
            }
            ChipCard(tr("音色"), { sheet = Sheet.SOUND }, Modifier.weight(1f)) {
                Text(tr(cfg.sound.title), color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 34.dp).padding(top = 22.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            SideButton("TAP", tr("测速"), onClick = { controller.tap() }, description = strings.t("TAP 测速"))
            PlayButton(controller.isPlaying) { controller.toggle() }
            val s = controller.elapsedSeconds
            val timerText = if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
            SideButton(timerText, tr("计时"), onClick = { controller.resetTimer() }, description = strings.t("计时 %@", timerText), mono = true)
        }
    }

    when (sheet) {
        Sheet.RHYTHM -> RhythmSheet(controller) { sheet = null }
        Sheet.SOUND -> SoundSheet(controller) { sheet = null }
        Sheet.BPM -> BpmSheet(controller) { sheet = null }
        null -> {}
    }
}

@Composable
private fun TopBar(controller: MetronomeController, onOpenTraining: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val o = controller.options
    val label = when {
        o.rampEnabled && o.muteEnabled -> strings.t("提速 + 静音")
        o.rampEnabled -> strings.t("渐进提速")
        o.muteEnabled -> strings.t("静音小节")
        else -> null
    }
    Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(tr("节拍器"), color = c.text, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        if (label != null) {
            Box(
                Modifier.padding(start = 8.dp).height(24.dp).clip(RoundedCornerShape(50)).background(c.accentTint).clickable { onOpenTraining() }.padding(horizontal = 9.dp),
                contentAlignment = Alignment.Center,
            ) { Text(label, color = c.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold) }
        }
    }
}

// 拍子方块 ---------------------------------------------------------------

/** 一小节的拍子方块：强一整格高、次强 66%、弱和静音 40%（像台阶）；静音是虚线框；点按循环 强→次强→弱→静音。 */
@Composable
private fun BeatBlocks(controller: MetronomeController) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val cfg = controller.config
    val count = cfg.accents.count
    val gap = if (count > 8) 4.dp else if (count > 6) 6.dp else 10.dp
    val radius = if (count > 8) 6.dp else 10.dp
    Box(Modifier.padding(horizontal = 20.dp).padding(top = 10.dp)) {
        CardBox(Modifier.fillMaxWidth(), radius = 20.dp) {
            Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 12.dp)) {
                Row(Modifier.fillMaxWidth().height(96.dp), horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.Bottom) {
                    for (i in 0 until count) {
                        val accent = cfg.accents[i]
                        val isNow = controller.currentBeat == i
                        Box(
                            Modifier.weight(1f).fillMaxSize()
                                .pointerInput(i) { detectTapGestures { controller.cycleAccent(i) } }
                                .semantics { contentDescription = strings.t("第 %lld 拍，%@", i + 1, strings.t(levelTitle(accent))) },
                            contentAlignment = Alignment.BottomCenter,
                        ) {
                            BeatBlock(accent, isNow, radius, cfg.subdivision, if (isNow && controller.isPlaying) controller.currentSub else null)
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (i in 0 until count) {
                        val on = controller.currentBeat == i
                        Text(
                            "${i + 1}", color = if (on) c.text else c.sub, fontSize = if (count > 12) 11.sp else 13.sp,
                            fontWeight = if (on) FontWeight.Bold else FontWeight.Normal, textAlign = TextAlign.Center, modifier = Modifier.weight(1f),
                        )
                    }
                }
                Text(
                    tr("点按方块切换重音：强 · 次强 · 弱 · 静音"), color = c.dim, fontSize = 12.sp, textAlign = TextAlign.Center, maxLines = 2,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun BeatBlock(accent: AccentLevel, isNow: Boolean, radius: Dp, pattern: Subdivision, activeSub: Int?) {
    val c = AppTheme.colors
    val shape = RoundedCornerShape(radius)
    val fraction = when (accent) {
        AccentLevel.STRONG -> 1f
        AccentLevel.MEDIUM -> 0.66f
        AccentLevel.WEAK, AccentLevel.MUTED -> 0.40f
    }
    val fill: Color = when (accent) {
        AccentLevel.STRONG -> c.accent
        AccentLevel.MEDIUM -> c.accent.copy(alpha = 0.6f)
        AccentLevel.WEAK -> if (isNow) c.weakNow else c.weak
        AccentLevel.MUTED -> Color.Transparent
    }
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        val h = maxHeight * fraction
        val muted = accent == AccentLevel.MUTED
        Box(
            Modifier.fillMaxWidth().height(h)
                // 正在响的拍：外面一圈 3 点的底色空隙加 2 点描边（和 iOS 版一样）
                .then(if (isNow) Modifier.border(2.dp, c.text, RoundedCornerShape(radius + 4.dp)).padding(5.dp) else Modifier),
        ) {
            Box(
                Modifier.fillMaxSize().clip(shape).background(fill)
                    .then(
                        if (muted) Modifier.drawBehind {
                            drawRoundRect(c.weak, cornerRadius = CornerRadius(radius.toPx()), style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
                        } else Modifier,
                    ),
            ) { SubdivisionCells(pattern, activeSub, filled = !muted) }
        }
    }
}

/** 方块里按切分分格（附点 3:1、前八后十六 2:1:1……）；正在响的那一格保持原色，其余变淡；格子很窄时分隔变成细线。 */
@Composable
private fun SubdivisionCells(pattern: Subdivision, active: Int?, filled: Boolean) {
    val c = AppTheme.colors
    val n = pattern.clickCount
    if (n <= 1) return
    Canvas(Modifier.fillMaxSize()) {
        val narrowest = (0 until n).minOf { i -> (if (i + 1 < n) pattern.offset(i + 1) else 1.0) - pattern.offset(i) }
        val w = size.width / density * narrowest
        val line = (if (w >= 14) 3 else if (w >= 7) 2 else 1) * density
        if (active != null && active < n) {
            for (i in 0 until n) {
                val start = pattern.offset(i)
                val end = if (i + 1 < n) pattern.offset(i + 1) else 1.0
                val x = (size.width * start).toFloat()
                val wd = (size.width * (end - start)).toFloat()
                if (filled) {
                    if (i == active) {
                        if (!c.isLight) drawRect(Color.White.copy(alpha = 0.22f), Offset(x, 0f), Size(wd, size.height))
                    } else drawRect(c.bgBottom.copy(alpha = if (c.isLight) 0.42f else 0.5f), Offset(x, 0f), Size(wd, size.height))
                } else if (i == active) drawRect(c.weak.copy(alpha = 0.6f), Offset(x, 0f), Size(wd, size.height))
            }
        }
        for (i in 1 until n) {
            val x = (size.width * pattern.offset(i)).toFloat()
            drawRect(if (filled) c.bgBottom else c.weak, Offset(x - line / 2, 0f), Size(line, size.height))
        }
    }
}

// 速度圆环 ---------------------------------------------------------------

/** 270 点的圆环：300° 的刻度和弧，旋钮是白色圆加主色圆点；拖一圈是 60 BPM；点数字输入；左右下角是 − / +。 */
@Composable
private fun TempoDial(controller: MetronomeController, onTapNumber: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val enabled = !controller.rampControlsTempo
    val shown = (if (controller.isPlaying) controller.liveBpm else controller.bpm).roundToInt()
    var startBpm by remember { mutableStateOf<Int?>(null) }
    var lastAngle by remember { mutableStateOf(0.0) }
    var accumulated by remember { mutableStateOf(0.0) }
    Box(Modifier.fillMaxWidth().height(282.dp), contentAlignment = Alignment.TopCenter) {
        Box(
            Modifier.padding(top = 6.dp).size(270.dp).pointerInput(enabled) {
                if (!enabled) return@pointerInput
                detectDragGestures(
                    onDragStart = { start ->
                        val ctr = Offset(size.width / 2f, size.height / 2f)
                        startBpm = controller.bpm.roundToInt()
                        lastAngle = atan2((start.y - ctr.y).toDouble(), (start.x - ctr.x).toDouble()) * 180 / PI
                        accumulated = 0.0
                    },
                    onDragEnd = { startBpm = null },
                    onDragCancel = { startBpm = null },
                ) { change, _ ->
                    val ctr = Offset(size.width / 2f, size.height / 2f)
                    val angle = atan2((change.position.y - ctr.y).toDouble(), (change.position.x - ctr.x).toDouble()) * 180 / PI
                    var delta = angle - lastAngle
                    if (delta > 180) delta -= 360
                    if (delta < -180) delta += 360
                    accumulated += delta
                    lastAngle = angle
                    val base = startBpm ?: return@detectDragGestures
                    val target = (base + accumulated / 360 * 60).roundToInt().coerceIn(20, 400)
                    if (target != controller.bpm.roundToInt()) controller.setBpm(target.toDouble())
                }
            },
        ) { DialFace((shown - 20) / 380.0) }
        Column(
            Modifier.fillMaxSize().padding(top = 6.dp).clickable(enabled = enabled, indication = null, interactionSource = remember { MutableInteractionSource() }) { onTapNumber() },
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
        ) {
            Text(
                "$shown", color = c.text, fontSize = 92.sp, fontWeight = FontWeight.Thin, letterSpacing = (-2).sp, maxLines = 1,
                modifier = Modifier.semantics { contentDescription = strings.t("%lld BPM，点按输入速度", shown) },
            )
            Text("BPM", color = c.sub, fontSize = 12.sp, letterSpacing = 3.sp, modifier = Modifier.padding(top = 4.dp))
            Text(
                if (controller.rampControlsTempo) tr("渐进提速控制中") else TempoTerm.name(shown.toDouble()) { strings.t(it) },
                color = c.accent, fontSize = 15.sp, maxLines = 1, modifier = Modifier.padding(top = 8.dp).width(190.dp), textAlign = TextAlign.Center,
            )
        }
        Row(
            Modifier.fillMaxSize().padding(horizontal = 22.dp).padding(bottom = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom,
        ) {
            StepButton("−", tr("减慢"), enabled) { controller.nudgeBpm(-1) }
            StepButton("+", tr("加快"), enabled) { controller.nudgeBpm(1) }
        }
    }
}

@Composable
private fun DialFace(value: Double) {
    val c = AppTheme.colors
    Canvas(Modifier.fillMaxSize()) {
        val d = density
        val cx = size.width / 2
        val r = 116 * d
        val start = -150.0
        val span = 300.0
        fun pt(deg: Double, rr: Float): Offset {
            val a = (deg - 90) * PI / 180
            return Offset(cx + rr * cos(a).toFloat(), cx + rr * sin(a).toFloat())
        }
        var deg = start
        while (deg <= start + span + 0.1) {
            val major = ((deg - start).roundToInt()) % 30 == 0
            drawLine(if (major) c.dim else c.tick, pt(deg, r + 12 * d), pt(deg, r + (if (major) 22 else 17) * d), strokeWidth = (if (major) 2f else 1.4f) * d, cap = StrokeCap.Round)
            deg += 5
        }
        val stroke = Stroke(12 * d, cap = StrokeCap.Round)
        val topLeft = Offset(cx - r, cx - r)
        val arcSize = Size(r * 2, r * 2)
        drawArc(c.track, (start - 90).toFloat(), span.toFloat(), false, topLeft, arcSize, style = stroke)
        val end = start + span * value.coerceIn(0.0, 1.0)
        drawArc(
            Brush.sweepGradient(listOf(c.accentLight, c.accent, c.accentDark, c.accentLight)), (start - 90).toFloat(),
            (end - start).toFloat().coerceAtLeast(0.5f), false, topLeft, arcSize, style = stroke,
        )
        val k = pt(end, r)
        drawCircle(Color.White, 14 * d, k)
        if (c.isLight) drawCircle(Color.Black.copy(alpha = 0.14f), 14 * d, k, style = Stroke(1.5f * d))
        drawCircle(c.accent, 5 * d, k)
    }
}

@Composable
private fun StepButton(symbol: String, label: String, enabled: Boolean, onStep: () -> Unit) {
    val c = AppTheme.colors
    var pressed by remember { mutableStateOf(false) }
    LaunchedEffect(pressed) {
        if (pressed) {
            kotlinx.coroutines.delay(400)
            var interval = 140L
            while (pressed) {
                onStep(); kotlinx.coroutines.delay(interval); interval = (interval * 0.9).toLong().coerceAtLeast(25)
            }
        }
    }
    Box(
        Modifier.size(52.dp).alpha(if (enabled) 1f else 0.4f).clip(CircleShape).background(c.card).border(1.dp, c.line, CircleShape)
            .semantics { contentDescription = label }
            .pointerInput(enabled) {
                if (enabled) detectTapGestures(onPress = { onStep(); pressed = true; try { tryAwaitRelease() } finally { pressed = false } })
            },
        contentAlignment = Alignment.Center,
    ) { Text(symbol, color = c.text, fontSize = 28.sp, fontWeight = FontWeight.Light) }
}

// 按钮 -------------------------------------------------------------------

@Composable
private fun ChipCard(caption: String, onClick: () -> Unit, modifier: Modifier, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    CardBox(modifier.height(62.dp).clickable(onClick = onClick), radius = 16.dp) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(0.dp, Alignment.CenterVertically)) {
            content()
            Text(caption, color = c.sub, fontSize = 11.sp, maxLines = 1)
        }
    }
}

@Composable
private fun SideButton(title: String, caption: String, onClick: () -> Unit, description: String, mono: Boolean = false) {
    val c = AppTheme.colors
    CardBox(Modifier.size(72.dp, 56.dp).clickable(onClick = onClick).semantics { contentDescription = description }, radius = 28.dp, border = true) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, color = c.text, fontSize = if (mono) 14.sp else 15.sp, fontWeight = FontWeight.Bold, letterSpacing = if (mono) 0.sp else 1.sp, maxLines = 1)
            Text(caption, color = c.sub, fontSize = 10.sp, maxLines = 1)
        }
    }
}

@Composable
private fun PlayButton(playing: Boolean, onClick: () -> Unit) {
    val c = AppTheme.colors
    val desc = if (playing) tr("暂停") else tr("播放")
    Box(
        Modifier.size(92.dp).shadow(14.dp, CircleShape, ambientColor = c.accent.copy(alpha = 0.45f), spotColor = c.accent.copy(alpha = 0.45f))
            .clip(CircleShape).background(c.accentBrush).semantics { contentDescription = desc }.clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.padding(start = if (playing) 0.dp else 4.dp)) { PlayPauseIcon(playing, Color.White, 40.dp) }
    }
}

internal fun levelTitle(level: AccentLevel) = when (level) {
    AccentLevel.STRONG -> "强"
    AccentLevel.MEDIUM -> "次强"
    AccentLevel.WEAK -> "弱"
    AccentLevel.MUTED -> "静音"
}

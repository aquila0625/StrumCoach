package com.example.tunebeatchord.ui.tuner

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.tuner.InstrumentLibrary
import com.example.tunebeatchord.tuner.InstrumentString
import com.example.tunebeatchord.tuner.NoteNaming
import com.example.tunebeatchord.tuner.Pitch
import com.example.tunebeatchord.tuner.TunerController
import com.example.tunebeatchord.tuner.TunerDefaults
import com.example.tunebeatchord.tuner.TunerModel
import com.example.tunebeatchord.ui.components.CardBox
import com.example.tunebeatchord.ui.components.ChevronDown
import com.example.tunebeatchord.ui.components.noteAnnotated
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** 调音器，布局和 iOS 版（TunerView）一致：标题和设置、乐器卡片（图标 + 名字）、定弦、音分表盘、读数、弦按钮、标准音、参考音。 */
@Composable
fun TunerScreen(controller: TunerController, settings: Settings, active: Boolean, onEnter: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val context = LocalContext.current
    val model = controller.model
    val naming = settings.noteNaming()
    var denied by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var referenceOctave by remember { mutableIntStateOf(4) }

    fun hasPermission() = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        denied = !granted
        if (granted && active) controller.start()
    }

    // 进入标签时开始收音（先让节拍器停下，免得把节拍声当成弦的声音），离开或退到后台时停止
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(active, lifecycle) {
        var resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        fun sync() {
            if (active && resumed) {
                onEnter()
                if (hasPermission()) { denied = false; controller.start() } else launcher.launch(Manifest.permission.RECORD_AUDIO)
            } else controller.stop()
        }
        val observer = LifecycleEventObserver { _, _ -> resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED); sync() }
        lifecycle.addObserver(observer)
        sync()
        onDispose { lifecycle.removeObserver(observer); controller.stop() }
    }
    LaunchedEffect(model.a4) { settings.updateA4(model.a4) }

    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        // 顶栏
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("调音器"), color = c.text, fontSize = 34.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Box {
                Box(
                    Modifier.size(40.dp).clip(CircleShape).background(c.card).clickable { showSettings = true }
                        .semantics { contentDescription = strings.t("调音器设置") },
                    contentAlignment = Alignment.Center,
                ) { SlidersIcon(c.text) }
                DropdownMenu(showSettings, { showSettings = false }, containerColor = c.sheet) {
                    Row(Modifier.width(280.dp).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(tr("调准提示音"), color = c.text, fontSize = 16.sp)
                            Text(tr("调准一根弦时播放“叮咚”提示音"), color = c.sub, fontSize = 12.sp)
                        }
                        Switch(model.tuneChimeEnabled, { model.setTuneChime(it) })
                    }
                }
            }
        }

        // 乐器：一排带图标的卡片，可左右滑动
        Row(Modifier.padding(top = 14.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            InstrumentLibrary.all.forEach { inst ->
                val on = inst.id == model.instrument.id
                Column(
                    Modifier.size(70.dp).clip(RoundedCornerShape(14.dp)).background(if (on) c.accent else c.cardTop).clickable {
                        if (model.playingReference != null) model.stopReference()
                        model.select(inst)
                    }.semantics { contentDescription = strings.t(inst.name) },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    InstrumentIcon(inst.family, if (on) c.onAccent else c.text, 38.dp)
                    Text(
                        tr(inst.name), color = if (on) c.onAccent else c.sub, fontSize = 11.sp,
                        fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1, modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }
        // 定弦：下拉菜单
        if (model.instrument.tunings.size > 1) {
            var menu by remember { mutableStateOf(false) }
            Box(Modifier.padding(horizontal = 20.dp).padding(top = 10.dp)) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.cardTop).clickable { menu = true }.padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(tr("定弦"), color = c.sub, fontSize = 11.sp)
                        Text(noteAnnotated(tr(model.tuning.name)), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                    ChevronDown(c.sub)
                }
                DropdownMenu(menu, { menu = false }, containerColor = c.sheet) {
                    model.instrument.tunings.forEach { t ->
                        DropdownMenuItem(
                            text = { Text((if (t.id == model.tuning.id) "✓  " else "     ") + tr(t.name), color = c.text) },
                            onClick = { model.select(t); menu = false },
                        )
                    }
                }
            }
        }
        when {
            denied -> Banner(tr("没有麦克风权限。请到系统设置里允许本 App 使用麦克风。"))
            model.errorMessage != null -> Banner(strings.t("无法打开麦克风：%@", model.errorMessage ?: ""))
        }

        Box(Modifier.padding(horizontal = 20.dp).padding(top = 6.dp)) { Gauge(model.result?.cents, strings.t("音分表盘")) }
        Readout(model, naming)
        if (!model.tuning.isChromatic) StringRow(model, naming)
        A4Card(model, naming)
        ReferenceSection(model, naming, referenceOctave, onOctave = { referenceOctave = it })
    }
}

@Composable
private fun Banner(text: String) {
    val c = AppTheme.colors
    Box(Modifier.padding(horizontal = 20.dp).padding(top = 12.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.cardTop).padding(14.dp)) {
        Text(text, color = c.text, fontSize = 14.sp)
    }
}

@Composable
private fun SlidersIcon(color: Color) {
    Canvas(Modifier.size(20.dp)) {
        val s = size.width
        for ((i, knob) in listOf(0.3f, 0.7f, 0.45f).withIndex()) {
            val y = s * (0.2f + i * 0.3f)
            drawLine(color, Offset(s * 0.08f, y), Offset(s * 0.92f, y), strokeWidth = s * 0.08f, cap = StrokeCap.Round)
            drawCircle(color, s * 0.1f, Offset(s * knob, y))
        }
    }
}

// 表盘 ---------------------------------------------------------------------

/** 音分表盘：−50…+50 音分，每 5 音分一条刻度、每 25 一条长刻度带数字，±5 内是绿色，指针按 1.2°/音分摆动。 */
@Composable
private fun Gauge(cents: Double?, description: String) {
    val c = AppTheme.colors
    val inTune = cents?.let { abs(it) <= TunerDefaults.IN_TUNE_CENTS } == true
    val target = (cents ?: 0.0).coerceIn(-50.0, 50.0).toFloat() * 1.2f
    val angle by animateFloatAsState(target, spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessMediumLow), label = "needle")
    val needleColor by animateColorAsState(if (cents == null) c.weak else if (inTune) c.green else c.accent, label = "needleColor")
    Canvas(Modifier.fillMaxWidth().aspectRatio(340f / 230f).semantics { contentDescription = description }) {
        val k = size.width / 340f
        val cx = 170f
        val cy = 210f
        val r = 160f
        fun point(deg: Double, radius: Float): Offset {
            val a = (deg - 90) * PI / 180
            return Offset((cx + radius * cos(a).toFloat()) * k, (cy + radius * sin(a).toFloat()) * k)
        }
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = c.dim.toArgb(); textSize = 12f * k * 1f; textAlign = android.graphics.Paint.Align.CENTER
        }
        for (v in -50..50 step 5) {
            val d = v * 1.2
            val major = v % 25 == 0
            val tickColor = if (abs(v) <= 5) c.green else if (major) c.sub else c.weak
            drawLine(tickColor, point(d, r), point(d, r - if (major) 22 else 13), strokeWidth = (if (major) 2.5f else 1.6f) * k, cap = StrokeCap.Round)
            if (major) {
                val label = if (v > 0) "+$v" else if (v < 0) "−${-v}" else "0"
                val p = point(d, r - 40)
                drawContext.canvas.nativeCanvas.drawText(label, p.x, p.y + 4 * k, paint)
            }
        }
        // 准音区弧线
        drawArc(
            c.green.copy(alpha = 0.9f), -90f - 6f - 0f, 12f, false,
            topLeft = Offset((cx - (r + 10)) * k, (cy - (r + 10)) * k), size = androidx.compose.ui.geometry.Size((r + 10) * 2 * k, (r + 10) * 2 * k),
            style = Stroke(6 * k, cap = StrokeCap.Round),
        )
        // 指针
        rotate(angle, pivot = Offset(cx * k, cy * k)) {
            drawLine(needleColor, Offset(cx * k, cy * k), Offset(cx * k, (cy - (r - 8)) * k), strokeWidth = 3 * k, cap = StrokeCap.Round)
            drawCircle(needleColor, 8 * k, Offset(cx * k, cy * k))
        }
    }
}

@Composable
private fun Readout(model: TunerModel, naming: NoteNaming) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val result = model.result
    val shown = model.reading ?: model.lastReading
    val live = model.reading != null
    val target = result?.target ?: shown?.pitch
    val inTune = result?.isInTune == true
    Column(Modifier.fillMaxWidth().padding(top = 0.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.height(104.dp).alpha(if (live) 1f else 0.35f), verticalAlignment = Alignment.Top) {
            Text(
                if (target != null) noteAnnotated(naming.name(target)) else noteAnnotated("–"),
                color = c.text, fontSize = 96.sp, fontWeight = FontWeight.Light, maxLines = 1,
            )
            if (target != null) Text("${target.octave}", color = c.sub, fontSize = 28.sp, modifier = Modifier.padding(top = 18.dp, start = 2.dp))
        }
        val status = when {
            result == null -> if (model.isRunning) strings.t("请弹奏一根弦") else strings.t("正在启动麦克风…")
            else -> {
                val cents = result.cents.roundToInt()
                val sign = if (cents > 0) "+" else if (cents < 0) "−" else ""
                val tail = if (result.isInTune) strings.t("已准") else if (result.isFlat) strings.t("偏低") else strings.t("偏高")
                "$sign${abs(cents)} ${strings.t("音分")} · $tail"
            }
        }
        Text(
            status, color = if (inTune) c.green else if (live) c.text else c.sub, fontSize = 20.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 6.dp),
        )
        Text(
            if (live) "${"%.1f".format(model.reading?.frequency ?: 0.0)} Hz" else " ",
            color = c.sub, fontSize = 15.sp, modifier = Modifier.padding(top = 6.dp),
        )
    }
}

// 弦按钮 -------------------------------------------------------------------

@Composable
private fun StringRow(model: TunerModel, naming: NoteNaming) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    Column(Modifier.padding(top = 22.dp)) {
        Text(tr("弦（点按锁定，再点解锁）"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 0.dp).padding(bottom = 8.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            model.tuning.strings.forEach { s -> StringButton(s, model, naming, Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun StringButton(s: InstrumentString, model: TunerModel, naming: NoteNaming, modifier: Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val isTarget = model.result?.stringIndex == s.index
    val isLocked = model.lockedString == s.index
    val tuned = s.index in model.tunedStrings
    val highlighted = isTarget || isLocked
    val textColor = if (highlighted) c.onAccent else if (tuned) c.green else c.text
    Box(
        modifier.heightIn(min = 56.dp).clip(RoundedCornerShape(12.dp)).background(if (highlighted) c.accent else c.cardTop)
            .clickable { model.lockString(s.index) }
            .semantics { contentDescription = strings.t("第 %lld 弦，%@", s.number, naming.fullName(s.pitch)) },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(noteAnnotated(naming.name(s.pitch)), color = textColor, fontSize = 19.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text("${s.pitch.octave}", color = textColor.copy(alpha = 0.7f), fontSize = 10.sp, modifier = Modifier.padding(bottom = 3.dp, start = 1.dp))
            }
            Text("${s.number}", color = textColor.copy(alpha = 0.55f), fontSize = 10.sp)
        }
        if (tuned) Box(Modifier.align(Alignment.TopEnd).padding(4.dp)) { TunedBadge(if (highlighted) c.onAccent else c.green, if (highlighted) c.accent else Color.White) }
        else if (isLocked) Box(Modifier.align(Alignment.TopEnd).padding(5.dp)) { LockIcon(c.onAccent) }
        if (tuned && isLocked) Box(Modifier.align(Alignment.TopStart).padding(5.dp)) { LockIcon(c.onAccent) }
    }
}

@Composable
private fun TunedBadge(fill: Color, mark: Color) {
    Canvas(Modifier.size(17.dp)) {
        drawCircle(fill)
        val s = size.width
        val p = androidx.compose.ui.graphics.Path().apply {
            moveTo(s * 0.3f, s * 0.52f); lineTo(s * 0.44f, s * 0.66f); lineTo(s * 0.72f, s * 0.34f)
        }
        drawPath(p, mark, style = Stroke(s * 0.13f, cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
    }
}

@Composable
private fun LockIcon(color: Color) {
    Canvas(Modifier.size(9.dp)) {
        val s = size.width
        drawRoundRect(color, Offset(s * 0.1f, s * 0.42f), androidx.compose.ui.geometry.Size(s * 0.8f, s * 0.54f), androidx.compose.ui.geometry.CornerRadius(s * 0.12f))
        drawArc(color, 180f, 180f, false, Offset(s * 0.25f, s * 0.05f), androidx.compose.ui.geometry.Size(s * 0.5f, s * 0.7f), style = Stroke(s * 0.14f))
    }
}

// 标准音、参考音 -----------------------------------------------------------

@Composable
private fun A4Card(model: TunerModel, naming: NoteNaming) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    Box(Modifier.padding(horizontal = 20.dp).padding(top = 22.dp)) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(c.cardTop).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                androidx.compose.ui.text.buildAnnotatedString {
                    append(strings.t("标准音") + " ")
                    pushStyle(androidx.compose.ui.text.SpanStyle(fontWeight = FontWeight.Bold))
                    append("${naming.fullName(Pitch(69))} = ${model.a4.roundToInt()} Hz")
                    pop()
                },
                color = c.text, fontSize = 15.sp, modifier = Modifier.weight(1f),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RoundStep("−", model.a4 > TunerDefaults.a4Range.start, 34) { model.adjustA4(-1.0) }
                RoundStep("+", model.a4 < TunerDefaults.a4Range.endInclusive, 34) { model.adjustA4(1.0) }
            }
        }
    }
}

@Composable
private fun RoundStep(symbol: String, enabled: Boolean, size: Int, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(c.card2).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(symbol, color = if (enabled) c.text else c.dim, fontSize = (size * 0.5).sp, fontWeight = FontWeight.SemiBold) }
}

@Composable
private fun ReferenceSection(model: TunerModel, naming: NoteNaming, octave: Int, onOctave: (Int) -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val pitches = if (model.tuning.isChromatic) listOf(0, 2, 4, 5, 7, 9, 11).map { Pitch((octave + 1) * 12 + it) } else model.tuning.strings.map { it.pitch }
    Column(Modifier.padding(horizontal = 20.dp).padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("参考音（点按发声）"), color = c.sub, fontSize = 13.sp, modifier = Modifier.weight(1f))
            if (model.tuning.isChromatic) {
                Text("${strings.t("八度")} $octave", color = c.sub, fontSize = 13.sp)
                Box(Modifier.width(6.dp))
                RoundStep("−", octave > 1, 26) { onOctave(octave - 1) }
                Box(Modifier.width(6.dp))
                RoundStep("+", octave < 7, 26) { onOctave(octave + 1) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            pitches.forEach { p ->
                val on = model.playingReference == p
                Column(
                    Modifier.weight(1f).heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(if (on) c.accent else c.cardTop)
                        .clickable { model.toggleReference(p) }.semantics { contentDescription = strings.t("参考音 %@", naming.fullName(p)) },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    Text(noteAnnotated(naming.name(p)), color = if (on) c.onAccent else c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, textAlign = TextAlign.Center)
                    if (!model.tuning.isChromatic) Text("${p.octave}", color = (if (on) c.onAccent else c.text).copy(alpha = 0.6f), fontSize = 10.sp)
                }
            }
        }
    }
}

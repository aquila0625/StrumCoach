package com.example.tunebeatchord.ui.tuner

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.tuner.InstrumentLibrary
import com.example.tunebeatchord.tuner.TunerController
import com.example.tunebeatchord.tuner.TunerDefaults
import com.example.tunebeatchord.tuner.ToneTimbreChoice
import com.example.tunebeatchord.ui.components.Card
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.ScreenTitle
import com.example.tunebeatchord.ui.components.Section
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** 调音器：音名、音分表盘、各弦状态，点弦锁定，点参考音发声。只在当前标签可见时收音。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TunerScreen(controller: TunerController, settings: Settings, active: Boolean, onEnter: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val context = LocalContext.current
    val model = controller.model
    val naming = settings.noteNaming()
    var denied by remember { mutableStateOf(false) }

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
    // a4 变化同步到全局设置
    LaunchedEffect(model.a4) { settings.updateA4(model.a4) }

    Column(modifier.verticalScroll(rememberScrollState())) {
        ScreenTitle(tr("调音器"))
        FlowRow(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            InstrumentLibrary.all.forEach { inst ->
                Chip(tr(inst.name), model.instrument.id == inst.id, { model.select(inst) }, height = 40.dp, fontSize = 15)
            }
        }
        if (model.instrument.tunings.size > 1) {
            FlowRow(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                model.instrument.tunings.forEach { t -> Chip(tr(t.name), model.tuning.id == t.id, { model.select(t) }, height = 36.dp, fontSize = 14) }
            }
        }
        Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            Card(Modifier.fillMaxWidth()) { Gauge(model, naming::fullName, naming) }
        }
        when {
            denied -> Notice(tr("没有麦克风权限。请到系统设置里允许本 App 使用麦克风。"))
            model.errorMessage != null -> Notice(strings.t("无法打开麦克风：%@", model.errorMessage ?: ""))
        }
        if (!model.tuning.isChromatic) {
            Section(tr("弦（点按锁定，再点解锁）")) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    model.tuning.strings.forEach { s ->
                        StringButton(
                            label = naming.name(s.pitch), number = s.number,
                            current = model.result?.stringIndex == s.index, tuned = s.index in model.tunedStrings, locked = model.lockedString == s.index,
                        ) { model.lockString(s.index) }
                    }
                }
            }
            Section(tr("参考音（点按发声）")) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    model.tuning.strings.forEach { s ->
                        val playing = model.playingReference == s.pitch
                        Box(
                            Modifier.size(52.dp).clip(CircleShape).background(if (playing) c.accentBrush else androidx.compose.ui.graphics.Brush.verticalGradient(listOf(c.card2, c.card2)))
                                .semantics { contentDescription = strings.t("参考音 %@", naming.fullName(s.pitch)) }
                                .clickable { model.toggleReference(s.pitch) },
                            contentAlignment = Alignment.Center,
                        ) { Text(naming.name(s.pitch), color = if (playing) c.onAccent else c.text, fontSize = 17.sp, fontWeight = FontWeight.Bold) }
                    }
                }
            }
        } else {
            Section(tr("参考音（点按发声）")) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("C4", "D4", "E4", "F4", "G4", "A4", "B4").mapNotNull { com.example.tunebeatchord.tuner.Pitch.parse(it) }.forEach { p ->
                        Chip(naming.fullName(p), model.playingReference == p, { model.toggleReference(p) }, height = 40.dp, fontSize = 15)
                    }
                }
            }
        }
        Section(tr("标准音")) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Chip("−", false, { model.adjustA4(-1.0) }, Modifier.size(48.dp), 48.dp)
                Text(strings.t("标准音 %@", "A4 = ${model.a4.roundToInt()} Hz"), color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Chip("+", false, { model.adjustA4(1.0) }, Modifier.size(48.dp), 48.dp)
                if (model.a4 != TunerDefaults.A4) Chip(tr("恢复默认"), false, { model.updateA4(TunerDefaults.A4) }, height = 40.dp, fontSize = 14)
            }
        }
        Section(tr("音色与反馈")) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(tr("调准提示音"), color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    Switch(model.tuneChimeEnabled, { model.setTuneChime(it) })
                }
            }
        }
        Box(Modifier.height(24.dp))
    }
}

@Composable
private fun Notice(text: String) {
    val c = AppTheme.colors
    Box(Modifier.padding(horizontal = 20.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accentTint).padding(12.dp)) {
        Text(text, color = c.accent, fontSize = 15.sp)
    }
}

@Composable
private fun StringButton(label: String, number: Int, current: Boolean, tuned: Boolean, locked: Boolean, onClick: () -> Unit) {
    val c = AppTheme.colors
    val bg by animateColorAsState(if (tuned) c.green.copy(alpha = 0.22f) else if (current) c.accentTint else c.card2, label = "string")
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable(onClick = onClick).padding(2.dp)) {
        Box(
            Modifier.size(52.dp).clip(CircleShape).background(bg)
                .then(if (locked) Modifier.background(c.accentSoft) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            Text(label, color = if (tuned) c.green else if (current || locked) c.accent else c.text, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
        Text(if (tuned) "✓" else "$number", color = if (tuned) c.green else c.dim, fontSize = 12.sp)
    }
}

/** 音名 + 半圆音分表盘：指针在 −50…+50 音分之间摆，±5 音分内变绿。 */
@Composable
private fun Gauge(model: com.example.tunebeatchord.tuner.TunerModel, fullName: (com.example.tunebeatchord.tuner.Pitch) -> String, naming: com.example.tunebeatchord.tuner.NoteNaming) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val result = model.result
    val cents = (result?.cents ?: 0.0).coerceIn(-50.0, 50.0)
    val inTune = result?.isInTune == true
    val tone by animateColorAsState(if (inTune) c.green else if (result == null) c.dim else c.accent, label = "tone")
    val status = when {
        model.playingReference != null -> strings.t("参考音 %@", fullName(model.playingReference!!))
        result == null -> if (model.lastReading == null) tr("请弹奏一根弦") else tr("无信号")
        inTune -> tr("已准")
        result.isFlat -> tr("偏低")
        else -> tr("偏高")
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Canvas(Modifier.fillMaxWidth().height(150.dp).semantics { contentDescription = strings.t("音分表盘") }) {
            val d = density
            val radius = minOf(size.width / 2 - 20 * d, size.height - 10 * d)
            val center = Offset(size.width / 2, size.height - 6 * d)
            val stroke = 8 * d
            drawArc(c.track, 180f, 180f, false, topLeft = Offset(center.x - radius, center.y - radius), size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2), style = Stroke(stroke, cap = StrokeCap.Round))
            // 准音区（±5 音分）
            val zone = (5 / 50.0 * 90).toFloat()
            drawArc(c.green.copy(alpha = 0.55f), 270f - zone, zone * 2, false, topLeft = Offset(center.x - radius, center.y - radius), size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2), style = Stroke(stroke, cap = StrokeCap.Butt))
            for (i in -5..5) {
                val a = (-90 + i * 18) * PI / 180
                val len = if (i % 5 == 0) 14 * d else 8 * d
                drawLine(c.dim, Offset(center.x + ((radius - 22 * d) * cos(a)).toFloat(), center.y + ((radius - 22 * d) * sin(a)).toFloat()),
                    Offset(center.x + ((radius - 22 * d - len) * cos(a)).toFloat(), center.y + ((radius - 22 * d - len) * sin(a)).toFloat()), strokeWidth = 2 * d)
            }
            if (result != null) {
                val a = (-90 + cents / 50 * 90) * PI / 180
                drawLine(tone, center, Offset(center.x + ((radius - 30 * d) * cos(a)).toFloat(), center.y + ((radius - 30 * d) * sin(a)).toFloat()), strokeWidth = 4 * d, cap = StrokeCap.Round)
            }
            drawCircle(tone, 7 * d, center)
        }
        val target = result?.target ?: model.lastReading?.pitch
        Text(
            if (target != null) naming.name(target) else "–", color = tone, fontSize = 64.sp, fontWeight = FontWeight.Bold,
        )
        Text(if (target != null) "${target.octave}" else "", color = c.sub, fontSize = 18.sp)
        Text(status, color = tone, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        val hz = result?.reading?.frequency
        Text(
            if (result != null && hz != null) "${if (result.cents >= 0) "+" else ""}${result.cents.roundToInt()} ${tr("音分")} · ${"%.1f".format(hz)} Hz" else " ",
            color = c.sub, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp),
        )
    }
}

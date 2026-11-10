package com.example.tunebeatchord.ui.training

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextAlign
import com.example.tunebeatchord.ui.components.noteAnnotated
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.example.tunebeatchord.chord.ChordLibrary
import com.example.tunebeatchord.chord.ChordRoot
import com.example.tunebeatchord.chord.ChordType
import com.example.tunebeatchord.chord.StrumCell
import com.example.tunebeatchord.chord.StrumRhythm
import com.example.tunebeatchord.chord.chordName
import com.example.tunebeatchord.chord.rootName
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.Strings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.strum.Advice
import com.example.tunebeatchord.strum.ChordProgression
import com.example.tunebeatchord.strum.ProgressionChord
import com.example.tunebeatchord.strum.StrumResult
import com.example.tunebeatchord.strum.StrumScore
import com.example.tunebeatchord.strum.StrumTrainer
import com.example.tunebeatchord.tuner.NoteNaming
import com.example.tunebeatchord.ui.components.Card
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.Segmented
import com.example.tunebeatchord.ui.theme.AppTheme
import kotlin.math.abs
import kotlin.math.roundToInt

private fun Strings.advice(a: Advice?): String = a?.let { t(it.key, *it.args.toTypedArray()) } ?: ""

/** 扫弦跟练：选乐器、编和弦进行、选节奏型，听示范，跟着练，收音评分。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StrumScreen(trainer: StrumTrainer, settings: Settings, autoStart: Boolean, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val context = LocalContext.current
    val naming = settings.noteNaming()
    var editing by remember { mutableStateOf<ProgressionChord?>(null) }
    var showSave by remember { mutableStateOf(false) }
    var denied by remember { mutableStateOf(false) }
    var pendingAction by remember { mutableStateOf<String?>(null) }

    // 跟 UI 同步的时钟：只在示范或跟练时每帧刷新
    var clock by remember { mutableLongStateOf(0L) }
    val busy = trainer.phase != StrumTrainer.Phase.IDLE
    LaunchedEffect(busy) { while (busy) androidx.compose.runtime.withFrameNanos { clock = it } }
    val nowSeconds = clock / 1e9
    DisposableEffect(Unit) { onDispose { trainer.leave() } }

    fun hasMic() = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    fun run(action: String) {
        when (action) { "practice" -> trainer.startPractice(); "calibrate" -> trainer.startCalibration() }
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        denied = !granted
        if (granted) pendingAction?.let { run(it) }
        pendingAction = null
    }
    fun needMic(action: String) {
        if (hasMic()) { denied = false; run(action) } else { pendingAction = action; launcher.launch(Manifest.permission.RECORD_AUDIO) }
    }

    var showCalibration by remember { mutableStateOf(false) }
    LaunchedEffect(autoStart) { if (autoStart && trainer.phase == StrumTrainer.Phase.IDLE) needMic("practice") }

    Column(modifier) {
        // 顶栏：关闭、标题、延迟校准
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(c.card).clickable { trainer.leave(); onBack() }.semantics { contentDescription = strings.t("关闭") }, contentAlignment = Alignment.Center) {
                Text("✕", color = c.text, fontSize = 18.sp, fontWeight = FontWeight.Medium)
            }
            Text(tr("扫弦节奏型"), color = c.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1)
            Box(Modifier.height(36.dp).clip(RoundedCornerShape(50)).background(c.card).clickable { if (!busy) showCalibration = true }.padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                Text(tr("延迟校准"), color = c.text, fontSize = 13.sp, maxLines = 1)
            }
        }
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 12.dp)) {
        val instruments = ChordLibrary.strummableInstruments
        Box(Modifier.padding(horizontal = 20.dp)) {
            Segmented(instruments.map { tr(it.name) }, instruments.indexOfFirst { it.id == trainer.instrument.id }.coerceAtLeast(0), { if (!busy) trainer.select(instruments[it]) })
        }

        // 正在示范或跟练：当前和弦、下一个和弦、倒数
        if (busy) LiveCard(trainer, naming, nowSeconds, strings)

        Section(tr("和弦进行")) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                trainer.progression.chords.forEach { pc ->
                    val current = busy && trainer.timeline != null && trainer.plan != null &&
                        trainer.position(nowSeconds)?.let { trainer.progression.chords.indexOf(pc) == trainer.plan!!.chordIndex(it.first) } == true
                    Column(
                        Modifier.clip(RoundedCornerShape(16.dp)).background(if (current) c.accentBrush else androidx.compose.ui.graphics.Brush.verticalGradient(listOf(c.card2, c.card2)))
                            .clickable(enabled = !busy) { editing = pc }.padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(naming.chordName(pc.chord), color = if (current) c.onAccent else c.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        Text(strings.plural("%lld 小节", pc.bars), color = if (current) c.onAccent else c.sub, fontSize = 12.sp)
                    }
                }
                Box(
                    Modifier.size(56.dp).clip(RoundedCornerShape(16.dp)).border(1.5.dp, c.dim, RoundedCornerShape(16.dp))
                        .clickable(enabled = !busy) { editing = ProgressionChord(0, ChordType.Major, 1).copy(id = "new") },
                    contentAlignment = Alignment.Center,
                ) { Text("+", color = c.sub, fontSize = 26.sp) }
            }
            FlowRow(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ChordProgression.presets.forEach { p ->
                    val label = if (p.name == ChordProgression.BLUES_KEY) strings.t(p.name) else p.name
                    Chip(label, false, { if (!busy) trainer.updateProgression(p.copy(id = java.util.UUID.randomUUID().toString())) }, height = 36.dp, fontSize = 13)
                }
            }
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip(tr("保存"), false, { if (!busy) showSave = true }, height = 36.dp, fontSize = 13)
            }
            if (trainer.saved.isNotEmpty()) {
                Text(tr("我的进行"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 6.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    trainer.saved.forEach { p -> Chip(p.name, false, { if (!busy) trainer.updateProgression(p) }, height = 36.dp, fontSize = 13) }
                }
            }
        }

        Section(tr("节奏型")) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                StrumRhythm.presets(trainer.instrument.family).forEach { r -> Chip(tr(r.title), trainer.rhythm.id == r.id, { if (!busy) trainer.select(r) }, height = 38.dp, fontSize = 14) }
            }
            PatternGrid(trainer, nowSeconds)
        }

        Section(tr("速度")) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Chip("−", false, { if (!busy) trainer.updateBpm(trainer.bpm - 5) }, Modifier.size(46.dp), 46.dp)
                Text(strings.t("速度 %lld BPM", trainer.bpm), color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Chip("+", false, { if (!busy) trainer.updateBpm(trainer.bpm + 5) }, Modifier.size(46.dp), 46.dp)
            }
        }
        Section(tr("练习遍数")) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Chip("−", false, { if (!busy) trainer.updatePracticeTarget((trainer.practiceTarget ?: 2) - 1) }, Modifier.size(46.dp), 46.dp)
                Text(trainer.practiceTarget?.let { strings.plural("共 %lld 遍", it) } ?: "∞", color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Chip("+", false, { if (!busy) trainer.updatePracticeTarget((trainer.practiceTarget ?: 0) + 1) }, Modifier.size(46.dp), 46.dp)
                Chip("∞", trainer.practiceTarget == null, { if (!busy) trainer.updatePracticeTarget(if (trainer.practiceTarget == null) 2 else null) }, height = 46.dp)
            }
            Text(tr("留空表示一直练"), color = c.dim, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
        }

        trainer.result?.takeIf { !busy }?.let { ResultCard(it, naming, strings) }

    }
        // 底部按钮：听示范 / 跟我练（练习中是“结束”，示范中是“停止”）
        Column(Modifier.padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (denied) Text(strings.t("需要麦克风权限才能听你扫弦：请到系统设置里允许“调音节拍和弦库”使用麦克风。"), color = c.accent, fontSize = 13.sp)
            trainer.message?.let { m ->
                val text = when (m) {
                    StrumTrainer.Message.MicFailed -> strings.t("无法打开麦克风：%@", "")
                    is StrumTrainer.Message.Calibrated -> strings.t("已校准：以后跟练会扣掉 %lld 毫秒的延迟。", m.ms)
                    is StrumTrainer.Message.CalibrationFailed -> strings.t("没收到足够的声音（%lld/8），请靠近手机、跟着每一拍扫一下再试一次。", m.found)
                }
                Text(text, color = c.accent, fontSize = 13.sp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                when (trainer.phase) {
                    StrumTrainer.Phase.IDLE -> {
                        ActionButton(tr("听示范"), false, Modifier.weight(1f)) { trainer.startDemo() }
                        ActionButton(tr("跟我练"), true, Modifier.weight(1f)) { needMic("practice") }
                    }
                    StrumTrainer.Phase.DEMO -> ActionButton(tr("停止"), true, Modifier.fillMaxWidth()) { trainer.stopDemo() }
                    StrumTrainer.Phase.PRACTICE -> ActionButton(tr("结束"), true, Modifier.fillMaxWidth()) { trainer.endPractice() }
                    StrumTrainer.Phase.CALIBRATING -> ActionButton(tr("停止"), true, Modifier.fillMaxWidth()) { trainer.stopAll() }
                }
            }
        }
    }

    if (showCalibration) {
        com.example.tunebeatchord.ui.metronome.AppSheet(strings.t("延迟校准"), { showCalibration = false }) {
            Text(tr("麦克风收到声音会晚一点。倒数之后，跟着屏幕上的节拍（戴耳机时听节拍声）每一拍扫一下或拍一下琴身，一共 8 拍。"), color = c.sub, fontSize = 13.sp)
            Text(strings.t("当前补偿：%lld 毫秒", (trainer.latencyOffset * 1000).roundToInt()), color = c.text, fontSize = 15.sp, modifier = Modifier.padding(top = 12.dp))
            Row(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ActionButton(tr("开始校准"), true, Modifier.weight(1f)) { showCalibration = false; needMic("calibrate") }
                if (trainer.latencyOffset != 0.0) ActionButton(tr("恢复默认"), false, Modifier.weight(1f)) { trainer.resetCalibration() }
            }
        }
    }

    editing?.let { pc ->
        ChordEditDialog(pc, naming, canDelete = pc.id != "new" && trainer.progression.chords.size > 1, onDismiss = { editing = null },
            onDelete = { trainer.updateProgression(trainer.progression.delete(pc.id)); editing = null },
            onDuplicate = if (pc.id != "new") ({ trainer.progression.duplicate(pc.id)?.let { trainer.updateProgression(it.first) }; editing = null }) else null,
            onConfirm = { edited ->
                trainer.updateProgression(if (pc.id == "new") trainer.progression.append(edited.copy(id = java.util.UUID.randomUUID().toString())) else trainer.progression.update(edited))
                editing = null
            })
    }
    if (showSave) SaveDialog(trainer.progression.name, onDismiss = { showSave = false }) { name -> trainer.saveProgression(name); showSave = false }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) = com.example.tunebeatchord.ui.components.Section(title, content)

/** 示范或跟练时的状态卡：当前和弦（大字）、下一个和弦、倒数、第几遍第几小节、正在评分。 */
@Composable
private fun LiveCard(trainer: StrumTrainer, naming: NoteNaming, now: Double, strings: Strings) {
    val c = AppTheme.colors
    val plan = trainer.plan
    val position = trainer.position(now)
    val countIn = trainer.countIn(now)
    Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
        Card(Modifier.fillMaxWidth()) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                when {
                    countIn != null -> {
                        Text(strings.t("倒数 %lld", countIn), color = c.accent, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                        Text("$countIn", color = c.text, fontSize = 72.sp, fontWeight = FontWeight.Bold)
                        Text(if (trainer.phase == StrumTrainer.Phase.PRACTICE && !trainer.headphonesConnected()) strings.t("准备，跟着倒数和高亮（外放时不放节拍声）") else if (trainer.phase == StrumTrainer.Phase.PRACTICE) strings.t("准备，跟着耳机里的节拍") else "", color = c.sub, fontSize = 13.sp)
                    }
                    position != null && plan != null -> {
                        val index = plan.chordIndex(position.first)
                        val chord = trainer.progression.chords[index].chord
                        Text(naming.chordName(chord), color = c.text, fontSize = 56.sp, fontWeight = FontWeight.Bold)
                        val next = if (position.first + 1 < plan.bars) plan.chordIndex(position.first + 1) else null
                        if (next != null && next != index) Text(strings.t("下一个：%@", naming.chordName(trainer.progression.chords[next].chord)), color = c.accent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        if (trainer.phase == StrumTrainer.Phase.PRACTICE) {
                            val total = trainer.practiceTarget
                            val round = trainer.passesDone + 1
                            Text(
                                if (total != null) strings.t("收音中 · 第 %lld / %lld 遍 · 第 %lld / %lld 小节", round, total, position.first + 1, plan.bars)
                                else strings.t("收音中 · 第 %lld 遍 · 第 %lld / %lld 小节", round, position.first + 1, plan.bars),
                                color = c.sub, fontSize = 13.sp,
                            )
                        }
                    }
                    else -> Text(if (trainer.scoring) strings.t("正在评分…") else "…", color = c.sub, fontSize = 18.sp)
                }
                trainer.lastPass?.let { (k, score) -> if (trainer.phase == StrumTrainer.Phase.PRACTICE) Text(strings.t("第 %lld 遍：%lld 分", k, score), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp)) }
            }
        }
    }
}

/** 节奏型的格子：箭头（该用的扫法）加报数，正在走到的那一格高亮。 */
@Composable
private fun PatternGrid(trainer: StrumTrainer, now: Double) {
    val c = AppTheme.colors
    val r = trainer.rhythm
    val current = trainer.position(now)?.second
    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        r.cells.indices.chunked(r.cellsPerBeat * 4).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                row.forEach { i ->
                    val on = current == i
                    Column(
                        Modifier.weight(1f).height(54.dp).clip(RoundedCornerShape(10.dp))
                            .background(if (on) c.accentBrush else androidx.compose.ui.graphics.Brush.verticalGradient(listOf(c.card2, c.card2))),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Text(r.cells[i].let { if (it == StrumCell.REST) "·" else it.arrow }, color = if (on) c.onAccent else if (r.cells[i] == StrumCell.REST) c.dim else c.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        Text(r.countLabel(i), color = if (on) c.onAccent else c.sub, fontSize = 11.sp)
                    }
                }
                repeat(r.cellsPerBeat * 4 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

private val Amber = Color(0xFFFFB020)
private val Red = Color(0xFFFF453A)

/** 底部的大按钮：主按钮是主色渐变，次按钮是主色淡底、主色字（和 iOS 版“听示范 / 跟我练”一致）。 */
@Composable
private fun ActionButton(label: String, primary: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(
        modifier.height(56.dp).clip(RoundedCornerShape(16.dp))
            .background(if (primary) c.accentBrush else Brush.verticalGradient(listOf(c.accent.copy(alpha = 0.18f), c.accent.copy(alpha = 0.18f))))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(label, color = if (primary) Color.White else c.accent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
}

private fun scoreColor(score: Int, c: com.example.tunebeatchord.ui.theme.AppColors) = if (score >= 85) c.green else if (score >= 60) Amber else Red

/** 成绩卡片（iOS 版的结果页）：平均分、每遍的柱、准偏漏多扫四格、最后一遍每个和弦的逐格结果、平均偏差和稳定度、建议、按和弦的分数、换和弦后第一下。 */
@Composable
private fun ResultCard(result: StrumResult, naming: NoteNaming, strings: Strings) {
    val c = AppTheme.colors
    val combined = result.combined ?: return
    val passes = result.run.passes
    val rhythm = result.timeline.pattern
    Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        com.example.tunebeatchord.ui.components.CardBox(Modifier.fillMaxWidth(), radius = 24.dp) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(if (passes.size > 1) tr("平均") else "", color = c.sub, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp, bottom = 12.dp))
                    Text("${result.score}", color = c.accent, fontSize = 64.sp, fontWeight = FontWeight.Bold)
                    Text(tr("分"), color = c.sub, fontSize = 18.sp, modifier = Modifier.padding(start = 6.dp, bottom = 14.dp))
                    Box(Modifier.weight(1f))
                    result.run.best?.let { Text(strings.t("这个节奏型最好 %lld 分", maxOf(it.second, 0)), color = c.sub, fontSize = 12.sp, textAlign = TextAlign.End, modifier = Modifier.padding(bottom = 16.dp)) }
                }
                if (passes.size > 1) {
                    Row(Modifier.fillMaxWidth().height(52.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
                        result.run.passScores.forEachIndexed { i, sc ->
                            Box(
                                Modifier.weight(1f).height(maxOf(6, (sc / 100f * 52).toInt()).dp).clip(RoundedCornerShape(4.dp))
                                    .background(if (i == passes.lastIndex) c.accent else c.accentSoft),
                            )
                        }
                    }
                    Text(
                        strings.plural("共 %lld 遍", passes.size) + "    " + (result.run.best?.let { strings.t("最好一遍：第 %lld 遍 %lld 分", it.first, it.second) } ?: ""),
                        color = c.sub, fontSize = 12.sp,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatTile(combined.good, tr("准"), c.green, Modifier.weight(1f))
                    StatTile(combined.off, tr("偏"), Amber, Modifier.weight(1f))
                    StatTile(combined.missed, tr("漏"), Red, Modifier.weight(1f))
                    StatTile(combined.extras.size, tr("多扫"), c.sub, Modifier.weight(1f))
                }
                // 最后一遍：每个和弦一行，每格按准偏漏上色
                val last = passes.lastOrNull()
                if (last != null) {
                    Text(if (passes.size > 1) tr("最后一遍") else tr("最后一遍"), color = c.sub, fontSize = 13.sp)
                    val bars = last.hits.map { it.bar }.distinct().sorted()
                    val plan = com.example.tunebeatchord.strum.ProgressionPlan.of(result.progression, minBars = StrumTrainer.MIN_PRACTICE_BARS)
                    for (bar in bars) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(noteAnnotated(result.names.getOrElse(plan.chordIndex(bar)) { "" }), color = c.sub, fontSize = 13.sp, maxLines = 1, modifier = Modifier.width(34.dp))
                            for (step in 0 until rhythm.cells.size) {
                                val hit = last.hits.firstOrNull { it.bar == bar && it.step == step }
                                val cell = rhythm.cells[step]
                                val tone = when (hit?.grade) {
                                    StrumScore.Grade.GOOD -> c.green
                                    StrumScore.Grade.OFF -> Amber
                                    StrumScore.Grade.MISSED -> Red
                                    null -> c.dim
                                }
                                Box(
                                    Modifier.weight(1f).height(30.dp).clip(RoundedCornerShape(7.dp))
                                        .background(if (hit == null) Color.Transparent else tone.copy(alpha = 0.22f))
                                        .then(if (hit == null) Modifier.border(1.dp, c.dim.copy(alpha = 0.6f), RoundedCornerShape(7.dp)) else Modifier),
                                    contentAlignment = Alignment.Center,
                                ) { if (hit != null) Text(cell.arrow, color = tone, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
                            }
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    combined.meanOffsetMs?.let { m ->
                        val text = if (abs(m) < 8) tr("刚好") else if (m > 0) strings.t("偏慢 %lld 毫秒", m.roundToInt()) else strings.t("偏快 %lld 毫秒", abs(m).roundToInt())
                        Row { Text(tr("平均") + " ", color = c.sub, fontSize = 14.sp); Text(text, color = c.text, fontSize = 14.sp, fontWeight = FontWeight.Bold) }
                    }
                    combined.spreadMs?.let {
                        Row { Text(tr("稳定度") + " ", color = c.sub, fontSize = 14.sp); Text(strings.t("±%lld 毫秒", it.roundToInt()), color = c.text, fontSize = 14.sp, fontWeight = FontWeight.Bold) }
                    }
                }
                Text(strings.advice(combined.advice), color = c.text, fontSize = 15.sp)
                result.report?.let { rep ->
                    if (rep.segments.size > 1) {
                        Text(tr("按和弦"), color = c.sub, fontSize = 13.sp)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            rep.segments.forEach { seg ->
                                Column(
                                    Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(c.card2).padding(vertical = 10.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                ) {
                                    Text(noteAnnotated(seg.name), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                    Text("${seg.score}", color = scoreColor(seg.score, c), fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                    rep.changeMeanMs?.let { m ->
                        val text = if (abs(m) < 8) tr("换和弦后第一下：刚好") else if (m > 0) strings.t("换和弦后第一下：平均偏慢 %lld 毫秒", m.roundToInt()) else strings.t("换和弦后第一下：平均偏快 %lld 毫秒", abs(m).roundToInt())
                        Text(text, color = c.sub, fontSize = 13.sp)
                    }
                    rep.advice?.let { Text(strings.advice(it), color = c.accent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
                }
                Text(tr("±60 毫秒内算准，±120 毫秒内算偏，再远算漏；多出来的一下扣半格。"), color = c.dim, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun StatTile(value: Int, label: String, color: Color, modifier: Modifier) {
    val c = AppTheme.colors
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(c.card2).padding(vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("$value", color = color, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
        Text(label, color = c.sub, fontSize = 13.sp)
    }
}

@Composable
private fun Stat(label: String, value: Int, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text("$value", color = color, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(label, color = AppTheme.colors.sub, fontSize = 12.sp)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChordEditDialog(
    start: ProgressionChord, naming: NoteNaming, canDelete: Boolean, onDismiss: () -> Unit, onDelete: () -> Unit,
    onDuplicate: (() -> Unit)?, onConfirm: (ProgressionChord) -> Unit,
) {
    var root by remember { mutableStateOf(start.root) }
    var type by remember { mutableStateOf(start.type) }
    var bars by remember { mutableStateOf(start.bars) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (start.id == "new") tr("添加和弦") else tr("编辑和弦进行")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(naming.chordName(root, type), fontSize = 28.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ChordRoot.all.forEach { pc -> Chip(naming.rootName(pc), root == pc, { root = pc }, height = 38.dp, fontSize = 14, horizontalPadding = 10.dp) }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ChordType.builtins.forEach { t -> Chip(naming.chordName(root, t), type.id == t.id, { type = t }, height = 38.dp, fontSize = 13, horizontalPadding = 8.dp) }
                }
                Text(tr("持续"))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ProgressionChord.barChoices.forEach { b -> Chip(LocalStrings.current.plural("%lld 小节", b), bars == b, { bars = b }, height = 38.dp, fontSize = 13) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (onDuplicate != null) TextButton(onClick = onDuplicate) { Text(tr("复制")) }
                    if (canDelete) TextButton(onClick = onDelete) { Text(tr("删除")) }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(start.copy(root = root, typeID = type.id, bars = bars)) }) { Text(tr("确定")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } },
    )
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

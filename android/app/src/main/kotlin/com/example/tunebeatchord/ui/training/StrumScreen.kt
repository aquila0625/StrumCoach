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
fun StrumScreen(trainer: StrumTrainer, settings: Settings, onBack: () -> Unit, modifier: Modifier = Modifier) {
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

    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable { trainer.leave(); onBack() }, contentAlignment = Alignment.Center) {
                Text("‹", color = c.text, fontSize = 32.sp)
            }
            Text(tr("扫弦节奏型"), color = c.text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
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

        // 操作按钮
        Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when (trainer.phase) {
                StrumTrainer.Phase.IDLE -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Chip(tr("听示范"), false, { trainer.startDemo() }, Modifier.weight(1f), height = 54.dp, fontSize = 17)
                    Chip(tr("跟我练"), true, { needMic("practice") }, Modifier.weight(1f), height = 54.dp, fontSize = 17)
                }
                StrumTrainer.Phase.DEMO -> Chip(tr("停止"), true, { trainer.stopDemo() }, Modifier.fillMaxWidth(), height = 54.dp, fontSize = 17)
                StrumTrainer.Phase.PRACTICE -> Chip(tr("结束"), true, { trainer.endPractice() }, Modifier.fillMaxWidth(), height = 54.dp, fontSize = 17)
                StrumTrainer.Phase.CALIBRATING -> Chip(tr("停止"), true, { trainer.stopAll() }, Modifier.fillMaxWidth(), height = 54.dp, fontSize = 17)
            }
            if (denied) Text(strings.t("需要麦克风权限才能听你扫弦：请到系统设置里允许“调音节拍和弦库”使用麦克风。"), color = c.accent, fontSize = 14.sp)
            when (trainer.phase) {
                StrumTrainer.Phase.DEMO -> Text(tr("示范中：一直循环，点“停止”结束"), color = c.sub, fontSize = 13.sp)
                StrumTrainer.Phase.IDLE -> Text(tr("先听示范，再跟着练；戴耳机可以听着节拍练。"), color = c.sub, fontSize = 13.sp)
                else -> {}
            }
            trainer.message?.let { m ->
                val text = when (m) {
                    StrumTrainer.Message.MicFailed -> strings.t("无法打开麦克风：%@", "")
                    is StrumTrainer.Message.Calibrated -> strings.t("已校准：以后跟练会扣掉 %lld 毫秒的延迟。", m.ms)
                    is StrumTrainer.Message.CalibrationFailed -> strings.t("没收到足够的声音（%lld/8），请靠近手机、跟着每一拍扫一下再试一次。", m.found)
                }
                Text(text, color = c.accent, fontSize = 14.sp)
            }
        }
        trainer.result?.takeIf { !busy }?.let { ResultCard(it, naming, strings) }

        Section(tr("延迟校准")) {
            Text(tr("麦克风收到声音会晚一点。倒数之后，跟着屏幕上的节拍（戴耳机时听节拍声）每一拍扫一下或拍一下琴身，一共 8 拍。"), color = c.sub, fontSize = 13.sp)
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Chip(tr("开始校准"), false, { if (!busy) needMic("calibrate") }, height = 40.dp, fontSize = 14)
                if (trainer.latencyOffset != 0.0) Chip(tr("恢复默认"), false, { trainer.resetCalibration() }, height = 40.dp, fontSize = 14)
                Text(strings.t("当前补偿：%lld 毫秒", (trainer.latencyOffset * 1000).roundToInt()), color = c.sub, fontSize = 13.sp)
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

@Composable
private fun ResultCard(result: StrumResult, naming: NoteNaming, strings: Strings) {
    val c = AppTheme.colors
    val combined = result.combined ?: return
    Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Card(Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${result.score}", color = c.accent, fontSize = 64.sp, fontWeight = FontWeight.Bold)
                    Text(tr("分"), color = c.sub, fontSize = 18.sp, modifier = Modifier.padding(start = 6.dp, bottom = 10.dp))
                }
                result.run.best?.let { (k, s) -> if (result.run.passes.size > 1) Text(strings.t("最好一遍：第 %lld 遍 %lld 分", k, s), color = c.sub, fontSize = 14.sp) }
                if (result.run.passes.size > 1) Text(result.run.passScores.mapIndexed { i, s -> strings.t("第 %lld 遍：%lld 分", i + 1, s) }.joinToString("  ·  "), color = c.sub, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Stat(tr("准"), combined.good, c.green); Stat(tr("偏"), combined.off, c.accent); Stat(tr("漏"), combined.missed, c.dim); Stat(tr("多扫"), combined.extras.size, c.dim)
                }
                combined.meanOffsetMs?.let { m ->
                    val text = if (abs(m) < 8) tr("刚好") else if (m > 0) strings.t("偏慢 %lld 毫秒", m.roundToInt()) else strings.t("偏快 %lld 毫秒", abs(m).roundToInt())
                    Text(tr("平均") + "：" + text, color = c.text, fontSize = 15.sp)
                }
                combined.spreadMs?.let { Text(tr("稳定度") + "：" + strings.t("±%lld 毫秒", it.roundToInt()), color = c.text, fontSize = 15.sp) }
                Text(strings.advice(combined.advice), color = c.accent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                result.report?.let { rep ->
                    if (rep.segments.size > 1) {
                        Text(tr("按和弦"), color = c.sub, fontSize = 13.sp)
                        rep.segments.forEach { Text("${it.name}  ${strings.t("%lld 分", it.score)}", color = c.text, fontSize = 15.sp) }
                    }
                    rep.changeMeanMs?.let { m ->
                        val text = if (abs(m) < 8) tr("换和弦后第一下：刚好") else if (m > 0) strings.t("换和弦后第一下：平均偏慢 %lld 毫秒", m.roundToInt()) else strings.t("换和弦后第一下：平均偏快 %lld 毫秒", abs(m).roundToInt())
                        Text(text, color = c.text, fontSize = 14.sp)
                    }
                    rep.advice?.let { Text(strings.advice(it), color = c.accent, fontSize = 14.sp) }
                }
                Text(tr("±60 毫秒内算准，±120 毫秒内算偏，再远算漏；多出来的一下扣半格。"), color = c.dim, fontSize = 12.sp)
                Text(tr("第一版只看扫弦的时间准不准，不判断你实际是上扫还是下扫；箭头是节奏型里该用的扫法。"), color = c.dim, fontSize = 12.sp)
            }
        }
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

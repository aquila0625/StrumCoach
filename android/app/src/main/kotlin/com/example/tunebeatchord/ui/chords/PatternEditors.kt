package com.example.tunebeatchord.ui.chords

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.chord.ArpeggioInput
import com.example.tunebeatchord.chord.ArpeggioParse
import com.example.tunebeatchord.chord.ArpeggioStep
import com.example.tunebeatchord.chord.ChordLibraryState
import com.example.tunebeatchord.chord.ChordPlayer
import com.example.tunebeatchord.chord.CustomArpeggio
import com.example.tunebeatchord.chord.CustomStrumRhythm
import com.example.tunebeatchord.chord.StrumInput
import com.example.tunebeatchord.chord.StrumParse
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.ui.components.Segmented
import com.example.tunebeatchord.ui.theme.AppTheme

private val ErrorRed = Color(0xFFE5484D)

/** 编辑页的外壳：顶上“取消 / 标题 / 保存”，下面是内容；键盘弹出时整体上移。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorSheet(title: String, canSave: Boolean, onCancel: () -> Unit, onSave: () -> Unit, saveLabel: String = tr("保存"), content: @Composable () -> Unit) {
    val c = AppTheme.colors
    ModalBottomSheet(
        onDismissRequest = onCancel, containerColor = c.sheet, scrimColor = c.scrim,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        dragHandle = { Box(Modifier.padding(vertical = 10.dp).width(40.dp).height(5.dp).clip(RoundedCornerShape(50)).background(c.weak)) },
    ) {
        Column(
            Modifier.imePadding().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(tr("取消"), color = c.sub, fontSize = 16.sp, modifier = Modifier.clickable(onClick = onCancel).padding(end = 12.dp, top = 4.dp, bottom = 4.dp))
                Text(title, color = c.text, fontSize = 17.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Text(
                    saveLabel, color = if (canSave) c.accent else c.dim, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clickable(enabled = canSave, onClick = onSave).padding(start = 12.dp, top = 4.dp, bottom = 4.dp),
                )
            }
            content()
        }
    }
}

@Composable
private fun FieldBox(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Box(modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(12.dp)).background(c.sheetCard).padding(horizontal = 12.dp), contentAlignment = Alignment.CenterStart) { content() }
}

/** 输入弦号 / 节奏型字符的输入框：不自动大小写、不自动更正。 */
@Composable
private fun SymbolField(value: String, placeholder: String, capitalizeAll: Boolean, onChange: (String) -> Unit) {
    val c = AppTheme.colors
    FieldBox {
        BasicTextField(
            value, onChange, singleLine = true,
            textStyle = TextStyle(color = c.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace),
            cursorBrush = SolidColor(c.accent),
            keyboardOptions = KeyboardOptions(
                capitalization = if (capitalizeAll) KeyboardCapitalization.Characters else KeyboardCapitalization.None,
                autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii,
            ),
            decorationBox = { inner -> if (value.isEmpty()) Text(placeholder, color = c.dim, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace); inner() },
        )
    }
}

@Composable
private fun NameField(value: String, placeholder: String, onChange: (String) -> Unit) {
    val c = AppTheme.colors
    FieldBox {
        BasicTextField(
            value, onChange, singleLine = true, textStyle = TextStyle(color = c.text, fontSize = 16.sp), cursorBrush = SolidColor(c.accent),
            decorationBox = { inner -> if (value.isEmpty()) Text(placeholder, color = c.dim, fontSize = 16.sp); inner() },
        )
    }
}

// 快捷键 -------------------------------------------------------------------

private class QuickKey(val title: String, val text: String?, val label: String, val isRest: Boolean = false, val isDelete: Boolean = false, val caption: String? = null, val arrow: String? = null)

@Composable
private fun QuickKeyPad(rows: List<List<QuickKey>>, onKey: (QuickKey) -> Unit) {
    val c = AppTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { key ->
                    val outlined = key.isRest || key.isDelete
                    Column(
                        Modifier.weight(1f).heightIn(min = if (key.arrow == null) 40.dp else 46.dp).clip(RoundedCornerShape(10.dp))
                            .then(if (outlined) Modifier else Modifier.background(c.sheetCard))
                            .then(if (outlined) Modifier.border(1.5.dp, if (key.isRest) c.accent else c.dim, RoundedCornerShape(10.dp)) else Modifier)
                            .clickable { onKey(key) },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        when {
                            key.isDelete -> Text("⌫", color = c.text, fontSize = 18.sp)
                            key.isRest -> Text("–", color = c.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                            key.arrow != null -> {
                                Text(key.arrow + " " + key.title, color = c.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                                key.caption?.let { Text(it, color = c.sub, fontSize = 10.sp, maxLines = 1) }
                            }
                            else -> Text(key.title, color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun arpeggioKeys(stringCount: Int): List<List<QuickKey>> {
    val digits = (1..maxOf(1, stringCount)).map { QuickKey("$it", "$it", "$it") } + QuickKey("R", "R", "R")
    return listOf(digits, listOf(QuickKey("-", "-", tr("空拍"), isRest = true), QuickKey("", null, tr("退格"), isDelete = true)))
}

@Composable
private fun rhythmKeys(): List<List<QuickKey>> = listOf(
    listOf(
        QuickKey("B", "B", tr("根音"), caption = tr("根音"), arrow = "●"),
        QuickKey("D", "D", tr("全扫"), caption = tr("全扫"), arrow = "↓"),
        QuickKey("d", "d", tr("半扫"), caption = tr("半扫"), arrow = "⇣"),
        QuickKey("U", "U", tr("上扫"), caption = tr("上扫"), arrow = "↑"),
        QuickKey("X", "X", tr("闷音"), caption = tr("闷音"), arrow = "✕"),
    ),
    listOf(QuickKey(".", ".", tr("空拍"), isRest = true), QuickKey("", null, tr("退格"), isDelete = true)),
)

private fun apply(key: QuickKey, text: String, deleteLast: (String) -> String): String = if (key.isDelete) deleteLast(text) else text + (key.text ?: "")

private fun tokenLine(tokens: List<Pair<String, Boolean>>, separator: String, valid: Color): AnnotatedString = buildAnnotatedString {
    tokens.forEachIndexed { i, (t, ok) ->
        if (i > 0 && separator.isNotEmpty()) append(separator)
        withStyle(SpanStyle(color = if (ok) valid else ErrorRed)) { append(t) }
    }
}

@Composable
private fun Message(text: String, isError: Boolean) {
    Text(text, color = if (isError) ErrorRed else AppTheme.colors.sub, fontSize = 13.sp)
}

@Composable
private fun EditorFooter(canPreview: Boolean, onPreview: () -> Unit, onDelete: (() -> Unit)?) {
    val c = AppTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.height(40.dp).clip(RoundedCornerShape(50)).then(if (canPreview) Modifier.background(c.accent) else Modifier.background(c.sheetCard))
                .clickable(enabled = canPreview, onClick = onPreview).padding(horizontal = 18.dp),
            contentAlignment = Alignment.Center,
        ) { Text("▶  " + tr("试听"), color = if (canPreview) c.onAccent else c.dim, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
        Box(Modifier.weight(1f))
        if (onDelete != null) Text(tr("删除"), color = ErrorRed, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onDelete).padding(8.dp))
    }
}

// 自定义分解指法 -----------------------------------------------------------------

/** 一步一个格子：弦号 / R 是实心格子，空拍是描边的空格子。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ArpeggioStepStrip(steps: List<ArpeggioStep>) {
    val c = AppTheme.colors
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        steps.forEach { step ->
            val shape = RoundedCornerShape(7.dp)
            when (step) {
                ArpeggioStep.Rest -> Box(Modifier.size(32.dp).clip(shape).border(1.dp, c.dim, shape))
                ArpeggioStep.Root -> Box(Modifier.size(32.dp).clip(shape).background(c.accent), contentAlignment = Alignment.Center) {
                    Text("R", color = c.onAccent, fontSize = 15.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                }
                is ArpeggioStep.StringNumber -> Box(Modifier.size(32.dp).clip(shape).background(c.card2), contentAlignment = Alignment.Center) {
                    Text("${step.n}", color = c.text, fontSize = 15.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }
}

@Composable
fun CustomArpeggioEditor(state: ChordLibraryState, player: ChordPlayer, editing: CustomArpeggio?, onClose: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var text by remember { mutableStateOf(editing?.text ?: "") }
    var name by remember { mutableStateOf(editing?.name ?: "") }
    val stringCount = state.tuning.strings.size
    val parsed = state.validateArpeggio(text)
    val isNewAndFull = editing == null && !state.canAddCustomArpeggio
    val message = when {
        isNewAndFull -> strings.t("每种乐器最多保存 %lld 个", ArpeggioInput.MAX_SAVED) to true
        parsed.failure == ArpeggioParse.Failure.INVALID_CHARACTERS -> strings.t("只能输入 1–%lld 的弦号、0 或 -（空拍）和字母 R", stringCount) to true
        parsed.failure == ArpeggioParse.Failure.TOO_LONG -> strings.t("最多 %lld 个音", ArpeggioInput.MAX_STEPS) to true
        else -> strings.t("输入弦号，1 弦最细（最多 %lld 弦）。- 或 0 是空拍（不弹，占一个音的时值）；可以用空格或逗号分隔，也可以连着写；R 代表当前和弦的根音弦。", stringCount) to false
    }
    EditorSheet(
        strings.t("自定义指法"), parsed.isValid && !isNewAndFull, onClose,
        onSave = { if (state.saveCustomArpeggio(editing?.id, name, text) != null) onClose() },
    ) {
        SymbolField(text, "5 3 2 1", capitalizeAll = true) { text = it }
        QuickKeyPad(arpeggioKeys(stringCount)) { text = apply(it, text, ArpeggioInput::deletingLastToken) }
        if (parsed.tokens.any { !it.isValid }) {
            Text(tokenLine(parsed.tokens.map { it.text to it.isValid }, " ", c.text), fontSize = 17.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace)
        } else if (parsed.steps.isNotEmpty()) ArpeggioStepStrip(parsed.steps)
        Message(message.first, message.second)
        NameField(name, if (parsed.isValid) parsed.normalized else strings.t("名称")) { name = it }
        EditorFooter(parsed.isValid, { player.previewArpeggio(text) }, editing?.let { e -> { state.deleteCustomArpeggio(e.id); onClose() } })
    }
}

// 自定义扫弦节奏型 ---------------------------------------------------------------

@Composable
fun CustomRhythmEditor(
    state: ChordLibraryState, player: ChordPlayer, editing: CustomStrumRhythm?,
    family: com.example.tunebeatchord.tuner.InstrumentFamily = state.instrument.family,
    selectsOnSave: Boolean = true,
    onSave: ((CustomStrumRhythm) -> Unit)? = null,
    onClose: () -> Unit,
) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var text by remember { mutableStateOf(editing?.code ?: "") }
    var name by remember { mutableStateOf(editing?.name ?: "") }
    var cellsPerBeat by remember { mutableStateOf(editing?.cellsPerBeat ?: 2) }
    val parsed: StrumParse = StrumInput.parse(text, cellsPerBeat)
    val isNewAndFull = editing == null && !state.canAddCustomRhythm(family)
    val message = when {
        isNewAndFull -> strings.t("每种乐器最多保存 %lld 个", StrumInput.MAX_SAVED) to true
        parsed.failure == StrumParse.Failure.INVALID_CHARACTERS -> strings.t("只能输入 B、D、d、U、X、- 和 .") to true
        parsed.failure == StrumParse.Failure.TOO_LONG -> strings.t("最多 %lld 拍", StrumInput.MAX_BEATS) to true
        parsed.failure == StrumParse.Failure.NOT_WHOLE_BEATS -> strings.t("格数要是 %lld 的整数倍", cellsPerBeat) to true
        else -> strings.t("每个字符一格：B 根音、D 全扫、d 半扫、U 上扫、X 闷音、- 或 . 空拍（D 和 d 分大小写）。空格只用来分组。") to false
    }
    EditorSheet(
        strings.t("自定义节奏型"), parsed.isValid && !isNewAndFull, onClose,
        onSave = { state.saveCustomRhythm(editing?.id, name, text, cellsPerBeat, family, selectsOnSave)?.let { onSave?.invoke(it); onClose() } },
    ) {
        SymbolField(text, "D.DU.UDU", capitalizeAll = false) { text = it }
        QuickKeyPad(rhythmKeys()) { text = apply(it, text) { t -> ArpeggioInput.deletingLastToken(t) } }
        Text(strings.t("B 只拨根音弦；D 从根音弦扫到 1 弦；d 和 U 只扫高音的 3–4 根弦。"), color = c.sub, fontSize = 12.sp)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(strings.t("格子单位"), color = c.sub, fontSize = 13.sp)
            Box(Modifier.weight(1f)) { Segmented(listOf(strings.t("八分"), strings.t("十六分")), if (cellsPerBeat == 2) 0 else 1, onSelect = { cellsPerBeat = if (it == 0) 2 else 4 }) }
        }
        if (parsed.invalid.isNotEmpty()) {
            Text(
                buildAnnotatedString { text.filter { !it.isWhitespace() }.forEach { ch -> withStyle(SpanStyle(color = if (ch in parsed.invalid) ErrorRed else c.text)) { append(ch) } } },
                fontSize = 17.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace,
            )
        } else if (parsed.cells.isNotEmpty()) CellStrip(parsed.cells, cellsPerBeat, null)
        Message(message.first, message.second)
        NameField(name, if (parsed.isValid) parsed.normalized else strings.t("名称")) { name = it }
        EditorFooter(parsed.isValid && family in com.example.tunebeatchord.chord.ChordLibrary.strummableFamilies, { player.previewRhythm(text, cellsPerBeat, family) }, editing?.let { e -> { state.deleteCustomRhythm(e.id, family); onClose() } })
    }
}

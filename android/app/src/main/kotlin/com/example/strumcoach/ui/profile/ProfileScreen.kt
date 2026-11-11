package com.example.strumcoach.ui.profile

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.strumcoach.i18n.LocalStrings
import com.example.strumcoach.i18n.Strings
import com.example.strumcoach.i18n.tr
import com.example.strumcoach.metronome.MetronomeController
import com.example.strumcoach.practice.PracticeLog
import com.example.strumcoach.practice.PracticeSession
import com.example.strumcoach.practice.PracticeStatistics
import com.example.strumcoach.rhythm.PracticeMode
import com.example.strumcoach.settings.AppLanguage
import com.example.strumcoach.settings.NoteNamingPreference
import com.example.strumcoach.settings.Settings
import com.example.strumcoach.tuner.NoteNaming
import com.example.strumcoach.tuner.TunerDefaults
import com.example.strumcoach.ui.components.CardBox
import com.example.strumcoach.ui.components.ChevronRight
import com.example.strumcoach.ui.components.Segmented
import com.example.strumcoach.ui.metronome.AppSheet
import com.example.strumcoach.ui.metronome.SoundSheet
import com.example.strumcoach.ui.theme.AppTheme
import com.example.strumcoach.ui.theme.ThemeMode
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

private val AppLanguage.flag: String
    get() = when (this) {
        AppLanguage.SYSTEM -> "🌐"
        AppLanguage.ZH_HANS -> "🇨🇳"
        AppLanguage.ZH_HANT -> "🇹🇼"
        AppLanguage.EN -> "🇺🇸"
        AppLanguage.JA -> "🇯🇵"
        AppLanguage.KO -> "🇰🇷"
        AppLanguage.ES -> "🇪🇸"
        AppLanguage.FR -> "🇫🇷"
        AppLanguage.DE -> "🇩🇪"
        AppLanguage.PT_BR -> "🇧🇷"
        AppLanguage.IT -> "🇮🇹"
        AppLanguage.RU -> "🇷🇺"
        AppLanguage.TR -> "🇹🇷"
    }

private enum class ProfileSheet { HISTORY, LANGUAGE, SOUND }

/** 我的：本周练习、连续打卡和近 7 天迷你柱状图，练习记录入口；偏好设置（外观、语言、音名显示、节拍音色、标准音、跟拍震动、左手模式）和版本。和 iOS 版同一个版式。 */
@Composable
fun ProfileScreen(log: PracticeLog, settings: Settings, metronome: MetronomeController, onLanguageChanged: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    var sheet by remember { mutableStateOf<ProfileSheet?>(null) }
    val stats = PracticeStatistics(ZoneId.systemDefault(), DayOfWeek.MONDAY)
    val sessions = log.sessions
    val now = Instant.now()

    Column(modifier) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("我的"), color = c.text, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard(stats, sessions, now, strings) { sheet = ProfileSheet.HISTORY }
            Text(tr("偏好设置"), color = c.sub, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 2.dp).padding(top = 2.dp))
            Preferences(settings, metronome, onLanguage = { sheet = ProfileSheet.LANGUAGE }, onSound = { sheet = ProfileSheet.SOUND })
            CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).heightIn(min = 50.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(tr("版本"), color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    Text(appVersion(), color = c.sub, fontSize = 15.sp)
                }
            }
        }
    }

    when (sheet) {
        ProfileSheet.HISTORY -> AppSheet(tr("练习历史"), { sheet = null }) { HistoryList(stats.recent(sessions, 200), strings) }
        ProfileSheet.LANGUAGE -> AppSheet(tr("语言"), { sheet = null }) {
            LanguageList(settings) { picked ->
                sheet = null
                if (settings.language != picked) { settings.updateLanguage(picked); onLanguageChanged() }
            }
        }
        ProfileSheet.SOUND -> SoundSheet(metronome) { sheet = null }
        null -> {}
    }
}

/** 数字大而细、单位小而灰：把本地化的时长字符串里的数字挑出来放大。 */
private fun styledDuration(text: String, number: androidx.compose.ui.graphics.Color, unit: androidx.compose.ui.graphics.Color): androidx.compose.ui.text.AnnotatedString =
    buildAnnotatedString {
        var i = 0
        while (i < text.length) {
            val digit = text[i].isDigit()
            var j = i
            while (j < text.length && text[j].isDigit() == digit) j++
            val part = text.substring(i, j)
            if (digit) pushStyle(SpanStyle(fontSize = 26.sp, fontWeight = FontWeight.Light, color = number))
            else pushStyle(SpanStyle(fontSize = 13.sp, color = unit))
            append(part)
            pop()
            i = j
        }
    }

private fun formatDuration(locale: Locale, minutes: Int, width: MeasureFormat.FormatWidth): String {
    val fmt = MeasureFormat.getInstance(locale, width)
    val h = minutes / 60
    val m = minutes % 60
    return when {
        minutes == 0 -> fmt.format(Measure(0, MeasureUnit.MINUTE))
        h == 0 -> fmt.format(Measure(m, MeasureUnit.MINUTE))
        m == 0 -> fmt.format(Measure(h, MeasureUnit.HOUR))
        else -> fmt.formatMeasures(Measure(h, MeasureUnit.HOUR), Measure(m, MeasureUnit.MINUTE))
    }
}

@Composable
private fun SummaryCard(stats: PracticeStatistics, sessions: List<PracticeSession>, now: Instant, strings: Strings, onHistory: () -> Unit) {
    val c = AppTheme.colors
    val weeklySeconds = stats.weeklyTotal(sessions, now)
    // 按分钟四舍五入；练过但不足 1 分钟时算 1 分钟，免得显示 0
    val weeklyMinutes = if (weeklySeconds > 0) max(1, (weeklySeconds / 60).roundToInt()) else 0
    val streak = stats.currentStreak(sessions, now)
    val days = stats.dailyDurations(sessions, now)
    val minutes = days.map { if (it.duration > 0) max(1, (it.duration / 60).roundToInt()) else 0 }
    val maxMinutes = max(50, minutes.maxOrNull() ?: 0)
    val barArea = 52.dp
    val latest = stats.recent(sessions, 1).firstOrNull()
    CardBox(Modifier.fillMaxWidth(), radius = 20.dp) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Bottom) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(tr("本周练习"), color = c.sub, fontSize = 12.sp)
                    Text(styledDuration(formatDuration(strings.locale, weeklyMinutes, MeasureFormat.FormatWidth.NARROW), c.text, c.sub), maxLines = 1)
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(tr("连续打卡"), color = c.sub, fontSize = 12.sp)
                    Text(styledDuration(MeasureFormat.getInstance(strings.locale, MeasureFormat.FormatWidth.WIDE).format(Measure(streak, MeasureUnit.DAY)), c.accent, c.sub), maxLines = 1)
                }
                Row(Modifier.weight(1f).height(barArea), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
                    minutes.forEachIndexed { i, m ->
                        val isToday = i == minutes.lastIndex
                        val h = max(m.toFloat() / maxMinutes * barArea.value, 3f)
                        Box(
                            Modifier.weight(1f).height(h.dp).clip(RoundedCornerShape(4.dp))
                                .background(if (isToday) c.accent else if (m > 0) c.accentSoft else c.line),
                        )
                    }
                }
            }
            Box(Modifier.padding(top = 12.dp).fillMaxWidth().height(1.dp).background(c.line))
            Row(Modifier.fillMaxWidth().height(40.dp).clickable { onHistory() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(tr("练习记录"), color = c.text, fontSize = 14.sp, modifier = Modifier.weight(1f))
                if (latest != null) Text("${dayText(latest.startedAt, strings)} · ${formatDuration(strings.locale, max(1, (latest.duration / 60).roundToInt()), MeasureFormat.FormatWidth.NARROW)}", color = c.sub, fontSize = 14.sp, maxLines = 1)
                ChevronRight(c.dim)
            }
        }
    }
}

@Composable
private fun Preferences(settings: Settings, metronome: MetronomeController, onLanguage: () -> Unit, onSound: () -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val naming = settings.noteNaming()
    val languageCode = settings.effectiveLanguage().tag ?: "en"
    CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
        Column {
            Row2(tr("外观")) {
                Box(Modifier.width(190.dp)) {
                    val items = listOf(ThemeMode.SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK)
                    Segmented(listOf(strings.t("系统"), strings.t("浅色"), strings.t("深色")), items.indexOf(settings.themeMode), onSelect = { settings.updateThemeMode(items[it]) })
                }
            }
            Divider()
            Row2(tr("语言"), onClick = onLanguage) {
                Text("${settings.effectiveLanguageOrSystem().flag} ${settings.effectiveLanguage().nativeName}", color = c.sub, fontSize = 15.sp, maxLines = 1)
                ChevronRight(c.dim)
            }
            Divider()
            Row2(tr("音名显示")) {
                Box(Modifier.width(190.dp)) {
                    val styles = listOf(NoteNaming.Style.LETTERS, NoteNaming.Style.SOLFEGE)
                    val labels = styles.map { s -> listOf(0, 2, 4).joinToString(" ") { NoteNaming(s, languageCode).name(it) } }
                    Segmented(labels, styles.indexOf(naming.style), onSelect = {
                        settings.updateNoteNaming(if (styles[it] == NoteNaming.Style.LETTERS) NoteNamingPreference.LETTERS else NoteNamingPreference.SOLFEGE)
                    })
                }
            }
            Divider()
            Row2(tr("节拍音色"), onClick = onSound) {
                Text(strings.t(metronome.config.sound.title), color = c.sub, fontSize = 15.sp, maxLines = 1)
                ChevronRight(c.dim)
            }
            Divider()
            Row2(strings.t("标准音 %@", naming.fullName(com.example.strumcoach.tuner.Pitch(69)))) {
                MiniStepper(settings.a4.roundToInt(), "${settings.a4.roundToInt()} Hz", TunerDefaults.a4Range.start.roundToInt()..TunerDefaults.a4Range.endInclusive.roundToInt()) { settings.updateA4(it.toDouble()) }
            }
            Divider()
            Row2(tr("跟拍震动")) { GreenSwitch(settings.vibrateOnBeat) { settings.updateVibrate(it) } }
            Divider()
            Row2(tr("左手模式")) { GreenSwitch(settings.leftHanded) { settings.updateLeftHanded(it) } }
        }
    }
}

private fun Settings.effectiveLanguageOrSystem(): AppLanguage = if (language == AppLanguage.SYSTEM) AppLanguage.SYSTEM else effectiveLanguage()

@Composable
private fun Row2(title: String, onClick: (() -> Unit)? = null, trailing: @Composable () -> Unit) {
    val c = AppTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 50.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, color = c.text, fontSize = 16.sp, maxLines = 2, modifier = Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { trailing() }
    }
}

@Composable
private fun Divider() {
    val c = AppTheme.colors
    Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(1.dp).background(c.line))
}

@Composable
private fun GreenSwitch(checked: Boolean, onChange: (Boolean) -> Unit) {
    val c = AppTheme.colors
    Switch(
        checked, onChange,
        colors = SwitchDefaults.colors(checkedTrackColor = c.green, checkedThumbColor = androidx.compose.ui.graphics.Color.White, checkedBorderColor = c.green, uncheckedTrackColor = c.card2, uncheckedBorderColor = c.card2, uncheckedThumbColor = androidx.compose.ui.graphics.Color.White),
    )
}

@Composable
private fun MiniStepper(value: Int, display: String, range: IntRange, onChange: (Int) -> Unit) {
    val c = AppTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        StepCircle("−", value > range.first) { onChange(value - 1) }
        Text(display, color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, textAlign = TextAlign.Center, modifier = Modifier.widthIn(min = 58.dp))
        StepCircle("+", value < range.last) { onChange(value + 1) }
    }
}

@Composable
private fun StepCircle(symbol: String, enabled: Boolean, onClick: () -> Unit) {
    val c = AppTheme.colors
    Box(Modifier.size(38.dp).clip(CircleShape).background(c.card2).clickable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Text(symbol, color = if (enabled) c.text else c.dim, fontSize = 20.sp, fontWeight = FontWeight.Light)
    }
}


// 语言 -------------------------------------------------------------------

/** 语言列表：跟随系统和 12 种语言，当前的打勾；点一个就换（立刻生效）。 */
@Composable
private fun LanguageList(settings: Settings, onPick: (AppLanguage) -> Unit) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
        Column {
            AppLanguage.entries.forEachIndexed { i, l ->
                if (i > 0) Divider()
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { onPick(l) }.padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(l.flag, fontSize = 22.sp)
                    Text(if (l == AppLanguage.SYSTEM) strings.t("跟随系统") else l.nativeName, color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    if (settings.language == l) Text("✓", color = c.accent, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

// 练习历史 -----------------------------------------------------------------

@Composable
private fun HistoryList(sessions: List<PracticeSession>, strings: Strings) {
    val c = AppTheme.colors
    CardBox(Modifier.fillMaxWidth(), radius = 18.dp) {
        Column {
            if (sessions.isEmpty()) {
                Box(Modifier.fillMaxWidth().heightIn(min = 62.dp), contentAlignment = Alignment.Center) {
                    Text(tr("还没有练习记录。播放 30 秒以上会自动记一次。"), color = c.sub, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp))
                }
            }
            sessions.forEachIndexed { i, s ->
                if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(c.line))
                Row(Modifier.fillMaxWidth().height(62.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text("${dayText(s.startedAt, strings)} · ${modeTitle(s.mode, strings)}", color = c.text, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                        val arrow = if (s.mode == PracticeMode.RAMP || s.mode == PracticeMode.RAMP_AND_MUTE) "→" else "–"
                        Text(if (s.minBPM == s.maxBPM) "${s.minBPM} BPM" else "${s.minBPM} $arrow ${s.maxBPM} BPM", color = c.sub, fontSize = 12.sp)
                    }
                    Text(formatDuration(strings.locale, max(1, (s.duration / 60).roundToInt()), MeasureFormat.FormatWidth.NARROW), color = c.text, fontSize = 15.sp)
                }
            }
        }
    }
}

private fun modeTitle(mode: PracticeMode, s: Strings) = when (mode) {
    PracticeMode.FREE -> s.t("自由练习")
    PracticeMode.RAMP -> s.t("渐进提速")
    PracticeMode.MUTE -> s.t("静音训练")
    PracticeMode.RAMP_AND_MUTE -> s.t("提速 + 静音")
    PracticeMode.STRUM -> s.t("扫弦节奏型")
}

private fun dayText(instant: Instant, strings: Strings): String {
    val zone = ZoneId.systemDefault()
    val day = instant.atZone(zone).toLocalDate()
    val today = LocalDate.now(zone)
    if (day == today) return strings.t("今天")
    if (day == today.minusDays(1)) return strings.t("昨天")
    val pattern = if (day.year == today.year) "MMMd" else "yMMMd"
    return DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(strings.locale, pattern), strings.locale).format(day)
}

/** 安装包里的版本号（build.gradle.kts 的 versionName），界面上不再写死。 */
@Composable
private fun appVersion(): String {
    val context = LocalContext.current
    return remember(context) {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty()
    }
}

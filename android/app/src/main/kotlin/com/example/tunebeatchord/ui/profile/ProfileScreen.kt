package com.example.tunebeatchord.ui.profile

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.i18n.LocalStrings
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.practice.PracticeLog
import com.example.tunebeatchord.practice.PracticeStatistics
import com.example.tunebeatchord.rhythm.PracticeMode
import com.example.tunebeatchord.settings.AppLanguage
import com.example.tunebeatchord.settings.NoteNamingPreference
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.ui.components.Card
import com.example.tunebeatchord.ui.components.Chip
import com.example.tunebeatchord.ui.components.ScreenTitle
import com.example.tunebeatchord.ui.theme.AppTheme
import com.example.tunebeatchord.ui.theme.ThemeMode
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

private fun duration(seconds: Double): String {
    val m = (seconds / 60).roundToInt()
    return if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m"
}

/** 我的：本周时长、连续打卡、近 7 天柱状图、最近练习。节拍器停止时和扫弦跟练结束时自动记一次（不足 30 秒不记）。 */
@Composable
fun ProfileScreen(log: PracticeLog, settings: Settings, onOpenSettings: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val strings = LocalStrings.current
    val stats = PracticeStatistics(ZoneId.systemDefault(), DayOfWeek.MONDAY)
    val sessions = log.sessions
    val now = Instant.now()
    val days = stats.dailyDurations(sessions, now)
    val maxDay = (days.maxOfOrNull { it.duration } ?: 0.0).coerceAtLeast(60.0)
    val today = days.lastOrNull()
    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        ScreenTitle(tr("我的")) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable { onOpenSettings() }, contentAlignment = Alignment.Center) { Text("⚙", color = c.text, fontSize = 24.sp) }
        }
        Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatCard(tr("本周练习"), duration(stats.weeklyTotal(sessions, now)), Modifier.weight(1f))
            StatCard(tr("连续打卡"), "${stats.currentStreak(sessions, now)}", Modifier.weight(1f))
        }
        Box(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            Card(Modifier.fillMaxWidth()) {
                Column {
                    Text(strings.t("今天已练 %@", duration(today?.duration ?: 0.0)), color = c.sub, fontSize = 14.sp)
                    Canvas(Modifier.fillMaxWidth().height(120.dp).padding(top = 12.dp)) {
                        val slot = size.width / days.size
                        days.forEachIndexed { i, d ->
                            val h = (size.height - 8.dp.toPx()) * (d.duration / maxDay).toFloat()
                            drawRoundRect(if (i == days.lastIndex) c.accent else c.accentSoft, Offset(i * slot + slot * 0.2f, size.height - h.coerceAtLeast(4.dp.toPx())), Size(slot * 0.6f, h.coerceAtLeast(4.dp.toPx())), CornerRadius(6.dp.toPx()))
                        }
                    }
                    Row(Modifier.fillMaxWidth()) {
                        days.forEach { d -> Text(d.day.dayOfWeek.getDisplayName(java.time.format.TextStyle.NARROW, strings.locale), color = c.dim, fontSize = 12.sp, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
                    }
                }
            }
        }
        Text(tr("练习历史"), color = c.sub, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
        val recent = stats.recent(sessions, 20)
        if (recent.isEmpty()) {
            Text(tr("还没有练习记录。播放 30 秒以上会自动记一次。"), color = c.dim, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 20.dp))
        }
        val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).withLocale(strings.locale)
        recent.forEach { s ->
            Box(Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
                Card(Modifier.fillMaxWidth(), padding = 14.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(modeTitle(s.mode, strings), color = c.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            Text(s.startedAt.atZone(ZoneId.systemDefault()).format(formatter), color = c.sub, fontSize = 13.sp)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(duration(s.duration), color = c.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            Text(if (s.minBPM == s.maxBPM) "${s.minBPM} BPM" else "${s.minBPM}–${s.maxBPM} BPM", color = c.sub, fontSize = 13.sp)
                        }
                    }
                }
            }
        }
    }
}

private fun modeTitle(mode: PracticeMode, s: com.example.tunebeatchord.i18n.Strings) = when (mode) {
    PracticeMode.FREE -> s.t("自由练习")
    PracticeMode.RAMP -> s.t("渐进提速")
    PracticeMode.MUTE -> s.t("静音训练")
    PracticeMode.RAMP_AND_MUTE -> s.t("提速 + 静音")
    PracticeMode.STRUM -> s.t("扫弦节奏型")
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier) {
    val c = AppTheme.colors
    Box(modifier) {
        Card(Modifier.fillMaxWidth()) {
            Column {
                Text(label, color = c.sub, fontSize = 14.sp)
                Text(value, color = c.text, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

/** 设置：主题、语言、音名、跟拍震动、左手模式、标准音 A4。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(settings: Settings, onBack: () -> Unit, onLanguageChanged: () -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    val context = LocalContext.current
    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable { onBack() }, contentAlignment = Alignment.Center) { Text("‹", color = c.text, fontSize = 32.sp) }
            Text(tr("设置"), color = c.text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
        SettingsGroup(tr("外观")) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip(tr("跟随系统"), settings.themeMode == ThemeMode.SYSTEM, { settings.updateThemeMode(ThemeMode.SYSTEM) }, height = 40.dp, fontSize = 15)
                Chip(tr("浅色"), settings.themeMode == ThemeMode.LIGHT, { settings.updateThemeMode(ThemeMode.LIGHT) }, height = 40.dp, fontSize = 15)
                Chip(tr("深色"), settings.themeMode == ThemeMode.DARK, { settings.updateThemeMode(ThemeMode.DARK) }, height = 40.dp, fontSize = 15)
            }
        }
        SettingsGroup(tr("语言")) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AppLanguage.entries.forEach { l ->
                    Chip(if (l == AppLanguage.SYSTEM) tr("跟随系统") else l.nativeName, settings.language == l, {
                        if (settings.language != l) { settings.updateLanguage(l); onLanguageChanged() }
                    }, height = 40.dp, fontSize = 15)
                }
            }
        }
        SettingsGroup(tr("音名显示")) {
            val naming = settings.noteNaming()
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip(tr("自动"), settings.noteNamingPreference == NoteNamingPreference.AUTO, { settings.updateNoteNaming(NoteNamingPreference.AUTO) }, height = 40.dp, fontSize = 15)
                Chip(LocalStrings.current.t("字母 %@", "C D E"), settings.noteNamingPreference == NoteNamingPreference.LETTERS, { settings.updateNoteNaming(NoteNamingPreference.LETTERS) }, height = 40.dp, fontSize = 15)
                Chip(LocalStrings.current.t("唱名 %@", "Do Re Mi"), settings.noteNamingPreference == NoteNamingPreference.SOLFEGE, { settings.updateNoteNaming(NoteNamingPreference.SOLFEGE) }, height = 40.dp, fontSize = 15)
            }
            Text("${naming.name(0)} ${naming.name(2)} ${naming.name(4)} ${naming.name(11)}", color = c.sub, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp))
        }
        SettingsGroup(tr("偏好设置")) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(tr("左手模式"), color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f)); Switch(settings.leftHanded, { settings.updateLeftHanded(it) })
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(tr("跟拍震动"), color = c.text, fontSize = 16.sp, modifier = Modifier.weight(1f)); Switch(settings.vibrateOnBeat, { settings.updateVibrate(it) })
            }
        }
        SettingsGroup(tr("标准音")) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Chip("−", false, { settings.updateA4(settings.a4 - 1) }, Modifier.size(46.dp), 46.dp)
                Text("A4 = ${settings.a4.roundToInt()} Hz", color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Chip("+", false, { settings.updateA4(settings.a4 + 1) }, Modifier.size(46.dp), 46.dp)
            }
        }
        Text(tr("版本") + " 1.0 · Apache-2.0", color = c.dim, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp))
    }
}

@Composable
private fun SettingsGroup(title: String, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Text(title, color = c.sub, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp))
        Card(Modifier.fillMaxWidth(), padding = 14.dp) { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { content() } }
    }
}

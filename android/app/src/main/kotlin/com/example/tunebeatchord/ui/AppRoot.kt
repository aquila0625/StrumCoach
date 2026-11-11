package com.example.tunebeatchord.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tunebeatchord.AppContainer
import com.example.tunebeatchord.i18n.tr
import com.example.tunebeatchord.ui.chords.ChordLibraryScreen
import com.example.tunebeatchord.ui.components.ScreenBackground
import com.example.tunebeatchord.ui.components.TabIcon
import com.example.tunebeatchord.ui.components.TabIconView
import com.example.tunebeatchord.ui.metronome.MetronomeScreen
import com.example.tunebeatchord.ui.profile.ProfileScreen
import com.example.tunebeatchord.ui.theme.AppTheme
import com.example.tunebeatchord.ui.training.StrumScreen
import com.example.tunebeatchord.ui.training.TrainingScreen
import com.example.tunebeatchord.ui.tuner.TunerScreen

enum class AppTab(val key: String, val icon: TabIcon) {
    TRAINING("训练", TabIcon.TRAIN),
    METRONOME("节拍器", TabIcon.METRONOME),
    TUNER("调音器", TabIcon.TUNER),
    CHORDS("和弦库", TabIcon.CHORD),
    PROFILE("我的", TabIcon.ME),
}

@Composable
fun AppRoot(container: AppContainer, onLanguageChanged: () -> Unit) {
    var tab by rememberSaveable { mutableStateOf(AppTab.METRONOME.name) }
    var strumOpen by rememberSaveable { mutableStateOf(false) }
    var strumAutoStart by rememberSaveable { mutableStateOf(false) }
    val current = AppTab.valueOf(tab)
    ScreenBackground {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth().statusBarsPadding()) {
                when (current) {
                    AppTab.TRAINING ->
                        if (strumOpen) StrumScreen(container.strumTrainer, container.settings, container.metronome, container.chordLibrary, container.chordPlayer, autoStart = strumAutoStart, onBack = { strumOpen = false; strumAutoStart = false })
                        else TrainingScreen(container.strumTrainer, container.metronome, container.settings, container.chordLibrary, container.chordPlayer, onOpenStrum = { start -> container.metronome.stop(); strumAutoStart = start; strumOpen = true })
                    AppTab.METRONOME -> MetronomeScreen(container.metronome, onOpenTraining = { tab = AppTab.TRAINING.name })
                    AppTab.TUNER -> TunerScreen(container.tuner, container.settings, active = true, onEnter = { container.metronome.stop() })
                    AppTab.CHORDS -> ChordLibraryScreen(container.chordLibrary, container.settings, container.chordPlayer)
                    AppTab.PROFILE -> ProfileScreen(container.practiceLog, container.settings, container.metronome, onLanguageChanged)
                }
            }
            NoticeBanner(container.metronome)
            TabBar(current) { strumOpen = false; tab = it.name }
        }
    }
}

@Composable
private fun TabBar(selected: AppTab, onSelect: (AppTab) -> Unit) {
    val c = AppTheme.colors
    Row(Modifier.fillMaxWidth().background(c.tabBg).windowInsetsPadding(WindowInsets.navigationBars).padding(vertical = 6.dp)) {
        AppTab.entries.forEach { t ->
            val on = t == selected
            Column(
                Modifier.weight(1f).clickable(role = Role.Tab) { onSelect(t) }.padding(vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                TabIconView(t.icon, if (on) c.accent else c.dim)
                Text(tr(t.key), color = if (on) c.accent else c.dim, fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}

/** 节拍器自己停下来或练习目标达成时，在标签栏上方显示几秒的提示（iOS 版的 showBanner）。 */
@Composable
private fun NoticeBanner(metronome: com.example.tunebeatchord.metronome.MetronomeController) {
    val c = AppTheme.colors
    val strings = com.example.tunebeatchord.i18n.LocalStrings.current
    val notice = metronome.notice
    androidx.compose.runtime.LaunchedEffect(notice) {
        if (notice != null) { kotlinx.coroutines.delay(4000); metronome.notice = null }
    }
    if (notice == null) return
    val goal = metronome.options.timerMinutes
    val text = when (notice) {
        com.example.tunebeatchord.metronome.MetronomeController.Notice.RAMP_FINISHED -> strings.t("渐进提速完成，已停止")
        com.example.tunebeatchord.metronome.MetronomeController.Notice.TIMER_REACHED_STOPPED -> strings.t("今天已练够 %@，已自动停止", minutesLabel(goal))
        com.example.tunebeatchord.metronome.MetronomeController.Notice.TIMER_REACHED -> strings.t("今天已练够 %@", minutesLabel(goal))
    }
    Box(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 8.dp), contentAlignment = Alignment.Center) {
        Text(
            text, color = c.text, fontSize = 14.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
            modifier = Modifier.clip(androidx.compose.foundation.shape.RoundedCornerShape(50)).background(c.sheet).clickable { metronome.notice = null }.padding(horizontal = 18.dp, vertical = 10.dp),
        )
    }
}

@Composable
private fun minutesLabel(v: Int): String {
    val locale = androidx.compose.ui.platform.LocalContext.current.resources.configuration.locales[0]
    val fmt = android.icu.text.MeasureFormat.getInstance(locale, android.icu.text.MeasureFormat.FormatWidth.SHORT)
    val parts = buildList {
        if (v / 60 > 0) add(android.icu.util.Measure(v / 60, android.icu.util.MeasureUnit.HOUR))
        if (v % 60 > 0 || v / 60 == 0) add(android.icu.util.Measure(v % 60, android.icu.util.MeasureUnit.MINUTE))
    }
    return fmt.formatMeasures(*parts.toTypedArray())
}

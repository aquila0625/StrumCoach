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
    val current = AppTab.valueOf(tab)
    ScreenBackground {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth().statusBarsPadding()) {
                when (current) {
                    AppTab.TRAINING ->
                        if (strumOpen) StrumScreen(container.strumTrainer, container.settings, onBack = { strumOpen = false })
                        else TrainingScreen(container.strumTrainer, container.metronome, onOpenStrum = { container.metronome.stop(); strumOpen = true })
                    AppTab.METRONOME -> MetronomeScreen(container.metronome, onOpenTraining = { tab = AppTab.TRAINING.name })
                    AppTab.TUNER -> TunerScreen(container.tuner, container.settings, active = true, onEnter = { container.metronome.stop() })
                    AppTab.CHORDS -> ChordLibraryScreen(container.chordLibrary, container.settings, onPlay = { container.playChord(it) })
                    AppTab.PROFILE -> ProfileScreen(container.practiceLog, container.settings, container.metronome, onLanguageChanged)
                }
            }
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

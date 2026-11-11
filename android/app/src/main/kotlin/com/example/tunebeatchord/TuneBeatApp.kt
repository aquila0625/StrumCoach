package com.example.tunebeatchord

import android.app.Application
import com.example.tunebeatchord.audio.AssetSampleLoader
import com.example.tunebeatchord.audio.AudioEngine
import com.example.tunebeatchord.audio.ChordSound
import com.example.tunebeatchord.audio.SampleBank
import com.example.tunebeatchord.chord.ChordLibraryState
import com.example.tunebeatchord.metronome.MetronomeController
import com.example.tunebeatchord.practice.PracticeLog
import com.example.tunebeatchord.settings.FileStore
import com.example.tunebeatchord.settings.PrefsStore
import com.example.tunebeatchord.settings.Settings
import com.example.tunebeatchord.strum.StrumTrainer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import com.example.tunebeatchord.tuner.InstrumentSelection
import com.example.tunebeatchord.tuner.TunerController
import com.example.tunebeatchord.tuner.TunerModel

/** 全 App 共用的状态：设置、和弦库选择等。都只存在本机。 */
class TuneBeatApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

class AppContainer(app: Application) {
    val settings = Settings(app)
    val chordLibrary = ChordLibraryState(PrefsStore(app, "chords"))
    val engine = AudioEngine(app)
    val practiceLog = PracticeLog(FileStore(java.io.File(app.filesDir, "practice")))
    val metronome = MetronomeController(engine, PrefsStore(app, "metronome"), practiceLog).also { m ->
        val vibrator = app.getSystemService(android.os.Vibrator::class.java)
        m.onGoalReached = {
            if (vibrator?.hasVibrator() == true) vibrator.vibrate(android.os.VibrationEffect.createWaveform(longArrayOf(0, 80, 70, 80, 70, 160), -1))
        }
        m.onMainBeat = { beat ->
            // 跟拍震动：首拍重一点
            if (settings.vibrateOnBeat && vibrator?.hasVibrator() == true) {
                vibrator.vibrate(android.os.VibrationEffect.createOneShot(if (beat == 0) 28 else 16, if (beat == 0) 200 else 110))
            }
        }
    }

    /** 乐器采样库：第一次用到时才从 assets 读 manifest，每段采样用到时才解码。 */
    val sampleBank: SampleBank? by lazy {
        runCatching { AssetSampleLoader(app).let { loader -> SampleBank(loader.manifestJson(), loader::load) } }.getOrNull()
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val strumTrainer: StrumTrainer by lazy {
        StrumTrainer(app, engine, chordSound, practiceLog, PrefsStore(app, "strum"), scope, naming = { settings.noteNaming() },
            customRhythms = { family -> chordLibrary.customRhythms(family).mapNotNull { it.rhythm } })
    }
    val tuner: TunerController by lazy {
        TunerController(engine, { sampleBank }, TunerModel(InstrumentSelection.Default, settings.a4, PrefsStore(app, "tuner")))
    }
    val chordSound: ChordSound by lazy { ChordSound(engine, sampleBank) }
    val chordPlayer: com.example.tunebeatchord.chord.ChordPlayer by lazy {
        com.example.tunebeatchord.chord.ChordPlayer(engine, chordSound, chordLibrary, scope, { settings.a4 }, { metronome.bpm })
    }
}

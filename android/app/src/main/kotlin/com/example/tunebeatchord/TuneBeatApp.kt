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
        StrumTrainer(app, engine, chordSound, practiceLog, PrefsStore(app, "strum"), scope, naming = { settings.noteNaming() })
    }
    val tuner: TunerController by lazy {
        TunerController(engine, { sampleBank }, TunerModel(InstrumentSelection.Default, settings.a4, PrefsStore(app, "tuner")))
    }
    val chordSound: ChordSound by lazy { ChordSound(engine, sampleBank) }

    /** 和弦库“试听”：按当前选的扫弦节奏型或一次下扫，把这个和弦的当前把位扫一遍；再点一次停止。 */
    fun playChord(state: ChordLibraryState) {
        val voicing = state.voicing
        val voice = com.example.tunebeatchord.audio.Voice.fromFamily(state.instrument.family)
        if (state.isBass) {
            // 贝斯：依次弹根音、三度、五度、八度
            val p = state.bassPositions ?: return
            val root = p.anchor?.pitch ?: return
            val third = p.markers(com.example.tunebeatchord.chord.BassPositions.Role.THIRD).firstOrNull()?.pitch
            val fifth = p.markers(com.example.tunebeatchord.chord.BassPositions.Role.FIFTH).firstOrNull()?.pitch
            val notes = listOfNotNull(root, third, fifth, root.transposed(12))
            chordSound.play(com.example.tunebeatchord.chord.ChordPlayback(
                notes.mapIndexed { i, pitch -> com.example.tunebeatchord.chord.PluckEvent(i * 0.45, i, pitch, 0.5f) }, voice, settings.a4, 1.5))
            return
        }
        voicing ?: return
        chordSound.play(com.example.tunebeatchord.chord.RhythmStrum.playback(voicing, com.example.tunebeatchord.chord.StrumCell.DOWN, state.chord.root, 1f, voice, settings.a4))
    }
}

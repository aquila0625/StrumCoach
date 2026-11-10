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
    val metronome = MetronomeController(engine, PrefsStore(app, "metronome"), practiceLog)

    /** 乐器采样库：第一次用到时才从 assets 读 manifest，每段采样用到时才解码。 */
    val sampleBank: SampleBank? by lazy {
        runCatching { AssetSampleLoader(app).let { loader -> SampleBank(loader.manifestJson(), loader::load) } }.getOrNull()
    }
    val chordSound: ChordSound by lazy { ChordSound(engine, sampleBank) }
}

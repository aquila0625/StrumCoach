package com.example.tunebeatchord

import android.app.Application
import com.example.tunebeatchord.chord.ChordLibraryState
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
}

package com.example.strumcoach

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Bundle
import android.os.LocaleList
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import com.example.strumcoach.i18n.LocalStrings
import com.example.strumcoach.i18n.Strings
import com.example.strumcoach.settings.Settings
import com.example.strumcoach.ui.AppRoot
import com.example.strumcoach.ui.theme.TuneBeatTheme

class MainActivity : ComponentActivity() {

    /** 按设置里的界面语言包一层 Context；换语言后 recreate() 就会重新走这里。 */
    override fun attachBaseContext(base: Context) {
        val settings = Settings(base)
        val locale = settings.effectiveLanguage(Resources.getSystem().configuration.locales[0]).locale(Resources.getSystem().configuration.locales[0])
        val config = Configuration(base.resources.configuration)
        config.setLocales(LocaleList(locale))
        super.attachBaseContext(base.createConfigurationContext(config))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as TuneBeatApp).container
        setContent {
            val strings = remember { Strings(resources) }
            CompositionLocalProvider(LocalStrings provides strings) {
                TuneBeatTheme(container.settings.themeMode) {
                    AppRoot(container, onLanguageChanged = { recreate() })
                }
            }
        }
    }
}

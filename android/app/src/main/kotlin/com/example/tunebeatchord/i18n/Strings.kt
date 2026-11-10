package com.example.tunebeatchord.i18n

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import java.util.Locale

/**
 * 取译文。和 iOS 一样，界面里直接用简体中文原文当键（`strings.t("强")`），
 * 译文由 `tools/l10n_to_android.py` 从 iOS 的译文生成。
 *
 * 占位符：iOS 的 %@ / %lld 已转成 %s / %d；复数键用 [plural]。
 * 找不到键时返回原文（调试时一眼能看出漏了），`StringsCoverageTest` 保证源码里的键都在表里。
 */
class Strings(private val resources: Resources) {
    val locale: Locale get() = resources.configuration.locales[0]

    fun t(key: String, vararg args: Any?): String {
        val id = StringTable.strings[key] ?: return fallback(key, args)
        return runCatching { resources.getString(id, *args) }.getOrElse { key }
    }

    fun plural(key: String, count: Int, vararg args: Any?): String {
        val id = StringTable.plurals[key] ?: return fallback(key, arrayOf(count, *args))
        return runCatching { resources.getQuantityString(id, count, count, *args) }.getOrElse { key }
    }

    private fun fallback(key: String, args: Array<out Any?>): String {
        if (args.isEmpty()) return key
        var i = 0
        return Regex("%(?:\\d+\\$)?(@|lld|d|s)").replace(key) { args.getOrNull(i++).toString() }
    }
}

val LocalStrings = compositionLocalOf<Strings> { error("Strings 没有提供") }

/** 在 Compose 里取译文：`tr("节拍器")`、`tr("%lld 小节", 3)`（占位符按参数顺序填）。 */
@Composable
fun tr(key: String, vararg args: Any?): String = LocalStrings.current.t(key, *args)

@Composable
fun trPlural(key: String, count: Int, vararg args: Any?): String = LocalStrings.current.plural(key, count, *args)

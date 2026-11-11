package com.example.strumcoach.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * 设计令牌，数值沿用 iOS 版（Theme.swift）。
 * 背景、卡片、主按钮都用同色系的渐变，不用大面积平涂的纯色。
 */
@Immutable
class AppColors(
    val isLight: Boolean,
    val bgTop: Color,
    val bgBottom: Color,
    val glow: Color,
    val cardTop: Color,
    val cardBottom: Color,
    val card2: Color,
    val line: Color,
    val text: Color,
    val sub: Color,
    val dim: Color,
    val accent: Color,
    val accentLight: Color,
    val accentDark: Color,
    val accentTint: Color,
    val accentSoft: Color,
    val weak: Color,
    val track: Color,
    val green: Color,
    val tabBg: Color,
    val sheet: Color,
    val sheetCard: Color,
    val tick: Color,
    val weakNow: Color,
    val scrim: Color,
    val onAccent: Color,
) {
    val background: Brush get() = Brush.verticalGradient(listOf(bgTop, bgBottom))
    val card: Brush get() = Brush.verticalGradient(listOf(cardTop, cardBottom))
    val accentBrush: Brush get() = Brush.linearGradient(listOf(accentLight, accentDark))
}

val DarkColors = AppColors(
    isLight = false,
    bgTop = Color(0xFF181A1F), bgBottom = Color(0xFF0E0F12), glow = Color(0xFFFF7A1A).copy(alpha = 0.10f),
    cardTop = Color(0xFF1F2227), cardBottom = Color(0xFF1A1C21), card2 = Color(0xFF22252B), line = Color(0xFF2A2D34),
    text = Color(0xFFF5F5F7), sub = Color(0xFF9A9AA0), dim = Color(0xFF6A6D76),
    accent = Color(0xFFFF7A1A), accentLight = Color(0xFFFF8E3A), accentDark = Color(0xFFF26B0F),
    accentTint = Color(0xFFFF7A1A).copy(alpha = 0.10f), accentSoft = Color(0xFFFF7A1A).copy(alpha = 0.35f),
    weak = Color(0xFF3A3D45), track = Color(0xFF23262C), green = Color(0xFF34C759),
    tabBg = Color(0xFF141519).copy(alpha = 0.96f), sheet = Color(0xFF17191D), sheetCard = Color(0xFF1A1C21), tick = Color(0xFF33363D),
    weakNow = Color(0xFF7A7F8C), scrim = Color.Black.copy(alpha = 0.55f), onAccent = Color(0xFF1A0E04),
)

val LightColors = AppColors(
    isLight = true,
    bgTop = Color(0xFFFBF8F3), bgBottom = Color(0xFFF1EEE9), glow = Color(0xFFF26B0F).copy(alpha = 0.10f),
    cardTop = Color(0xFFFFFFFF).copy(alpha = 0.92f), cardBottom = Color(0xFFFFFCF8).copy(alpha = 0.72f),
    card2 = Color(0xFFEDEBE8), line = Color(0xFFE4E1DD),
    text = Color(0xFF16171A), sub = Color(0xFF6E6E73), dim = Color(0xFFA6A4A0),
    accent = Color(0xFFF26B0F), accentLight = Color(0xFFFF8A3A), accentDark = Color(0xFFE85F06),
    accentTint = Color(0xFFF26B0F).copy(alpha = 0.09f), accentSoft = Color(0xFFF26B0F).copy(alpha = 0.28f),
    weak = Color(0xFFD8D5D0), track = Color(0xFFECEAE6), green = Color(0xFF28A745),
    tabBg = Color(0xFFFFFCF8).copy(alpha = 0.92f), sheet = Color(0xFFFFFFFF), sheetCard = Color(0xFFF3F1EE), tick = Color(0xFFDCD9D4),
    weakNow = Color(0xFFA8A49D), scrim = Color(0xFF141414).copy(alpha = 0.28f), onAccent = Color(0xFFFFFFFF),
)

val LocalColors = staticCompositionLocalOf { DarkColors }

/** 主题偏好：跟随系统 / 浅色 / 深色。 */
enum class ThemeMode(val id: String) {
    SYSTEM("system"), LIGHT("light"), DARK("dark");

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: SYSTEM
    }
}

@Composable
fun TuneBeatTheme(mode: ThemeMode = ThemeMode.SYSTEM, content: @Composable () -> Unit) {
    val light = when (mode) {
        ThemeMode.SYSTEM -> !isSystemInDarkTheme()
        ThemeMode.LIGHT -> true
        ThemeMode.DARK -> false
    }
    val colors = if (light) LightColors else DarkColors
    val scheme = if (light) {
        lightColorScheme(primary = colors.accent, onPrimary = colors.onAccent, background = colors.bgBottom,
            surface = colors.sheet, onSurface = colors.text, onBackground = colors.text)
    } else {
        darkColorScheme(primary = colors.accent, onPrimary = colors.onAccent, background = colors.bgBottom,
            surface = colors.sheet, onSurface = colors.text, onBackground = colors.text)
    }
    CompositionLocalProvider(LocalColors provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

object AppTheme {
    val colors: AppColors
        @Composable get() = LocalColors.current
}

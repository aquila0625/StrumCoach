package com.example.tunebeatchord.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.tunebeatchord.ui.theme.AppTheme

/** iOS 版的 `.card(radius:)`：渐变底、可选描边。 */
@Composable
fun CardBox(modifier: Modifier = Modifier, radius: Dp = 20.dp, border: Boolean = false, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    val shape = RoundedCornerShape(radius)
    Box(
        modifier.clip(shape).background(c.card)
            .then(if (border) Modifier.border(1.dp, c.line, shape) else Modifier),
        contentAlignment = Alignment.Center,
    ) { content() }
}

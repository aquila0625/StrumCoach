package com.example.strumcoach.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.strumcoach.ui.theme.AppTheme

/** 页面背景：很淡的渐变加一团主色光晕，不是平涂的纯色。 */
@Composable
fun ScreenBackground(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Box(
        modifier
            .fillMaxSize()
            .background(c.background)
            .background(Brush.radialGradient(listOf(c.glow, Color.Transparent), radius = 900f, center = androidx.compose.ui.geometry.Offset(900f, 0f))),
    ) { content() }
}

@Composable
fun Card(modifier: Modifier = Modifier, padding: Dp = 16.dp, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Box(
        modifier
            .clip(RoundedCornerShape(24.dp))
            .background(c.card)
            .border(1.dp, c.line.copy(alpha = if (c.isLight) 0.6f else 0.5f), RoundedCornerShape(24.dp))
            .padding(padding),
    ) { content() }
}

@Composable
fun ScreenTitle(text: String, modifier: Modifier = Modifier, trailing: @Composable () -> Unit = {}) {
    Row(modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, color = AppTheme.colors.text, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        trailing()
    }
}

/** 胶囊按钮：选中时是主色渐变，没选中是浅色底。 */
@Composable
fun Chip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    height: Dp = 40.dp,
    shape: Shape = RoundedCornerShape(50),
    fontSize: Int = 16,
    horizontalPadding: Dp = 14.dp,
) {
    val c = AppTheme.colors
    Box(
        modifier
            .height(height)
            .clip(shape)
            .background(if (selected) c.accentBrush else Brush.verticalGradient(listOf(c.card2, c.card2)))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = horizontalPadding),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            noteAnnotated(text), color = if (selected) c.onAccent else c.text, fontSize = fontSize.sp,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, maxLines = 1,
        )
    }
}

/** 分段控件（iOS 版的 Segmented）：浅色底圆角 12、内边距 3，选中的那段是主色圆角 9。 */
@Composable
fun Segmented(items: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card2).padding(3.dp),
    ) {
        items.forEachIndexed { i, label ->
            val on = i == selectedIndex
            Box(
                Modifier.weight(1f).height(38.dp).clip(RoundedCornerShape(9.dp))
                    .background(if (on) c.accentBrush else Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent)))
                    .clickable(role = Role.Tab) { onSelect(i) }.padding(horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    noteAnnotated(label), color = if (on) Color.White else c.sub, fontSize = 16.sp,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, maxLines = 2, textAlign = androidx.compose.ui.text.style.TextAlign.Center, lineHeight = 17.sp,
                )
            }
        }
    }
}

@Composable
fun CircleButton(size: Dp, onClick: () -> Unit, description: String, filled: Boolean = true, content: @Composable () -> Unit) {
    val c = AppTheme.colors
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(if (filled) c.accentBrush else Brush.verticalGradient(listOf(c.card2, c.card2)))
            .semantics { contentDescription = description }
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

val ScreenPadding = PaddingValues(horizontal = 20.dp)
@Composable
fun Section(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) {
        Text(title, color = AppTheme.colors.sub, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp))
        content()
    }
}

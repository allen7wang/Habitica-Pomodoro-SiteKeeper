package com.habitica.pomodoro.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// 番茄红 / 专注蓝 —— 与 macOS 版视觉基调一致
private val TomatoRed = Color(0xFFE8534F)
private val FocusBlue = Color(0xFF4A90D9)
private val LeafGreen = Color(0xFF4CAF7D)

private val LightColors = lightColorScheme(
    primary = TomatoRed,
    secondary = FocusBlue,
    tertiary = LeafGreen,
)

private val DarkColors = darkColorScheme(
    primary = TomatoRed,
    secondary = FocusBlue,
    tertiary = LeafGreen,
)

@Composable
fun HabiticaPomodoroTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}

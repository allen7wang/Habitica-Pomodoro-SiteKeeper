package com.habitica.pomodoro.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.habitica.pomodoro.engine.PomodoroViewModel
import com.habitica.pomodoro.engine.PomodoroViewModel.Phase
import com.habitica.pomodoro.engine.PomodoroViewModel.UiState
import java.util.Locale

/** 番茄钟主页：圆环计时器 + 主控制按钮 + 今日统计 */
@Composable
fun PomoScreen(
    vm: PomodoroViewModel,
    state: UiState,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Spacer(Modifier.height(8.dp))

        Text(
            text = phaseLabel(state.phase),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        TimerRing(
            remainingSeconds = state.remainingSeconds,
            totalSeconds = state.totalSeconds,
            isRunning = state.isRunning,
            phase = state.phase,
            onClick = { vm.activate() },
        )

        ControlButtons(state = state, vm = vm)

        StatsCard(state = state)
    }
}

@Composable
private fun phaseLabel(phase: Phase): String = when (phase) {
    Phase.IDLE -> "准备开始"
    Phase.POMODORO -> "专注中"
    Phase.BREAK -> "休息中"
    Phase.LONG_BREAK -> "长休息中"
    Phase.MANUAL_BREAK -> "该休息了，点击开始休息"
}

/** 圆环计时器：点击圆环即启动/暂停（与 iOS 端交互一致） */
@Composable
private fun TimerRing(
    remainingSeconds: Int,
    totalSeconds: Int,
    isRunning: Boolean,
    phase: Phase,
    onClick: () -> Unit,
) {
    val progress = if (totalSeconds > 0) {
        1f - (remainingSeconds.toFloat() / totalSeconds.toFloat())
    } else {
        0f
    }
    val animatedProgress by animateFloatAsState(
        targetValue = progress,
        animationSpec = tween(durationMillis = 400),
        label = "ring",
    )
    val ringColor = when (phase) {
        Phase.POMODORO -> MaterialTheme.colorScheme.primary
        Phase.BREAK, Phase.LONG_BREAK -> MaterialTheme.colorScheme.tertiary
        Phase.MANUAL_BREAK -> MaterialTheme.colorScheme.secondary
        Phase.IDLE -> MaterialTheme.colorScheme.outlineVariant
    }

    Box(
        modifier = Modifier
            .size(240.dp),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val stroke = 14.dp.toPx()
            val diameter = size.minDimension - stroke
            val topLeft = (size.width - diameter) / 2f
            // 背景轨道
            drawArc(
                color = Color(0x22808080),
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = androidx.compose.ui.geometry.Offset(topLeft, topLeft),
                size = Size(diameter, diameter),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
            // 进度弧
            drawArc(
                color = ringColor,
                startAngle = -90f,
                sweepAngle = 360f * animatedProgress,
                useCenter = false,
                topLeft = androidx.compose.ui.geometry.Offset(topLeft, topLeft),
                size = Size(diameter, diameter),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = formatTime(remainingSeconds),
                fontSize = 52.sp,
                fontWeight = FontWeight.Light,
                letterSpacing = 2.sp,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = if (isRunning) "点击圆环暂停" else if (remainingSeconds > 0) "点击圆环继续" else "点击圆环开始",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // 透明点击层（覆盖整个圆环区域）：无涟漪效果，避免盖住圆环视觉
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClick,
                ),
        )
    }
}

@Composable
private fun ControlButtons(state: UiState, vm: PomodoroViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
    ) {
        Button(
            onClick = { vm.activate() },
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(16.dp),
        ) {
            Text(
                text = when {
                    !state.isRunning && state.phase == Phase.IDLE -> "开始番茄"
                    !state.isRunning && state.phase == Phase.MANUAL_BREAK -> "开始休息"
                    state.isRunning -> "暂停"
                    else -> "继续"
                },
                fontSize = 16.sp,
            )
        }

        if (state.phase == Phase.BREAK || state.phase == Phase.LONG_BREAK) {
            OutlinedButton(
                onClick = { vm.skipBreak() },
                modifier = Modifier.weight(0.6f),
                shape = RoundedCornerShape(16.dp),
            ) { Text("跳过休息") }
        }

        if (state.phase != Phase.IDLE) {
            OutlinedButton(
                onClick = { vm.stop() },
                modifier = Modifier.weight(0.5f),
                shape = RoundedCornerShape(16.dp),
            ) { Text("结束") }
        }
    }
}

@Composable
private fun StatsCard(state: UiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("今日番茄", style = MaterialTheme.typography.bodyMedium)
                Text(
                    text = "${state.todayPomodoros} 个",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("本组进度", style = MaterialTheme.typography.bodyMedium)
                Text(
                    text = "${state.pomoSetCounter} / ${state.settings.pomoSetNum}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            state.profile?.let { p ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Habitica", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        text = "Lv.${p.level} · ♥ ${p.hp.toInt()} · ✦ ${p.gp.toInt()}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            if (state.habiticaBusy) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 2.dp)
                    Text(
                        text = "  正在同步 Habitica…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            state.message?.let { msg ->
                Text(
                    text = msg,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

fun formatTime(totalSeconds: Int): String {
    val safe = totalSeconds.coerceAtLeast(0)
    val m = safe / 60
    val s = safe % 60
    return String.format(Locale.US, "%02d:%02d", m, s)
}

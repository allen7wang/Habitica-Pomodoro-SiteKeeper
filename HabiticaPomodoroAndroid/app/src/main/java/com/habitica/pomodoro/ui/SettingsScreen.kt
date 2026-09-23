package com.habitica.pomodoro.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.habitica.pomodoro.engine.PomodoroViewModel
import com.habitica.pomodoro.engine.PomodoroViewModel.UiState

/**
 * 设置页。所有改动即时保存（与 iOS 端 didSet 自动保存行为一致，无需"保存"按钮）。
 *
 * 注意：Android 无法访问 iCloud Drive（Apple 不向非苹果平台开放），
 * 因此本机设置/历史存在应用私有目录，任务与习惯经 Habitica 云端跨端一致。
 */
@Composable
fun SettingsScreen(
    vm: PomodoroViewModel,
    state: UiState,
    modifier: Modifier = Modifier,
) {
    val s = state.settings
    var showToken by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("设置", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)

        // MARK: Habitica
        SettingsCard(title = "Habitica") {
            SwitchRow(
                label = "连接 Habitica",
                checked = s.connectHabitica,
                onCheckedChange = { v -> vm.updateSettings { it.connectHabitica = v } },
            )
            if (s.connectHabitica) {
                OutlinedTextField(
                    value = s.uid,
                    onValueChange = { v -> vm.updateSettings { it.uid = v } },
                    label = { Text("User ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = s.apiToken,
                    onValueChange = { v -> vm.updateSettings { it.apiToken = v } },
                    label = { Text("API Token") },
                    singleLine = true,
                    visualTransformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
                    supportingText = {
                        Text(
                            if (showToken) "点击隐藏 Token" else "点击右侧按钮可临时显示",
                        )
                    },
                    trailingIcon = {
                        androidx.compose.material3.TextButton(onClick = { showToken = !showToken }) {
                            Text(if (showToken) "隐藏" else "显示")
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = "获取方式：Habitica 网站 → Settings → API",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = { vm.refreshProfile() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = s.uid.isNotBlank() && s.apiToken.isNotBlank(),
                ) { Text("测试连接并刷新角色") }
                state.profileError?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                state.profile?.let { p ->
                    Text(
                        text = "✓ 已连接：${p.username.ifEmpty { "—" }} (Lv.${p.level})",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
        }

        // MARK: 番茄钟
        SettingsCard(title = "番茄钟") {
            StepperRow(
                label = "番茄时长",
                value = s.pomoDurationMins,
                range = 1..120,
                suffix = "分钟",
                onChange = { v -> vm.updateSettings { it.pomoDurationMins = v } },
            )
            StepperRow(
                label = "短休息",
                value = s.breakDuration,
                range = 1..60,
                suffix = "分钟",
                onChange = { v -> vm.updateSettings { it.breakDuration = v } },
            )
            StepperRow(
                label = "长休息",
                value = s.longBreakDuration,
                range = 1..120,
                suffix = "分钟",
                onChange = { v -> vm.updateSettings { it.longBreakDuration = v } },
            )
            StepperRow(
                label = "长休息间隔",
                value = s.pomoSetNum,
                range = 1..12,
                suffix = "个番茄",
                onChange = { v -> vm.updateSettings { it.pomoSetNum = v } },
            )
            HorizontalDivider()
            SwitchRow(
                label = "手动开始休息",
                checked = s.manualBreak,
                onCheckedChange = { v -> vm.updateSettings { it.manualBreak = v } },
            )
            Text(
                text = if (s.manualBreak) "番茄结束后等你点击才开始休息" else "番茄结束后自动进入休息",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // MARK: 提醒声音
        SettingsCard(title = "提醒声音") {
            Text(
                text = "番茄结束音：${if (s.pomoEndSound == "None") "系统默认" else s.pomoEndSound}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = "音量 ${String.format(java.util.Locale.US, "%.0f%%", s.pomoEndSoundVolume * 100)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Slider(
                value = s.pomoEndSoundVolume.toFloat(),
                onValueChange = { v -> vm.updateSettings { it.pomoEndSoundVolume = v.toDouble() } },
                valueRange = 0f..1f,
            )
            Text(
                text = "阶段结束的提醒通过通知栏发送，锁屏也能看到。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // MARK: 数据
        SettingsCard(title = "数据") {
            Text(
                text = "存储位置：应用私有目录",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = vm.dataDirectoryPath(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            HorizontalDivider()
            Text(
                text = "跨端同步说明",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Android 无法访问 iCloud Drive（Apple 不向非苹果平台开放该目录），" +
                    "所以 Mac/iPhone 之间共用的那批本地 JSON 在 Android 上读不到。" +
                    "Android 端的任务与完成状态通过 Habitica 云端同步：Task 页每条任务对应一个 " +
                    "Habitica todo，分类名对应 tag，完成/取消会实时打分。" +
                    "因此三端的任务数据一致，本机设置与番茄历史各自保存在本机。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // MARK: 关于
        SettingsCard(title = "关于") {
            Text("Habitica Pomodoro for Android · v1.0.0", style = MaterialTheme.typography.bodyMedium)
            Text(
                text = "与 macOS / iOS 版同一套业务规则：逻辑日以第一个时间块起点（默认 04:00）为界，" +
                    "Work/MyOwn 各限 3 条、Chores 自由列表，昨天未完成任务可顺延到今天。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            content()
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun StepperRow(
    label: String,
    value: Int,
    range: IntRange,
    suffix: String,
    onChange: (Int) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.TextButton(
                onClick = { if (value > range.first) onChange(value - 1) },
                enabled = value > range.first,
            ) { Text("−") }
            Text(
                text = "$value $suffix",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
            androidx.compose.material3.TextButton(
                onClick = { if (value < range.last) onChange(value + 1) },
                enabled = value < range.last,
            ) { Text("+") }
        }
    }
}

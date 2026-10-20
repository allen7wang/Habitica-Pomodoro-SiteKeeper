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
import androidx.compose.material3.*
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import com.habitica.pomodoro.service.PomoAudio
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.isValidHabiticaUid
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
 * 设置页。一般选项即时保存；User ID 和自定义 API 地址校验后明确应用。
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
    var uidDraft by remember(s.uid) { mutableStateOf(s.uid) }
    var uidError by remember(s.uid) { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val preview = remember { PomoAudio(context.applicationContext) }
    DisposableEffect(preview) { onDispose { preview.stopAll(); vm.refreshRuntimeAudio() } }
    var serverDraft by remember(s.developerServerUrl) { mutableStateOf(s.developerServerUrl) }
    var confirmServer by remember { mutableStateOf(false) }
    var serverError by remember { mutableStateOf<String?>(null) }
    if (confirmServer) AlertDialog(onDismissRequest = { confirmServer = false }, title = { Text("确认自定义 API 服务") },
        text = { Text("User ID 和 API Token 会发送给此 HTTPS 服务器。仅使用你控制或信任的服务；HTTPS 不代表服务可信。不跟随重定向，也不接受 HTTP 地址。") },
        confirmButton = { TextButton(onClick = { vm.updateSettings { it.copy(developerServerUrl = serverDraft.trim()) }; confirmServer = false }) { Text("确认使用") } },
        dismissButton = { TextButton(onClick = { confirmServer = false }) { Text("取消") } })

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
                onCheckedChange = { v -> vm.updateSettings { it.copy(connectHabitica = v) } },
            )
            if (s.connectHabitica) {
                OutlinedTextField(
                    value = uidDraft,
                    onValueChange = { v ->
                        uidDraft = v
                        uidError = if (isValidHabiticaUid(v)) null else "User ID 必须是完整 UUID，不能包含空白"
                    },
                    label = { Text("User ID") },
                    singleLine = true,
                    isError = uidError != null,
                    supportingText = { uidError?.let { Text(it) } },
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(onClick = {
                    if (!isValidHabiticaUid(uidDraft)) uidError = "User ID 必须是完整 UUID，不能包含空白；原账号未改变"
                    else {
                        vm.updateSettings { it.copy(uid = uidDraft) }
                        uidError = null
                    }
                }) { Text("应用 User ID") }
                OutlinedTextField(
                    value = s.apiToken,
                    onValueChange = { v -> vm.updateSettings { it.copy(apiToken = v) } },
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
                OutlinedTextField(serverDraft, onValueChange = { serverDraft = it; serverError = null },
                    label = { Text("自定义 HTTPS API 根地址（留空使用官方）") }, modifier = Modifier.fillMaxWidth(), singleLine = true,
                    supportingText = { Text("例如 https://your-server.example/api/v3/；凭据将发送给该服务") })
                TextButton(onClick = {
                    if (!HabiticaAPI.validServerUrl(serverDraft)) serverError = "仅支持不含账号、查询参数和片段的 HTTPS 地址"
                    else if (serverDraft.isBlank()) vm.updateSettings { it.copy(developerServerUrl = "") }
                    else confirmServer = true
                }) { Text("应用 API 地址") }
                serverError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Button(
                    onClick = { vm.refreshProfile(); vm.ensureDefaultHabits() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = isValidHabiticaUid(s.uid) && s.apiToken.isNotBlank(),
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
                onChange = { v -> vm.updateSettings { it.copy(pomoDurationMins = v) } },
            )
            StepperRow(
                label = "短休息",
                value = s.breakDuration,
                range = 1..60,
                suffix = "分钟",
                onChange = { v -> vm.updateSettings { it.copy(breakDuration = v) } },
            )
            StepperRow(
                label = "长休息",
                value = s.longBreakDuration,
                range = 1..120,
                suffix = "分钟",
                onChange = { v -> vm.updateSettings { it.copy(longBreakDuration = v) } },
            )
            StepperRow(
                label = "长休息间隔",
                value = s.pomoSetNum,
                range = 1..12,
                suffix = "个番茄",
                onChange = { v -> vm.updateSettings { it.copy(pomoSetNum = v) } },
            )
            StepperRow("休息延长", s.breakExtention, 0..30, "分钟") { v -> vm.updateSettings { it.copy(breakExtention = v) } }
            SwitchRow("延长结束后清空连击", s.resetPomoAfterBreak) { v -> vm.updateSettings { it.copy(resetPomoAfterBreak = v) } }
            HorizontalDivider()
            SwitchRow(
                label = "手动开始休息",
                checked = s.manualBreak,
                onCheckedChange = { v -> vm.updateSettings { it.copy(manualBreak = v) } },
            )
            Text(
                text = if (s.manualBreak) "番茄结束后等你点击才开始休息" else "番茄结束后自动进入休息",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        SettingsCard(title = "种植与时间块") { BlockSettings(vm, state) }

        SettingsCard(title = "Habitica 番茄打分") {
            SwitchRow("完成番茄时给习惯加分", s.pomoHabitPlus) { v -> vm.updateSettings { it.copy(pomoHabitPlus = v) } }
            SwitchRow("中途放弃时扣分", s.pomoHabitMinus) { v -> vm.updateSettings { it.copy(pomoHabitMinus = v) } }
            SwitchRow("休息延长超时扣分", s.breakExtentionFails) { v -> vm.updateSettings { it.copy(breakExtentionFails = v) } }
            SwitchRow("使用自定义番茄 Habit", s.customPomodoroTask) { v -> vm.updateSettings { it.copy(customPomodoroTask = v) } }
            if (s.customPomodoroTask) OutlinedTextField(value = s.pomodoroTaskId.orEmpty(), onValueChange = { v -> vm.updateSettings { it.copy(pomodoroTaskId = v.trim().ifBlank { null }) } },
                label = { Text("番茄 Habit 任务 ID") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            SwitchRow("完成一组时给习惯加分", s.pomoSetHabitPlus) { v -> vm.updateSettings { it.copy(pomoSetHabitPlus = v) } }
            SwitchRow("使用自定义 Combo Habit", s.customSetTask) { v -> vm.updateSettings { it.copy(customSetTask = v) } }
            if (s.customSetTask) OutlinedTextField(value = s.pomodoroSetTaskId.orEmpty(), onValueChange = { v -> vm.updateSettings { it.copy(pomodoroSetTaskId = v.trim().ifBlank { null }) } },
                label = { Text("一组 Habit 任务 ID") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            SwitchRow("块达标时奖励一次", s.blockRewardEnabled) { v -> vm.updateSettings { it.copy(blockRewardEnabled = v) } }
            Text("默认自动查找/创建 Pomodoro 与 Pomodoro Combo!；自定义模式使用填写的 Habit ID。块奖励为独立的一次额外加分。", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = vm::ensureDefaultHabits, enabled = !state.habiticaBusy) { Text("确认/初始化番茄习惯") }
            SwitchRow("短休息结束发 Habitica 私信", s.breakExtentionNotify) { v -> vm.updateSettings { it.copy(breakExtentionNotify = v) } }
            SwitchRow("长休息结束发 Habitica 私信", s.longBreakNotify) { v -> vm.updateSettings { it.copy(longBreakNotify = v) } }
        }

        // MARK: 提醒声音
        SettingsCard(title = "阶段提醒") {
            SoundSetting("番茄结束音", s.pomoEndSound, s.pomoEndSoundVolume, PomoAudio.soundOptions,
                { v -> vm.updateSettings { it.copy(pomoEndSound = v) } }, { v -> vm.updateSettings { it.copy(pomoEndSoundVolume = v) } }) { preview.effect(s.pomoEndSound, s.pomoEndSoundVolume, true) }
            SoundSetting("休息结束音", s.breakEndSound, s.breakEndSoundVolume, PomoAudio.soundOptions,
                { v -> vm.updateSettings { it.copy(breakEndSound = v) } }, { v -> vm.updateSettings { it.copy(breakEndSoundVolume = v) } }) { preview.effect(s.breakEndSound, s.breakEndSoundVolume, true) }
            SoundSetting("环境音", s.ambientSound, s.ambientSoundVolume, PomoAudio.ambientOptions,
                { v -> vm.updateSettings { it.copy(ambientSound = v) } }, { v -> vm.updateSettings { it.copy(ambientSoundVolume = v) } }) { preview.previewAmbient(s.ambientSound, s.ambientSoundVolume) }
            TextButton(onClick = { preview.stopAll(); vm.refreshRuntimeAudio() }) { Text("停止预听") }
            Text("预听最多 8 秒。环境音仅专注时循环，暂停/休息/放弃会停止。系统通知是否显示受通知权限和渠道设置控制。", style = MaterialTheme.typography.bodySmall)
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
                text = "Android 不访问 iCloud Drive。Habits/Dailies 从 Habitica 读取并打分；本机创建的 Task 可同步为 todo。" +
                    "Mac/iPhone 已上传且带专用日期/分类备注的 Top3 todo 会保守合并；普通 todo 不导入。本机未上传修改保留。设置、番茄/块/植物历史不跨端同步。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // MARK: 关于
        SettingsCard(title = "关于") {
            Text("Habitica Pomodoro for Android · v1.2.2", style = MaterialTheme.typography.bodyMedium)
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

@Composable
private fun SoundSetting(label: String, value: String, volume: Double, options: List<String>, onChoice: (String) -> Unit, onVolume: (Double) -> Unit, preview: () -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, Modifier.weight(1f))
            androidx.compose.foundation.layout.Box {
                TextButton(onClick = { expanded = true }) { Text(if (value in options) value else "None") }
                DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
                    options.forEach { option -> DropdownMenuItem(text = { Text(option) }, onClick = { onChoice(option); expanded = false }) }
                }
            }
            TextButton(onClick = preview, enabled = value in options && value != "None") { Text("预听") }
        }
        Text("音量 ${(volume * 100).toInt()}%", style = MaterialTheme.typography.labelSmall)
        Slider(volume.toFloat(), onValueChange = { onVolume(it.toDouble()) })
    }
}

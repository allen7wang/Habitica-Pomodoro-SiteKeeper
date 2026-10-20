package com.habitica.pomodoro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.habitica.pomodoro.data.BlockTimeRange
import com.habitica.pomodoro.data.calendarDayKey
import com.habitica.pomodoro.engine.PomodoroViewModel

@Composable
fun BlockGarden(vm: PomodoroViewModel, state: PomodoroViewModel.UiState) {
    val settings = state.settings
    val key = calendarDayKey()
    val today = state.dailyBlocks[key]
    val plants = state.plants[key]
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text("时间块 · 种植", style = MaterialTheme.typography.titleSmall)
        repeat(settings.blockCount) { index ->
            val done = today?.blockProgress?.getOrNull(index) ?: 0
            val attempts = plants?.attempts?.getOrNull(index).orEmpty()
            val aligned = List((done - attempts.count { it == "shrub" }).coerceAtLeast(0)) { "shrub" } + attempts
            val visible = aligned.takeLast(settings.blockPomoCount)
            val range = settings.blockTimeRanges.getOrNull(index)
            val goal = settings.blockGoals.getOrNull(index).orEmpty()
            Column(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("B${index + 1}", style = MaterialTheme.typography.labelMedium)
                    Text(range?.displayString ?: "—", style = MaterialTheme.typography.labelSmall)
                    if (goal.isNotBlank()) Text(goal, maxLines = 1, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall)
                    else Spacer(Modifier.weight(1f))
                    Text("$done/${settings.blockPomoCount}", style = MaterialTheme.typography.labelSmall)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    repeat(settings.blockPomoCount) { i ->
                        Text(when (visible.getOrNull(i)) { "shrub" -> "🌿"; "wilted" -> "🥀"; else -> "○" }, style = MaterialTheme.typography.labelSmall)
                    }
                    Text(" │ ", style = MaterialTheme.typography.labelSmall)
                    val trees = plants?.trees?.getOrNull(index) ?: 0
                    Text(if (trees > 0) "🌳${if (trees > 1) "×$trees" else ""}" else "○", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        Text("🌿 完成 · 🥀 放弃 · 🌳 一组连击；仅本机保存", style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
fun BlockSettings(vm: PomodoroViewModel, state: PomodoroViewModel.UiState) {
    val s = state.settings
    Text("时间块 (1–24 块)", style = MaterialTheme.typography.titleSmall)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("启用时间块", modifier = Modifier.weight(1f))
        Switch(s.enableBlockMode, onCheckedChange = { vm.updateSettings { value -> value.copy(enableBlockMode = it) } })
    }
    if (!s.enableBlockMode) return
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("块数量 ${s.blockCount}", modifier = Modifier.weight(1f))
        TextButton(onClick = { vm.updateSettings { it.copy(blockCount = (it.blockCount - 1).coerceAtLeast(1)) } }, enabled = s.blockCount > 1) { Text("−") }
        TextButton(onClick = { vm.updateSettings { it.copy(blockCount = (it.blockCount + 1).coerceAtMost(24)) } }, enabled = s.blockCount < 24) { Text("+") }
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("每块番茄 ${s.blockPomoCount}", modifier = Modifier.weight(1f))
        TextButton(onClick = { vm.updateSettings { it.copy(blockPomoCount = (it.blockPomoCount - 1).coerceAtLeast(1)) } }, enabled = s.blockPomoCount > 1) { Text("−") }
        TextButton(onClick = { vm.updateSettings { it.copy(blockPomoCount = (it.blockPomoCount + 1).coerceAtMost(12)) } }, enabled = s.blockPomoCount < 12) { Text("+") }
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("块前系统提醒", Modifier.weight(1f)); Switch(s.blockStartReminder, onCheckedChange = { v -> vm.updateSettings { it.copy(blockStartReminder = v) } })
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("4/6 冲刺提醒", Modifier.weight(1f)); Switch(s.blockSprintReminder, onCheckedChange = { v -> vm.updateSettings { it.copy(blockSprintReminder = v) } })
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("提前 ${s.blockReminderMinutes} 分钟", Modifier.weight(1f))
        TextButton(onClick = { vm.updateSettings { it.copy(blockReminderMinutes = (it.blockReminderMinutes - 1).coerceAtLeast(1)) } }) { Text("−") }
        TextButton(onClick = { vm.updateSettings { it.copy(blockReminderMinutes = (it.blockReminderMinutes + 1).coerceAtMost(60)) } }) { Text("+") }
    }
    Text("采用无需特殊权限的系统非精确提醒；省电/待机可能延迟。通知需系统授权。", style = MaterialTheme.typography.bodySmall)
    var reset by remember { mutableStateOf(false) }
    TextButton(onClick = { reset = true }) { Text("重置当前块计数") }
    if (reset) AlertDialog(onDismissRequest = { reset = false }, title = { Text("重置当前块？") },
        text = { Text("同时重置当前与今日该块计数；保留植物和达标奖励记录，避免重复奖励。不删除其他块或 Task。") },
        confirmButton = { TextButton(onClick = { vm.resetCurrentBlock(); reset = false }) { Text("确认重置") } },
        dismissButton = { TextButton(onClick = { reset = false }) { Text("取消") } })
    repeat(s.blockCount) { index ->
        val range = s.blockTimeRanges.getOrNull(index) ?: BlockTimeRange(4, 0, 5, 0)
        val tasks = s.blockTasks.getOrNull(index).orEmpty()
        var editing by remember { mutableStateOf(false) }
        TextButton(onClick = { editing = true }) { Text("B${index + 1}  ${range.displayString}  ${s.blockGoals.getOrNull(index).orEmpty().ifBlank { "设置目标/任务" }}  (${tasks.size})") }
        if (editing) {
            var goal by remember(index) { mutableStateOf(s.blockGoals.getOrNull(index).orEmpty()) }
            var start by remember(index) { mutableStateOf("%02d:%02d".format(range.startHour, range.startMinute)) }
            var end by remember(index) { mutableStateOf("%02d:%02d".format(range.endHour, range.endMinute)) }
            var newTask by remember(index) { mutableStateOf("") }
            var invalid by remember { mutableStateOf(false) }
            var taskToDelete by remember(index) { mutableStateOf<String?>(null) }
            if (taskToDelete != null) AlertDialog(
                onDismissRequest = { taskToDelete = null }, title = { Text("删除这条块任务？") },
                confirmButton = { TextButton(onClick = {
                    taskToDelete?.let { vm.deleteBlockTask(index, it) }; taskToDelete = null
                }) { Text("删除") } },
                dismissButton = { TextButton(onClick = { taskToDelete = null }) { Text("取消") } })
            AlertDialog(onDismissRequest = { editing = false }, title = { Text("B${index + 1} 设置") },
                text = {
                    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedTextField(goal, onValueChange = { goal = it }, label = { Text("目标") }, singleLine = true)
                        OutlinedTextField(start, onValueChange = { start = it }, label = { Text("开始 HH:mm") }, singleLine = true)
                        OutlinedTextField(end, onValueChange = { end = it }, label = { Text("结束 HH:mm") }, singleLine = true)
                        tasks.forEach { task ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Checkbox(task.isCompleted, onCheckedChange = { vm.toggleBlockTask(index, task.id) })
                                var title by remember(task.id, task.title) { mutableStateOf(task.title) }
                                var estimate by remember(task.id, task.estimatedPomo) { mutableStateOf(task.estimatedPomo) }
                                Column(Modifier.weight(1f)) {
                                    OutlinedTextField(title, onValueChange = { title = it }, singleLine = true, label = { Text("任务标题") })
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        TextButton(onClick = { estimate = (estimate - 1).coerceAtLeast(1) }) { Text("−") }
                                        Text("预计 $estimate 🍅")
                                        TextButton(onClick = { estimate = (estimate + 1).coerceAtMost(12) }) { Text("+") }
                                    }
                                    TextButton(onClick = { vm.editBlockTask(index, task.id, title, estimate) }, enabled = title.isNotBlank()) { Text("保存任务") }
                                }
                                TextButton(onClick = { taskToDelete = task.id }) { Text("删除") }
                            }
                        }
                        if (invalid) Text("请输入有效的 HH:mm（00:00–23:59）", color = MaterialTheme.colorScheme.error)
                        OutlinedTextField(newTask, onValueChange = { newTask = it }, label = { Text("块任务") }, singleLine = true)
                        TextButton(onClick = { vm.addBlockTask(index, newTask); newTask = "" }, enabled = newTask.isNotBlank()) { Text("添加任务") }
                    }
                }, confirmButton = {
                    TextButton(onClick = {
                        fun parse(value: String): Pair<Int, Int>? {
                            val match = Regex("^(\\d{1,2}):(\\d{2})$").matchEntire(value.trim()) ?: return null
                            val h = match.groupValues[1].toInt(); val m = match.groupValues[2].toInt()
                            return if (h in 0..23 && m in 0..59) h to m else null
                        }
                        val a = parse(start); val b = parse(end)
                        if (a != null && b != null) {
                            vm.updateBlockRange(index, BlockTimeRange(a.first, a.second, b.first, b.second))
                            vm.updateBlockGoal(index, goal)
                            editing = false
                        } else invalid = true
                    }) { Text("保存时间与目标") }
                }, dismissButton = { TextButton(onClick = { editing = false }) { Text("关闭") } })
        }
    }
    Text("时段允许跨午夜；相同起止表示全天，与 Mac/iOS 一致。块任务仅本机保存。", style = MaterialTheme.typography.bodySmall)
}

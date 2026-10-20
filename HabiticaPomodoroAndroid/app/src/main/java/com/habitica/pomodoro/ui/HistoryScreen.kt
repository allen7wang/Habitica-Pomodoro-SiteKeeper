package com.habitica.pomodoro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.Alignment
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.habitica.pomodoro.engine.PomodoroViewModel

@Composable
fun HistoryScreen(vm: PomodoroViewModel, state: PomodoroViewModel.UiState, modifier: Modifier = Modifier) {
    var confirmClear by remember { mutableStateOf(false) }
    var confirmHistogram by remember { mutableStateOf(false) }
    var chartDays by remember { mutableStateOf(7) }
    val counts = state.histogram.toSortedMap(reverseOrder())
    val total = counts.values.sumOf { it.pomodoros }; val minutes = counts.values.sumOf { it.minutes }
    val blockDays = (state.plants.mapValues { (date, plant) -> com.habitica.pomodoro.data.DailyBlockProgress(date, List(plant.attempts.size) { 0 }, emptyList()) } + state.dailyBlocks).toSortedMap(reverseOrder())
    LazyColumn(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("番茄历史", style = MaterialTheme.typography.headlineSmall)
            Text("今日 ${state.todayPomodoros} 个 · 累计 $total 个 · ${counts.size} 天",
                style = MaterialTheme.typography.titleSmall)
            Text("总专注 ${"%.2f".format(java.util.Locale.US, minutes / 60.0)} 小时 · 日均 ${"%.1f".format(java.util.Locale.US, if (counts.isEmpty()) 0.0 else total.toDouble() / counts.size)} 个 / ${"%.2f".format(java.util.Locale.US, if (counts.isEmpty()) 0.0 else minutes / 60.0 / counts.size)} 小时")
            Row { listOf(7, 30).forEach { n -> TextButton(onClick = { chartDays = n }) { Text("近 $n 条记录") } }
                TextButton(onClick = { confirmHistogram = true }, enabled = counts.isNotEmpty()) { Text("清空番茄统计") } }
            if (counts.isNotEmpty()) {
                val recent = state.histogram.toSortedMap().entries.toList().takeLast(chartDays)
                val max = state.histogram.values.maxOf { it.pomodoros }.coerceAtLeast(1)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Bottom) {
                    recent.forEach { (date, hist) ->
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("${hist.pomodoros}", style = MaterialTheme.typography.labelSmall)
                            Box(Modifier.width(26.dp).height((hist.pomodoros.toFloat() / max * 130).coerceAtLeast(2f).dp).background(MaterialTheme.colorScheme.primary))
                            Text(date.takeLast(5), style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
            if (counts.values.any { it.weekday.isBlank() && it.pomodoros > 0 }) Text("旧版只有计数的记录保留原日期；历史分钟未知，不按当前设置补造。", style = MaterialTheme.typography.bodySmall)
        }
        if (counts.isEmpty()) item { Text("暂无已完成番茄。完成计时后会记录在这里。") }
        items(counts.entries.toList()) { (day, value) ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("$day ${value.weekday}"); Text("${value.pomodoros} 🍅 · ${if (value.weekday.isBlank() && value.pomodoros > 0) "分钟未知" else "${value.minutes} 分钟"}")
            }
        }
        item {
            HorizontalDivider()
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("时间块历史", style = MaterialTheme.typography.titleMedium)
                TextButton(onClick = { confirmClear = true }, enabled = blockDays.isNotEmpty() || state.plants.isNotEmpty()) { Text("清空块记录") }
            }
            if (blockDays.isEmpty()) Text("暂无块进度。开启时间块并完成番茄后生成。")
        }
        items(blockDays.entries.toList()) { (day, progress) ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp)) {
                    Text(day, style = MaterialTheme.typography.titleSmall)
                    progress.blockProgress.forEachIndexed { i, n ->
                        if (n > 0 || !state.plants[day]?.attempts?.getOrNull(i).isNullOrEmpty()) {
                            val attempts = state.plants[day]?.attempts?.getOrNull(i).orEmpty()
                            val trees = state.plants[day]?.trees?.getOrNull(i) ?: 0
                            Text("B${i + 1}: $n 番茄 · 🌿${attempts.count { it == "shrub" }} · 🥀${attempts.count { it == "wilted" }} · 🌳$trees")
                        }
                    }
                }
            }
        }
        item {
            HorizontalDivider()
            Text("每日任务历史", style = MaterialTheme.typography.titleMedium)
            if (state.store.history.isEmpty()) Text("暂无本机每日任务。")
        }
        items(state.store.history.toSortedMap(reverseOrder()).entries.toList()) { (day, tasks) ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(day, style = MaterialTheme.typography.titleSmall)
                    tasks.taskGroups.forEachIndexed { index, group ->
                        if (group.isNotEmpty()) {
                            Text("${state.store.categoryNames.getOrElse(index) { "分类 ${index + 1}" }} · ${group.count { it.isCompleted }}/${group.size}",
                                style = MaterialTheme.typography.labelMedium)
                            group.forEach { task -> Text("${if (task.isCompleted) "✓" else "○"} ${task.title}", style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
            }
        }
    }
    if (confirmHistogram) AlertDialog(onDismissRequest = { confirmHistogram = false }, title = { Text("清空番茄统计？") },
        text = { Text("只清番茄数与专注分钟，不删除 Task、块进度或植物。不可撤销。") },
        confirmButton = { TextButton(onClick = { vm.clearHistogram(); confirmHistogram = false }) { Text("确认清空") } },
        dismissButton = { TextButton(onClick = { confirmHistogram = false }) { Text("取消") } })
    // Local Task records are historical snapshots, not fabricated Habitica todos.
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("清空块历史与植物？") },
        text = { Text("不会删除番茄计数和每日任务；此操作不可撤销。") },
        confirmButton = { TextButton(onClick = { vm.clearBlockHistory(); confirmClear = false }) { Text("确认清空") } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("取消") } })
}

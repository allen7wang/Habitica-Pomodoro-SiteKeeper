package com.habitica.pomodoro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.habitica.pomodoro.engine.PomodoroViewModel

/** Reads actual Habitica tasks; never substitutes sample records for an unconfigured account. */
@Composable
fun HabiticaListsScreen(vm: PomodoroViewModel, state: PomodoroViewModel.UiState, modifier: Modifier = Modifier) {
    var type by remember { mutableStateOf("habits") }
    val configured = state.settings.connectHabitica && state.settings.uid.isNotBlank() && state.settings.apiToken.isNotBlank()
    LaunchedEffect(type, state.settings.uid, state.settings.apiToken, state.settings.connectHabitica) {
        if (configured) vm.refreshHabiticaTasks(type)
    }
    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = type == "habits", onClick = { type = "habits" }, label = { Text("Habits") })
            FilterChip(selected = type == "dailys", onClick = { type = "dailys" }, label = { Text("Dailies") })
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { vm.refreshHabiticaTasks(type) }, enabled = configured && !state.tasksLoading) { Text("刷新") }
        }
        if (!configured) {
            Text("未配置 Habitica。请在设置中填写 User ID 与 API Token。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@Column
        }
        state.tasksError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (state.tasksLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        val items = if (type == "habits") state.habits else state.dailies
        if (items.isEmpty() && !state.tasksLoading && state.tasksError == null) Text("暂无${if (type == "habits") "习惯" else "每日任务"}")
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(items, key = { it.id }) { item ->
                val busy = item.id in state.scoringIds
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (type == "dailys") {
                            Checkbox(checked = item.completed, enabled = !busy,
                                onCheckedChange = { vm.scoreHabiticaTask(type, item, if (item.completed) "down" else "up") })
                        } else {
                            OutlinedButton(onClick = { vm.scoreHabiticaTask(type, item, "down") }, enabled = item.canDown && !busy,
                                contentPadding = PaddingValues(horizontal = 12.dp)) { Text("−") }
                        }
                        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                            Text(item.text, style = MaterialTheme.typography.bodyMedium)
                            if (item.notes.isNotBlank()) Text(item.notes, maxLines = 2, style = MaterialTheme.typography.bodySmall)
                            Text(if (type == "habits") "value %.1f".format(java.util.Locale.US, item.value) else if (!item.isDue) "今天未到期" else "今天到期",
                                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (type == "habits") OutlinedButton(onClick = { vm.scoreHabiticaTask(type, item, "up") }, enabled = item.canUp && !busy,
                            contentPadding = PaddingValues(horizontal = 12.dp)) { Text("+") }
                    }
                }
            }
        }
    }
}

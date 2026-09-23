package com.habitica.pomodoro.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.habitica.pomodoro.engine.PomodoroViewModel
import com.habitica.pomodoro.engine.PomodoroViewModel.UiState

/** 前 2 个分类（Work/MyOwn）上限 3 条，其余（Chores）为自由列表 */
private const val FIXED_SLOT_CATEGORIES = 2
private const val MAX_FIXED_TASKS = 3

/**
 * Task 页：每日三件事 + 琐事。
 * 今天（逻辑日）可增删改与勾选；昨天只读，未完成的可用 ➡️ 移动到今天。
 */
@Composable
fun TaskScreen(
    vm: PomodoroViewModel,
    state: UiState,
    modifier: Modifier = Modifier,
) {
    val store = state.store
    val todayKey = vm.todayKey()
    val yesterdayKey = vm.yesterdayKey()
    var renamingIndex by remember { mutableStateOf<Int?>(null) }
    var renameText by remember { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Task", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Text(
            text = "今天可编辑 · 昨天只读（未完成的可以移动到今天）",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(12.dp))

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
        ) {
            store.categoryNames.forEachIndexed { index, categoryName ->
                item(key = "header-$index-$categoryName") {
                    CategoryHeader(
                        name = categoryName,
                        index = index,
                        isRenaming = renamingIndex == index,
                        renameText = renameText,
                        todayCount = dayGroupSize(store, todayKey, index),
                        onStartRename = {
                            renamingIndex = index
                            renameText = categoryName
                        },
                        onRenameTextChanged = { renameText = it },
                        onCommitRename = {
                            vm.renameCategory(index, renameText)
                            renamingIndex = null
                        },
                        onCancelRename = { renamingIndex = null },
                    )
                }

                item(key = "today-$index") {
                    SectionLabel(text = "今天 · ${todayKey}")
                }

                val todayDay = store.history[todayKey]
                val todayTasks = todayDay?.taskGroups?.getOrNull(index).orEmpty()
                itemsIndexed(
                    items = todayTasks,
                    key = { _, task -> "today-$index-${task.id}" },
                ) { taskIndex, task ->
                    TaskRow(
                        title = task.title,
                        completed = task.isCompleted,
                        editable = true,
                        showMoveButton = false,
                        onToggle = { vm.toggleTask(index, taskIndex) },
                        onDelete = { vm.deleteTask(index, taskIndex) },
                        onMove = { },
                    )
                }

                item(key = "add-$index") {
                    AddTaskRow(
                        enabled = true,
                        hint = if (index < FIXED_SLOT_CATEGORIES) {
                            val used = todayTasks.size
                            if (used >= MAX_FIXED_TASKS) "已达上限 $MAX_FIXED_TASKS 条" else "添加任务…"
                        } else {
                            "添加琐事…"
                        },
                        atLimit = index < FIXED_SLOT_CATEGORIES && todayTasks.size >= MAX_FIXED_TASKS,
                        onAdd = { title -> vm.addTask(index, title) },
                    )
                }

                // 昨天（只读 + 未完成的可以移动到今天）
                val yesterdayDay = store.history[yesterdayKey]
                val yesterdayTasks = yesterdayDay?.taskGroups?.getOrNull(index).orEmpty()
                if (yesterdayTasks.isNotEmpty()) {
                    item(key = "yesterday-label-$index") {
                        SectionLabel(text = "昨天 · ${yesterdayDay?.date ?: yesterdayKey}", muted = true)
                    }
                    itemsIndexed(
                        items = yesterdayTasks,
                        key = { _, task -> "yst-$index-${task.id}" },
                    ) { taskIndex, task ->
                        TaskRow(
                            title = task.title,
                            completed = task.isCompleted,
                            editable = false,
                            showMoveButton = !task.isCompleted && !task.movedToToday,
                            onToggle = { },
                            onDelete = { },
                            onMove = { vm.moveTaskToToday(index, taskIndex) },
                        )
                    }
                }

                item(key = "divider-$index") {
                    HorizontalDivider(modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}

private fun dayGroupSize(store: com.habitica.pomodoro.data.TopThreeStore, key: String, index: Int): Int =
    store.history[key]?.taskGroups?.getOrNull(index)?.size ?: 0

@Composable
private fun CategoryHeader(
    name: String,
    index: Int,
    isRenaming: Boolean,
    renameText: String,
    todayCount: Int,
    onStartRename: () -> Unit,
    onRenameTextChanged: (String) -> Unit,
    onCommitRename: () -> Unit,
    onCancelRename: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isRenaming) {
            OutlinedTextField(
                value = renameText,
                onValueChange = onRenameTextChanged,
                modifier = Modifier.weight(1f),
                singleLine = true,
                label = { Text("分类名称") },
            )
            TextButton(onClick = onCommitRename) { Text("保存") }
            TextButton(onClick = onCancelRename) { Text("取消") }
        } else {
            Text(
                text = name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = if (index < FIXED_SLOT_CATEGORIES) "今天 $todayCount/$MAX_FIXED_TASKS" else "今天 $todayCount",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            IconButton(onClick = onStartRename) {
                Icon(Icons.Filled.Edit, contentDescription = "重命名分类", modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String, muted: Boolean = false) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        fontSize = 12.sp,
        color = if (muted) MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
        else MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 4.dp, bottom = 2.dp),
    )
}

@Composable
private fun TaskRow(
    title: String,
    completed: Boolean,
    editable: Boolean,
    showMoveButton: Boolean,
    onToggle: () -> Unit,
    onDelete: () -> Unit,
    onMove: () -> Unit,
) {
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (completed) {
                MaterialTheme.colorScheme.tertiary.copy(alpha = 0.10f)
            } else {
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
            },
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(
                checked = completed,
                onCheckedChange = { if (editable) onToggle() },
                enabled = editable,
            )
            Text(
                text = title,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyLarge,
                textDecoration = if (completed) TextDecoration.LineThrough else null,
                color = if (completed) {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
            )
            if (showMoveButton) {
                TextButton(onClick = onMove) { Text("➡️ 今天") }
            }
            if (editable) {
                IconButton(onClick = { showDeleteConfirm = true }) {
                    Icon(
                        Icons.Filled.Delete,
                        contentDescription = "删除",
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            } else {
                Spacer(Modifier.width(12.dp))
            }
        }
    }

    if (showDeleteConfirm) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("删除任务") },
            text = { Text("「$title」将被删除，同时从 Habitica 移除对应的 todo。") },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    onDelete()
                }) { Text("删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("取消") }
            },
        )
    }
}

/** 统一的添加输入行：输入后点添加（回车由单行 TextField 的 keyboard action 处理） */
@Composable
private fun AddTaskRow(
    enabled: Boolean,
    hint: String,
    atLimit: Boolean,
    onAdd: (String) -> Unit,
) {
    var text by remember { mutableStateOf("") }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.weight(1f),
            enabled = enabled && !atLimit,
            placeholder = { Text(hint) },
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                imeAction = androidx.compose.ui.text.input.ImeAction.Done,
            ),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                onDone = {
                    if (text.isNotBlank()) {
                        onAdd(text)
                        text = ""
                    }
                },
            ),
        )
        Spacer(Modifier.width(8.dp))
        TextButton(
            onClick = {
                onAdd(text)
                text = ""
            },
            enabled = enabled && !atLimit && text.isNotBlank(),
        ) { Text("添加") }
    }
}

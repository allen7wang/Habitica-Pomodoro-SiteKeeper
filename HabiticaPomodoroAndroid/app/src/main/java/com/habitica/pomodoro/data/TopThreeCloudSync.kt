package com.habitica.pomodoro.data

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle

/** Only the dated notes written by Mac/iOS (and current Android) identify an app-owned todo. */
data class CloudTodo(val id: String, val title: String, val notes: String, val completed: Boolean, val tags: List<String>)
data class TopThreeNotes(val category: String, val date: String)

private const val NOTES_PREFIX = "From HabiticaPomodoro Top3 · "
private val dateFormatter = DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)

fun topThreeNotes(category: String, date: String): String = "$NOTES_PREFIX$category · $date"

fun parseTopThreeNotes(notes: String): TopThreeNotes? {
    if (!notes.startsWith(NOTES_PREFIX)) return null
    val parts = notes.removePrefix(NOTES_PREFIX).split(" · ")
    if (parts.size != 2 || parts[0].isBlank() || parts[0] != parts[0].trim() ||
        !Regex("\\d{4}-\\d{2}-\\d{2}").matches(parts[1])) return null
    if (runCatching { LocalDate.parse(parts[1], dateFormatter) }.isFailure) return null
    return TopThreeNotes(parts[0], parts[1])
}

/** An attempt belongs to one UUID even when its moved/archive copies retain the same marker. */
fun TopThreeStore.pendingCreateCandidates(title: String, notes: String): List<TopThreeTask> =
    history.values.flatMap { it.taskGroups.flatten() }.filter {
        it.cloudAccount == cloudAccount && it.habiticaTaskId == null &&
            it.pendingCreateTitle == title && it.pendingCreateNotes == notes
    }.distinctBy { it.id }

fun TopThreeStore.remoteIdOccupied(remoteId: String, localId: String): Boolean =
    history.values.any { day -> day.taskGroups.flatten().any {
        it.cloudAccount == cloudAccount && it.habiticaTaskId == remoteId && it.id != localId
    } }

/** Merge onto the latest owner partition. Ambiguous POSTs bind the original UUID before imports. */
fun TopThreeStore.quarantinesDeletedCreation(todo: CloudTodo): Boolean {
    if (parseTopThreeNotes(todo.notes) == null) return false
    // A known ID is not evidence that an unresolved creation belongs to this deletion.
    if (history.values.any { day -> day.taskGroups.flatten().any {
        it.cloudAccount == cloudAccount && it.habiticaTaskId == todo.id
    } }) return false
    // Legacy markers have no tags. Use the full strict notes + separator, never split on newlines.
    return deletedCreateMarkers.any { it.startsWith("${todo.notes}\n") }
}

fun mergeTopThreeTodos(local: TopThreeStore, remote: List<CloudTodo>): TopThreeStore {
    var history = local.history
    val cloud = remote.distinctBy { it.id }
    fun changeTask(id: String, transform: (TopThreeTask) -> TopThreeTask) {
        history = history.mapValues { (_, day) -> day.copy(taskGroups = day.taskGroups.map { group ->
            group.map { if (it.id == id && it.cloudAccount == local.cloudAccount) transform(it) else it }
        }) }
    }
    for (todo in cloud) {
        if (todo.id.isBlank() || todo.title.isBlank() || todo.id in local.deletedCloudIds) continue
        val marker = parseTopThreeNotes(todo.notes) ?: continue
        val current = local.copy(history = history)
        if (current.quarantinesDeletedCreation(todo)) continue
        val pending = current.pendingCreateCandidates(todo.title, todo.notes)
        if (pending.isNotEmpty()) {
            val matches = cloud.filter { it.title == todo.title && it.notes == todo.notes }
            val occupied = current.remoteIdOccupied(todo.id, pending.singleOrNull()?.id.orEmpty())
            if (pending.size != 1 || matches.size != 1 || occupied) {
                pending.forEach { p -> changeTask(p.id) { it.copy(syncError = "创建匹配不唯一或远端 ID 已绑定其他本地任务；请人工核对，未重复创建") } }
                continue
            }
            changeTask(pending.single().id) { it.copy(habiticaTaskId = todo.id, syncPending = true,
                pendingCreateTitle = null, pendingCreateNotes = null, syncError = null, syncVersion = it.syncVersion + 1) }
            continue // Preserve local edits and every moved/archive copy of the original UUID.
        }
        val category = local.categoryNames.indices.filter { local.categoryNames[it] == marker.category }.singleOrNull()
            ?: local.categoryNames.indices.filter { i -> local.categoryTagIds[local.categoryNames[i]]?.let { it in todo.tags } == true }.singleOrNull()
            ?: continue
        val locations = history.flatMap { (date, day) -> day.taskGroups.flatMapIndexed { index, group ->
            group.filter { it.cloudAccount == local.cloudAccount && it.habiticaTaskId == todo.id }.map { Triple(date, index, it) }
        } }
        val active = locations.filter { !it.third.movedToToday }
        if (active.any { it.third.syncPending }) continue // Local rename/move/completion wins until confirmed.
        if (active.size > 1) continue // Do not guess which local UUID owns a conflicting ID.
        val source = active.singleOrNull() ?: locations.maxByOrNull { it.first }
        val task = source?.third?.copy(title = todo.title, isCompleted = todo.completed, movedToToday = false)
            ?: TopThreeTask(title = todo.title, isCompleted = todo.completed, habiticaTaskId = todo.id, cloudAccount = local.cloudAccount)
        if (source != null && source.first == marker.date && source.second == category && !source.third.movedToToday) {
            history = history + (source.first to history.getValue(source.first).let { day -> day.copy(taskGroups = day.taskGroups.mapIndexed { i, group ->
                if (i == category) group.map { if (it.id == task.id && !it.movedToToday) task else it } else group
            }) })
            continue
        }
        if (source != null && !source.third.movedToToday) {
            // Keep the original day's archive, but move the single active copy by the strict dated marker.
            val day = history.getValue(source.first)
            history = history + (source.first to day.copy(taskGroups = day.taskGroups.mapIndexed { i, group ->
                if (i == source.second) group.map { if (it.id == task.id) it.copy(movedToToday = true) else it } else group
            }))
        }
        val day = history[marker.date] ?: TopThreeDay(marker.date)
        val groups = List(maxOf(local.categoryNames.size, day.taskGroups.size)) { i ->
            val group = day.taskGroups.getOrElse(i) { emptyList() }
            if (i == category) group.filterNot { it.id == task.id } + task else group
        }
        history = history + (marker.date to day.copy(taskGroups = groups))
    }
    return if (history == local.history) local else local.copy(history = history)
}

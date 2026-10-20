// Harness stub: com.habitica.pomodoro.data.HabiticaAPI — an in-memory SUBSTITUTE
// for the real OkHttp client. HTTP 0 by construction: there is no networking
// code in this file at all. Every call is recorded in `calls` and answered from
// scriptable state, so cases control the cloud world deterministically.
//
// The public surface mirrors the production object exactly (same method names,
// parameter shapes and Result types) so the production ViewModel/Models compile
// against it unmodified. apiRoot/validServerUrl mirror production semantics
// (canonical HTTPS root, no user-info/query/fragment) with java.net.URI instead
// of okhttp; the default official root is byte-identical.
package com.habitica.pomodoro.data

import org.json.JSONObject
import java.util.UUID

object HabiticaAPI {

    sealed class Result<out T> {
        data class Success<T>(val value: T) : Result<T>()
        data class Error(val message: String, val statusCode: Int? = null) : Result<Nothing>()
    }

    private const val SERVER_URL = "https://habitica.com/api/v3/"

    // ---- scriptable cloud world ----
    /** Todos currently visible in the cloud (fetchTopThreeTodos answers from here). */
    val cloud = mutableListOf<CloudTodo>()
    /** Tag name -> id. */
    val tags = linkedMapOf<String, String>()
    /** Recorded call log, e.g. "deleteTodo:RID-1". */
    val calls = mutableListOf<String>()
    /** When non-null, every fetch* answers with Error(message, fetchStatus). */
    var fetchFailure: String? = null
    var fetchStatus: Int? = null
    /** Ids whose read-back (fetchTodo) must 404 even if still present in `cloud`. */
    val fetchTodoMissing = mutableSetOf<String>()
    /** Scripted delete behaviour. Default: succeed and remove from `cloud`. */
    var deleteOutcome: (String) -> Result<Boolean> = { Result.Success(true) }
    /** When true, a successful delete also removes the todo from `cloud`. */
    var deleteRemovesFromCloud = true
    /** Scripted create behaviour: (title, notes) -> Result<remoteId?>. */
    var createOutcome: (String, String) -> Result<String?> = { _, _ -> Result.Success("RID-" + UUID.randomUUID().toString().take(8)) }
    /** When true, a successful create makes the todo visible in `cloud`. */
    var createAddsToCloud = true
    var nextTagId = 0

    fun reset() {
        cloud.clear(); tags.clear(); calls.clear(); fetchTodoMissing.clear()
        fetchFailure = null; fetchStatus = null
        deleteOutcome = { Result.Success(true) }; deleteRemovesFromCloud = true
        createOutcome = { _, _ -> Result.Success("RID-" + UUID.randomUUID().toString().take(8)) }
        createAddsToCloud = true
        nextTagId = 0
    }

    private fun <T> failOr(value: () -> T): Result<T> {
        val failure = fetchFailure
        return if (failure != null) Result.Error(failure, fetchStatus) else Result.Success(value())
    }

    // ---- surface used by production code ----

    suspend fun fetchProfile(settings: UserSettings): Result<HabiticaProfile> {
        calls += "fetchProfile"
        return failOr { HabiticaProfile(username = "stub-user", level = 1) }
    }

    suspend fun fetchTaskItems(settings: UserSettings, type: String): Result<List<HabiticaTaskItem>> {
        calls += "fetchTaskItems:$type"
        return failOr { emptyList() }
    }

    suspend fun scoreTask(settings: UserSettings, taskId: String, direction: String): Result<JSONObject?> {
        calls += "scoreTask:$taskId:$direction"
        return failOr { JSONObject() }
    }

    suspend fun fetchTopThreeTodos(settings: UserSettings): Result<List<CloudTodo>> {
        calls += "fetchTopThreeTodos"
        return failOr { cloud.toList() }
    }

    suspend fun fetchTodo(settings: UserSettings, id: String): Result<CloudTodo> {
        calls += "fetchTodo:$id"
        fetchFailure?.let { return Result.Error(it, fetchStatus) }
        if (id in fetchTodoMissing) return Result.Error("Habitica 请求失败 (HTTP 404)", 404)
        return cloud.firstOrNull { it.id == id }?.let { Result.Success(it) }
            ?: Result.Error("Habitica 请求失败 (HTTP 404)", 404)
    }

    suspend fun createTodo(settings: UserSettings, text: String, notes: String, tagIds: List<String>): Result<String?> {
        calls += "createTodo:$text"
        val outcome = createOutcome(text, notes)
        if (outcome is Result.Success && createAddsToCloud) {
            outcome.value?.takeIf { it.isNotBlank() }?.let { id ->
                if (cloud.none { it.id == id }) cloud += CloudTodo(id, text, notes, false, tagIds)
            }
        }
        return outcome
    }

    suspend fun updateTodo(settings: UserSettings, taskId: String, text: String, notes: String = "", tagIds: List<String>? = null): Result<Boolean> {
        calls += "updateTodo:$taskId"
        fetchFailure?.let { return Result.Error(it, fetchStatus) }
        val index = cloud.indexOfFirst { it.id == taskId }
        if (index >= 0) {
            val old = cloud[index]
            cloud[index] = old.copy(title = text, notes = if (notes.isNotEmpty()) notes else old.notes,
                tags = tagIds ?: old.tags)
        }
        return Result.Success(true)
    }

    suspend fun deleteTodo(settings: UserSettings, taskId: String): Result<Boolean> {
        calls += "deleteTodo:$taskId"
        fetchFailure?.let { return Result.Error(it, fetchStatus) }
        val outcome = deleteOutcome(taskId)
        if (outcome is Result.Success && deleteRemovesFromCloud) {
            cloud.removeAll { it.id == taskId }
            fetchTodoMissing += taskId
        }
        return outcome
    }

    suspend fun fetchTags(settings: UserSettings): Result<Map<String, String>> {
        calls += "fetchTags"
        return failOr { tags.toMap() }
    }

    suspend fun createTag(settings: UserSettings, name: String): Result<String?> {
        calls += "createTag:$name"
        fetchFailure?.let { return Result.Error(it, fetchStatus) }
        val id = "TAG-${++nextTagId}"
        tags[name] = id
        return Result.Success(id)
    }

    suspend fun updateTag(settings: UserSettings, tagId: String, name: String): Result<Boolean> {
        calls += "updateTag:$tagId:$name"
        fetchFailure?.let { return Result.Error(it, fetchStatus) }
        val entry = tags.entries.firstOrNull { it.value == tagId }
        if (entry != null) { tags.remove(entry.key); tags[name] = tagId }
        return Result.Success(true)
    }

    suspend fun ensureTag(settings: UserSettings, name: String): Result<String?> {
        calls += "ensureTag:$name"
        fetchFailure?.let { return Result.Error(it, fetchStatus) }
        tags[name]?.let { return Result.Success(it) }
        return createTag(settings, name)
    }

    suspend fun ensureHabit(settings: UserSettings, combo: Boolean): Result<String> {
        calls += "ensureHabit:${if (combo) "combo" else "pomo"}"
        return failOr { if (combo) "HABIT-COMBO-STUB" else "HABIT-POMO-STUB" }
    }

    suspend fun sendPrivateMessage(settings: UserSettings, message: String): Result<JSONObject?> {
        calls += "sendPrivateMessage"
        return failOr { JSONObject() }
    }

    suspend fun verifyCredentials(settings: UserSettings): Result<String> {
        calls += "verifyCredentials"
        return failOr { "stub-user" }
    }

    // ---- non-suspend helpers (pure, mirror production semantics) ----

    fun validServerUrl(value: String): Boolean = value.isBlank() || runCatching { checkedUrl(value); true }.getOrDefault(false)

    fun apiRoot(settings: UserSettings): String =
        if (settings.developerServerUrl.isBlank()) SERVER_URL else checkedUrl(settings.developerServerUrl)

    private fun checkedUrl(value: String): String {
        val url = java.net.URI(value.trim())
        require(url.scheme == "https" && url.userInfo == null && url.query == null && url.fragment == null && url.host != null)
        val port = if (url.port > 0) ":${url.port}" else ""
        val path = (url.path ?: "").trimEnd('/')
        return "https://${url.host}$port$path/"
    }
}

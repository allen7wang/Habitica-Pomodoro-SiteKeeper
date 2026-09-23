package com.habitica.pomodoro.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Habitica REST API 客户端 —— 端点、x-client header、解析规则与 Swift 端逐条对齐。
 *
 * 关键约定（踩坑记录，来自 Swift 端）：
 * - Dailies 的类型参数必须是 `type=dailys`（不是 dailies），
 *   否则报 `Task type must be one of "habits", "dailys", "todos", "rewards", "completedTodos".`
 * - 注册时间在 `auth.timestamps`，不是 `auth.local.timestamps`
 * - API 不返回 maxMP / maxHealth / toNextLevel，需用公式计算（见 HabiticaProfile）
 */
object HabiticaAPI {

    private const val SERVER_URL = "https://habitica.com/api/v3/"
    // 与 Swift HabiticaConsts.xClientHeader 一致，便于 Habitica 侧识别本应用
    private const val X_CLIENT = "5a8238ab-1819-4f7f-a750-f23264719a2d-HabiticaPomodoroSiteKeeper-v2"

    private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /** API 调用结果：成功返回 data 里的 JSON，失败返回错误描述 */
    sealed class Result<out T> {
        data class Success<T>(val value: T) : Result<T>()
        data class Error(val message: String) : Result<Nothing>()
    }

    private fun Request.Builder.withAuth(settings: UserSettings): Request.Builder = apply {
        header("x-client", X_CLIENT)
        header("x-api-user", settings.uid)
        header("x-api-key", settings.apiToken)
    }

    private fun canCall(settings: UserSettings): Boolean =
        settings.connectHabitica && settings.uid.isNotBlank() && settings.apiToken.isNotBlank()

    // MARK: - 通用请求

    private suspend fun request(
        settings: UserSettings,
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
    ): Result<JSONObject?> = withContext(Dispatchers.IO) {
        if (!canCall(settings)) return@withContext Result.Error("未连接 Habitica：请先在设置中填写 User ID 与 API Token")
        try {
            val builder = Request.Builder().url(SERVER_URL + path).withAuth(settings)
            when (method) {
                "GET" -> builder.get()
                "DELETE" -> builder.delete()
                else -> builder.method(
                    method,
                    (body?.toString() ?: "{}").toRequestBody(JSON_MEDIA),
                )
            }
            client.newCall(builder.build()).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    val msg = runCatching { JSONObject(text).optString("error", text) }.getOrDefault(text)
                    return@use Result.Error("HTTP ${resp.code}: $msg")
                }
                val json = runCatching { JSONObject(text) }.getOrNull()
                Result.Success(json?.optJSONObject("data"))
            }
        } catch (e: Exception) {
            Result.Error("网络错误: ${e.message}")
        }
    }

    // MARK: - 角色信息（Role 页）

    /** 获取账号角色信息：等级、HP/MP/EXP/GP、四维属性、成就 */
    suspend fun fetchProfile(settings: UserSettings): Result<HabiticaProfile> {
        val result = request(settings, "user")
        return when (result) {
            is Result.Error -> result
            is Result.Success -> {
                val d = result.value
                    ?: return Result.Error("返回数据为空")
                Result.Success(parseProfile(d))
            }
        }
    }

    private fun parseProfile(d: JSONObject): HabiticaProfile {
        var username = ""
        var registeredAt = ""
        d.optJSONObject("auth")?.let { auth ->
            auth.optJSONObject("local")?.let { local ->
                username = local.optString("username", "")
            }
            // 注册时间在 auth.timestamps（不是 auth.local.timestamps）
            auth.optJSONObject("timestamps")?.let { ts ->
                val millis = ts.optLong("registered", 0L)
                if (millis > 0) {
                    registeredAt = java.text.SimpleDateFormat(
                        "yyyy-MM-dd", java.util.Locale.US,
                    ).format(java.util.Date(millis))
                }
            }
        }

        val stats = d.optJSONObject("stats") ?: JSONObject()
        val prefs = d.optJSONObject("preferences") ?: JSONObject()
        val achievements = d.optJSONObject("achievements") ?: JSONObject()

        var questsTotal = 0
        achievements.optJSONObject("quests")?.let { q ->
            q.keys().forEach { k -> questsTotal += q.optInt(k, 0) }
        }

        return HabiticaProfile(
            username = username,
            className = prefs.optString("class", "").replaceFirstChar { it.uppercase() },
            level = stats.optInt("lvl", 0),
            exp = stats.optDouble("exp", 0.0),
            hp = stats.optDouble("hp", 0.0),
            mp = stats.optDouble("mp", 0.0),
            gp = stats.optDouble("gp", 0.0),
            str = stats.optInt("str", 0),
            con = stats.optInt("con", 0),
            int = stats.optInt("int", 0),
            per = stats.optInt("per", 0),
            streak = achievements.optInt("streak", 0),
            perfectDays = achievements.optInt("perfectCount", 0),
            questsTotal = questsTotal,
            registeredAt = registeredAt,
        )
    }

    // MARK: - 任务列表（Habits / Dailies）

    /** data 为数组的接口专用（tasks/user?type=...、tags） */
    private suspend fun requestArray(
        settings: UserSettings,
        path: String,
    ): Result<List<JSONObject>> = withContext(Dispatchers.IO) {
        if (!canCall(settings)) return@withContext Result.Error("未连接 Habitica：请先在设置中填写 User ID 与 API Token")
        try {
            val builder = Request.Builder().url(SERVER_URL + path).withAuth(settings).get()
            client.newCall(builder.build()).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    val msg = runCatching { JSONObject(text).optString("error", text) }.getOrDefault(text)
                    return@use Result.Error("HTTP ${resp.code}: $msg")
                }
                val arr = runCatching { JSONObject(text).optJSONArray("data") }.getOrNull()
                val list = mutableListOf<JSONObject>()
                if (arr != null) for (i in 0 until arr.length()) arr.optJSONObject(i)?.let { list.add(it) }
                Result.Success(list)
            }
        } catch (e: Exception) {
            Result.Error("网络错误: ${e.message}")
        }
    }

    suspend fun fetchTaskItems(settings: UserSettings, type: String): Result<List<HabiticaTaskItem>> {
        return when (val result = requestArray(settings, "tasks/user?type=$type")) {
            is Result.Error -> result
            is Result.Success -> Result.Success(result.value.map { obj ->
                HabiticaTaskItem(
                    id = obj.optString("_id", obj.optString("id", "")),
                    text = obj.optString("text", ""),
                    notes = obj.optString("notes", ""),
                    value = obj.optDouble("value", 0.0),
                    completed = obj.optBoolean("completed", false),
                    canUp = obj.optBoolean("up", true),
                    canDown = obj.optBoolean("down", true),
                    // dailies: isDue 在 JSON 里叫 isDue；habits 无此字段
                    isDue = obj.optBoolean("isDue", true),
                )
            })
        }
    }

    /** 打分（up / down），返回最新 stats（金币/经验/血量），用于刷新 Role 数据 */
    suspend fun scoreTask(
        settings: UserSettings,
        taskId: String,
        direction: String,
    ): Result<JSONObject?> {
        return request(settings, "tasks/$taskId/score/$direction", method = "POST")
    }

    // MARK: - Todos（Task 页任务同步为 Habitica todo）

    /** 创建 todo，返回 task id */
    suspend fun createTodo(
        settings: UserSettings,
        text: String,
        notes: String,
        tagIds: List<String>,
    ): Result<String?> {
        val body = JSONObject().apply {
            put("type", "todo")
            put("text", text)
            put("notes", notes)
            if (tagIds.isNotEmpty()) put("tags", org.json.JSONArray(tagIds))
        }
        return when (val result = request(settings, "tasks/user", method = "POST", body = body)) {
            is Result.Error -> result
            is Result.Success -> Result.Success(result.value?.optString("_id", null))
        }
    }

    /** 更新 todo 文本/备注/标签 */
    suspend fun updateTodo(
        settings: UserSettings,
        taskId: String,
        text: String,
        notes: String = "",
        tagIds: List<String>? = null,
    ): Result<Boolean> {
        val body = JSONObject().apply {
            put("text", text)
            if (notes.isNotEmpty()) put("notes", notes)
            tagIds?.let { put("tags", org.json.JSONArray(it)) }
        }
        return when (val result = request(settings, "tasks/$taskId", method = "PUT", body = body)) {
            is Result.Error -> result
            is Result.Success -> Result.Success(true)
        }
    }

    /** 删除 todo */
    suspend fun deleteTodo(settings: UserSettings, taskId: String): Result<Boolean> {
        return when (val result = request(settings, "tasks/$taskId", method = "DELETE")) {
            is Result.Error -> result
            is Result.Success -> Result.Success(true)
        }
    }

    // MARK: - Tags（分类名同步为 Habitica tag）

    /** 获取全部 tag：name -> id */
    suspend fun fetchTags(settings: UserSettings): Result<Map<String, String>> {
        return when (val result = requestArray(settings, "tags")) {
            is Result.Error -> result
            is Result.Success -> Result.Success(result.value.associate { obj ->
                obj.optString("name", "") to obj.optString("id", "")
            }.filterKeys { it.isNotEmpty() })
        }
    }

    /** 创建 tag，返回 tag id */
    suspend fun createTag(settings: UserSettings, name: String): Result<String?> {
        val body = JSONObject().apply { put("name", name) }
        return when (val result = request(settings, "tags", method = "POST", body = body)) {
            is Result.Error -> result
            is Result.Success -> Result.Success(result.value?.optString("id", null))
        }
    }

    /** 重命名 tag（分类名修改时同步） */
    suspend fun updateTag(settings: UserSettings, tagId: String, name: String): Result<Boolean> {
        val body = JSONObject().apply { put("name", name) }
        return when (val result = request(settings, "tags/$tagId", method = "PUT", body = body)) {
            is Result.Error -> result
            is Result.Success -> Result.Success(true)
        }
    }

    /**
     * 确保分类对应的 tag 存在，返回 tag id。
     * 先查已有 tag（按名字精确匹配），没有则创建 —— 与 Swift 端 ensureTag 行为一致，
     * 避免重复创建同名 tag。
     */
    suspend fun ensureTag(settings: UserSettings, name: String): Result<String?> {
        if (!canCall(settings)) return Result.Error("未连接 Habitica")
        return when (val tags = fetchTags(settings)) {
            is Result.Error -> tags
            is Result.Success -> {
                val existing = tags.value[name]
                if (existing != null) Result.Success(existing)
                else createTag(settings, name)
            }
        }
    }

    // MARK: - 连通性自检

    /** 验证 uid/token 是否有效（Role 页与设置页用） */
    suspend fun verifyCredentials(settings: UserSettings): Result<String> {
        return when (val result = fetchProfile(settings)) {
            is Result.Error -> result
            is Result.Success -> Result.Success(result.value.username.ifEmpty { "已连接" })
        }
    }
}

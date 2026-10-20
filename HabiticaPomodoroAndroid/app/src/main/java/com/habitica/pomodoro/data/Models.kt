package com.habitica.pomodoro.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.Locale

/**
 * 数据模型 —— 字段名与 macOS/iOS 端 Swift Codable 保持逐字一致，
 * 使 Habitica todo/tag 的语义与三端对齐（本地 JSON 在 Android 上不跨端同步）。
 */

// MARK: - 用户设置（对应 Swift UserSettings 的子集 + 番茄钟/块参数）

data class UserSettings(
    val uid: String = "",
    val apiToken: String = "",
    val connectHabitica: Boolean = true,
    val pomoDurationMins: Int = 25,
    val breakDuration: Int = 5,
    val longBreakDuration: Int = 30,
    val pomoSetNum: Int = 4,
    val manualBreak: Boolean = true,
    val pomoHabitPlus: Boolean = false,
    val pomoHabitMinus: Boolean = false,
    val pomoEndSound: String = "None",
    val pomoEndSoundVolume: Double = 0.5,
    val pomodoroTaskId: String? = null,
    val pomodoroSetTaskId: String? = null,
    val pomoSetHabitPlus: Boolean = false,
    val breakExtention: Int = 2,
    val resetPomoAfterBreak: Boolean = false,
    val breakExtentionFails: Boolean = false,
    val breakExtentionNotify: Boolean = false,
    val longBreakNotify: Boolean = false,
    val breakEndSound: String = "None",
    val breakEndSoundVolume: Double = 0.5,
    val ambientSound: String = "None",
    val ambientSoundVolume: Double = 0.5,
    /** 环境音来源："custom" = 内置环境音单轨；"qishi" = 每个番茄随机播放一个栖时场景混音。
     *  字段名与 Apple 端设置 JSON 逐字一致；旧数据缺字段时宽松解码为 "custom"。 */
    val ambientSource: String = "custom",
    val customPomodoroTask: Boolean = false,
    val customSetTask: Boolean = false,
    val developerServerUrl: String = "",
    val enableBlockMode: Boolean = false,
    val blockCount: Int = 8,
    val blockPomoCount: Int = 6,
    val blockGoals: List<String> = emptyList(),
    val blockTasks: List<List<BlockTask>> = List(8) { emptyList() },
    val blockRewardEnabled: Boolean = true,
    val blockSprintReminder: Boolean = true,
    val blockStartReminder: Boolean = true,
    val blockReminderMinutes: Int = 5,
    val blockTimeRanges: List<BlockTimeRange> = BlockTimeRange.defaults(),
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("breakExtention", breakExtention)
        put("resetPomoAfterBreak", resetPomoAfterBreak)
        put("breakExtentionFails", breakExtentionFails)
        put("breakExtentionNotify", breakExtentionNotify)
        put("longBreakNotify", longBreakNotify)
        put("breakEndSound", breakEndSound)
        put("breakEndSoundVolume", breakEndSoundVolume)
        put("ambientSound", ambientSound)
        put("ambientSoundVolume", ambientSoundVolume)
        put("ambientSource", ambientSource)
        put("customPomodoroTask", customPomodoroTask)
        put("customSetTask", customSetTask)
        put("developerServerUrl", developerServerUrl)
        put("uid", uid)
        put("apiToken", apiToken)
        put("connectHabitica", connectHabitica)
        put("pomoDurationMins", pomoDurationMins)
        put("breakDuration", breakDuration)
        put("longBreakDuration", longBreakDuration)
        put("pomoSetNum", pomoSetNum)
        put("manualBreak", manualBreak)
        put("pomoHabitPlus", pomoHabitPlus)
        put("pomoHabitMinus", pomoHabitMinus)
        put("pomoEndSound", pomoEndSound)
        put("pomoEndSoundVolume", pomoEndSoundVolume)
        put("enableBlockMode", enableBlockMode)
        put("pomodoroTaskId", pomodoroTaskId ?: JSONObject.NULL)
        put("pomodoroSetTaskId", pomodoroSetTaskId ?: JSONObject.NULL)
        put("pomoSetHabitPlus", pomoSetHabitPlus)
        put("blockCount", blockCount)
        put("blockPomoCount", blockPomoCount)
        put("blockGoals", JSONArray(blockGoals))
        put("blockTasks", JSONArray().apply { blockTasks.forEach { tasks -> put(JSONArray().apply { tasks.forEach { put(it.toJson()) } }) } })
        put("blockRewardEnabled", blockRewardEnabled)
        put("blockSprintReminder", blockSprintReminder)
        put("blockStartReminder", blockStartReminder)
        put("blockReminderMinutes", blockReminderMinutes)
        put("blockTimeRanges", JSONArray().apply {
            blockTimeRanges.forEach { r -> put(r.toJson()) }
        })
    }

    companion object {
        fun fromJson(json: JSONObject): UserSettings = UserSettings(
            breakExtention = json.optInt("breakExtention", 2),
            resetPomoAfterBreak = json.optBoolean("resetPomoAfterBreak", false),
            breakExtentionFails = json.optBoolean("breakExtentionFails", false),
            breakExtentionNotify = json.optBoolean("breakExtentionNotify", false),
            longBreakNotify = json.optBoolean("longBreakNotify", false),
            breakEndSound = json.optString("breakEndSound", "None"),
            breakEndSoundVolume = json.optDouble("breakEndSoundVolume", 0.5),
            ambientSound = json.optString("ambientSound", "None"),
            ambientSoundVolume = json.optDouble("ambientSoundVolume", 0.5),
            ambientSource = json.optString("ambientSource", "custom").takeIf { it.isNotBlank() && it != "null" } ?: "custom",
            customPomodoroTask = json.optBoolean("customPomodoroTask", json.optString("pomodoroTaskId").let { it.isNotBlank() && it != "null" }),
            customSetTask = json.optBoolean("customSetTask", json.optString("pomodoroSetTaskId").let { it.isNotBlank() && it != "null" }),
            developerServerUrl = json.optString("developerServerUrl", ""),
            uid = json.optString("uid", ""),
            apiToken = json.optString("apiToken", ""),
            connectHabitica = json.optBoolean("connectHabitica", true),
            pomoDurationMins = json.optInt("pomoDurationMins", 25),
            breakDuration = json.optInt("breakDuration", 5),
            longBreakDuration = json.optInt("longBreakDuration", 30),
            pomoSetNum = json.optInt("pomoSetNum", 4),
            manualBreak = json.optBoolean("manualBreak", true),
            pomoHabitPlus = json.optBoolean("pomoHabitPlus", false),
            pomoHabitMinus = json.optBoolean("pomoHabitMinus", false),
            pomoEndSound = json.optString("pomoEndSound", "None"),
            pomoEndSoundVolume = json.optDouble("pomoEndSoundVolume", 0.5),
            enableBlockMode = json.optBoolean("enableBlockMode", false),
            pomodoroTaskId = json.optString("pomodoroTaskId", "").takeIf { it.isNotBlank() && it != "null" },
            pomodoroSetTaskId = json.optString("pomodoroSetTaskId", "").takeIf { it.isNotBlank() && it != "null" },
            pomoSetHabitPlus = json.optBoolean("pomoSetHabitPlus", false),
            blockCount = json.optInt("blockCount", 8).coerceIn(1, 24),
            blockPomoCount = json.optInt("blockPomoCount", 6).coerceIn(1, 12),
            blockGoals = json.optJSONArray("blockGoals")?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList(),
            blockTasks = json.optJSONArray("blockTasks")?.let { a -> (0 until a.length()).map { i ->
                a.optJSONArray(i)?.let { inner -> (0 until inner.length()).mapNotNull { j -> inner.optJSONObject(j)?.let(BlockTask::fromJson) } } ?: emptyList()
            } } ?: List(8) { emptyList() },
            blockRewardEnabled = json.optBoolean("blockRewardEnabled", true),
            blockSprintReminder = json.optBoolean("blockSprintReminder", true),
            blockStartReminder = json.optBoolean("blockStartReminder", true),
            blockReminderMinutes = json.optInt("blockReminderMinutes", 5).coerceIn(1, 60),
            blockTimeRanges = json.optJSONArray("blockTimeRanges")?.let { arr ->
                (0 until arr.length()).map { BlockTimeRange.fromJson(arr.getJSONObject(it)) }
            } ?: BlockTimeRange.defaults(),
        ).normalized()
    }
}

/** 块时间范围；startMinutes 为一天内的分钟数，逻辑日边界取第一个块的 startMinutes */
data class BlockTimeRange(
    val startHour: Int,
    val startMinute: Int,
    val endHour: Int,
    val endMinute: Int,
) {
    val startMinutes: Int get() = startHour * 60 + startMinute
    val endMinutes: Int get() = endHour * 60 + endMinute

    fun contains(minuteOfDay: Int): Boolean = if (startMinutes < endMinutes) {
        minuteOfDay in startMinutes until endMinutes
    } else {
        minuteOfDay >= startMinutes || minuteOfDay < endMinutes
    }

    val displayString: String get() = "%02d:%02d–%02d:%02d".format(java.util.Locale.US, startHour, startMinute, endHour, endMinute)

    fun toJson(): JSONObject = JSONObject().apply {
        put("startHour", startHour)
        put("startMinute", startMinute)
        put("endHour", endHour)
        put("endMinute", endMinute)
    }

    companion object {
        fun fromJson(json: JSONObject) = BlockTimeRange(
            startHour = json.optInt("startHour", 0).coerceIn(0, 23),
            startMinute = json.optInt("startMinute", 0).coerceIn(0, 59),
            endHour = json.optInt("endHour", 0).coerceIn(0, 23),
            endMinute = json.optInt("endMinute", 0).coerceIn(0, 59),
        )

        /** 与 Swift UserSettings.init() 一致的默认 8 块（4:00 起，每块 3 小时） */
        fun defaults(): List<BlockTimeRange> = listOf(
            BlockTimeRange(4, 0, 7, 0),
            BlockTimeRange(7, 0, 10, 0),
            BlockTimeRange(10, 0, 13, 0),
            BlockTimeRange(13, 0, 16, 0),
            BlockTimeRange(16, 0, 19, 0),
            BlockTimeRange(19, 0, 22, 0),
            BlockTimeRange(22, 0, 1, 0),
            BlockTimeRange(1, 0, 4, 0),
        )
    }
}

// MARK: - Top Three（每日三件事 / 琐事）

/** 注意：Swift 端 UUID 序列化为大写连字符格式，这里保持一致以便 Habitica 侧对齐。
 *  全字段 val（不可变）：ViewModel 状态持有实例，原地 mutate 会让 StateFlow 判定
 *  新旧值相等而吞掉发射（UI 不刷新），因此更新一律走 copy()。 */
data class TopThreeTask(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val title: String = "",
    val isCompleted: Boolean = false,
    val habiticaTaskId: String? = null,
    val movedToToday: Boolean = false,
    val syncPending: Boolean = false,
    val syncError: String? = null,
    val pendingCreateTitle: String? = null,
    val pendingCreateNotes: String? = null,
    val cloudAccount: String? = null,
    val syncVersion: Long = 0,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("isCompleted", isCompleted)
        habiticaTaskId?.let { put("habiticaTaskId", it) } ?: put("habiticaTaskId", JSONObject.NULL)
        put("movedToToday", movedToToday)
        put("syncPending", syncPending)
        put("syncError", syncError ?: JSONObject.NULL)
        put("pendingCreateTitle", pendingCreateTitle ?: JSONObject.NULL)
        put("pendingCreateNotes", pendingCreateNotes ?: JSONObject.NULL)
        put("cloudAccount", cloudAccount ?: JSONObject.NULL)
        put("syncVersion", syncVersion)
    }

    companion object {
        fun fromJson(json: JSONObject) = TopThreeTask(
            id = json.optString("id", UUID.randomUUID().toString().uppercase()),
            title = json.optString("title", ""),
            isCompleted = json.optBoolean("isCompleted", false),
            habiticaTaskId = if (json.isNull("habiticaTaskId")) null else json.optString("habiticaTaskId"),
            movedToToday = json.optBoolean("movedToToday", false),
            syncPending = json.optBoolean("syncPending", json.optString("title").isNotBlank() && json.optString("habiticaTaskId").let { it.isBlank() || it == "null" }),
            pendingCreateTitle = json.optString("pendingCreateTitle").takeIf { it.isNotBlank() && it != "null" },
            pendingCreateNotes = json.optString("pendingCreateNotes").takeIf { it.isNotBlank() && it != "null" },
            syncError = json.optString("syncError").takeIf { it.isNotBlank() && it != "null" },
            cloudAccount = json.optString("cloudAccount").takeIf { it.isNotBlank() && it != "null" },
            syncVersion = json.optLong("syncVersion", 0).coerceAtLeast(0),
        )
    }
}

/** 一天（逻辑日）的任务，按分类分组：Work/MyOwn 固定 3 槽，第 3 个及以后为自由列表 */
data class TopThreeDay(
    val date: String,
    val taskGroups: List<List<TopThreeTask>> = emptyList(),
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("date", date)
        put("taskGroups", JSONArray().apply {
            taskGroups.forEach { group ->
                put(JSONArray().apply { group.forEach { t -> put(t.toJson()) } })
            }
        })
    }

    companion object {
        fun fromJson(json: JSONObject): TopThreeDay {
            val groups = mutableListOf<List<TopThreeTask>>()
            json.optJSONArray("taskGroups")?.let { outer ->
                for (i in 0 until outer.length()) {
                    val inner = outer.optJSONArray(i) ?: continue
                    val list = mutableListOf<TopThreeTask>()
                    for (j in 0 until inner.length()) {
                        list.add(TopThreeTask.fromJson(inner.getJSONObject(j)))
                    }
                    groups.add(list)
                }
            }
            return TopThreeDay(date = json.optString("date", ""), taskGroups = groups)
        }
    }
}

/** 持久化单元：分类名可自定义 + Habitica tag 映射 + 历史 */
data class TopThreeStore(
    val categoryNames: List<String> = listOf("Work", "MyOwn", "Chores"),
    val categoryTagIds: Map<String, String> = emptyMap(),
    val history: Map<String, TopThreeDay> = emptyMap(),
    val deletedCloudIds: Set<String> = emptySet(),
    // Remote ID -> explicitly deleted original UUID, scoped to this owner partition.
    val deletedCloudTaskOrigins: Map<String, String> = emptyMap(),
    val deletedCreateMarkers: Set<String> = emptySet(),
    // Remote ID -> lost-creation marker ("notes\ntitle"), recorded when the id is enqueued
    // for deletion. A queue entry later consumed with marker == null (restart retry) must
    // still retire its marker in the same atomic save, or the marker orphans forever (D1).
    val deletedCloudIdMarkers: Map<String, String> = emptyMap(),
    val cloudAccount: String? = null,
    val ownerInitialized: Boolean = false,
    val accountStores: Map<String, TopThreeStore> = emptyMap(),
    // tag ID -> desired name; retry must rename the old ID rather than create another tag.
    val pendingTagNames: Map<String, String> = emptyMap(),
    val pomodoroHabitId: String? = null,
    val comboHabitId: String? = null,
) {
    /** Project valid legacy owner keys without changing settings or repairing invalid credentials. */
    private fun canonicalOwners(): TopThreeStore {
        fun project(value: TopThreeStore) = value.copy(accountStores = emptyMap(),
            cloudAccount = canonicalCloudAccount(value.cloudAccount),
            history = value.history.mapValues { (_, day) -> day.copy(taskGroups = day.taskGroups.map { group ->
                group.map { it.copy(cloudAccount = canonicalCloudAccount(it.cloudAccount)) }
            }) })
        var current = project(this)
        val saved = linkedMapOf<String, TopThreeStore>()
        for ((key, value) in accountStores) {
            val canonicalKey = canonicalCloudAccount(key)!!
            val next = project(value)
            if (canonicalKey == (current.cloudAccount ?: "")) current = mergeOwnerPartitions(current, next)
            else saved[canonicalKey] = saved[canonicalKey]?.let { mergeOwnerPartitions(it, next) } ?: next
        }
        return current.copy(accountStores = saved)
    }

    /** Migrate old JSON once; then retain each owner's UUIDs, mappings and queues independently. */
    fun forAccount(owner: String?): TopThreeStore {
        val canonical = canonicalOwners()
        val canonicalOwner = canonicalCloudAccount(owner)
        if (canonical != this || canonicalOwner != owner) return canonical.forAccount(canonicalOwner)
        // D3 (evaluated; adoption kept): the first owner initialization adopts pre-existing
        // deletedCloudIds/deletedCloudTaskOrigins/deletedCreateMarkers wholesale. Legacy JSON
        // carries no reliable ownership evidence to filter by: only stores written AFTER the
        // owner-partition feature stamp cloudAccount on task rows (and those have
        // ownerInitialized == true, so they never reach this branch), while the queue/marker
        // rows never carried any per-entry owner metadata at all. The residual risk is bounded:
        // deletes execute only against the server-side authenticated account (a foreign id
        // 404s and stays queued instead of deleting anything), and every history consumer
        // (pendingCreateCandidates/remoteIdOccupied/mayDelete/merge) filters rows by
        // cloudAccount. Adoption preserves the delete intents of single-account legacy users —
        // the only population that reaches this path — which outweighs discarding them.
        if (!ownerInitialized) return copy(cloudAccount = owner, ownerInitialized = true,
            history = history.mapValues { (_, day) -> day.copy(taskGroups = day.taskGroups.map { group ->
                group.map { if (it.cloudAccount == null) it.copy(cloudAccount = owner) else it }
            }) })
        if (cloudAccount == owner) return this
        val saved = accountStores + ((cloudAccount ?: "") to copy(accountStores = emptyMap()))
        val next = saved[owner ?: ""] ?: TopThreeStore(categoryNames = categoryNames, cloudAccount = owner, ownerInitialized = true)
        return next.copy(accountStores = saved - (owner ?: ""))
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("cloudAccount", cloudAccount ?: JSONObject.NULL)
        put("ownerInitialized", ownerInitialized)
        put("accountStores", JSONObject().apply { accountStores.forEach { (owner, value) -> put(owner, value.copy(accountStores = emptyMap()).toJson()) } })
        put("pendingTagNames", JSONObject(pendingTagNames))
        put("pomodoroHabitId", pomodoroHabitId ?: JSONObject.NULL)
        put("comboHabitId", comboHabitId ?: JSONObject.NULL)
        put("deletedCloudIds", JSONArray(deletedCloudIds.toList()))
        put("deletedCloudTaskOrigins", JSONObject(deletedCloudTaskOrigins))
        put("deletedCreateMarkers", JSONArray(deletedCreateMarkers.toList()))
        put("deletedCloudIdMarkers", JSONObject(deletedCloudIdMarkers))
        put("categoryNames", JSONArray(categoryNames))
        put("categoryTagIds", JSONObject().apply {
            categoryTagIds.forEach { (k, v) -> put(k, v) }
        })
        put("history", JSONObject().apply {
            history.forEach { (k, v) -> put(k, v.toJson()) }
        })
    }

    companion object {
        fun fromJson(json: JSONObject): TopThreeStore {
            val names = mutableListOf<String>()
            json.optJSONArray("categoryNames")?.let { arr ->
                for (i in 0 until arr.length()) names.add(arr.optString(i))
            }
            if (names.size < 3) names.addAll(listOf("Work", "MyOwn", "Chores").drop(names.size))

            val tagIds = mutableMapOf<String, String>()
            json.optJSONObject("categoryTagIds")?.let { obj ->
                obj.keys().forEach { k -> tagIds[k] = obj.optString(k) }
            }

            val history = mutableMapOf<String, TopThreeDay>()
            json.optJSONObject("history")?.let { obj ->
                obj.keys().forEach { k -> history[k] = TopThreeDay.fromJson(obj.getJSONObject(k)) }
            }

            val accounts = json.optJSONObject("accountStores")?.let { obj -> obj.keys().asSequence().mapNotNull { k ->
                obj.optJSONObject(k)?.let { k to fromJson(it).copy(accountStores = emptyMap()) }
            }.toMap() } ?: emptyMap()
            val pendingNames = json.optJSONObject("pendingTagNames")?.let { obj -> obj.keys().asSequence().associateWith { obj.optString(it) } } ?: emptyMap()
            return TopThreeStore(categoryNames = names, categoryTagIds = tagIds, history = history,
                cloudAccount = json.optString("cloudAccount").takeIf { it.isNotBlank() && it != "null" },
                ownerInitialized = json.optBoolean("ownerInitialized", json.has("cloudAccount")), accountStores = accounts,
                pendingTagNames = pendingNames,
                pomodoroHabitId = json.optString("pomodoroHabitId").takeIf { it.isNotBlank() && it != "null" },
                comboHabitId = json.optString("comboHabitId").takeIf { it.isNotBlank() && it != "null" },
                deletedCloudIds = json.optJSONArray("deletedCloudIds")?.let { arr -> (0 until arr.length()).map { arr.optString(it) }.toSet() } ?: emptySet(),
                deletedCloudTaskOrigins = json.optJSONObject("deletedCloudTaskOrigins")?.let { obj -> obj.keys().asSequence().mapNotNull { id ->
                    (obj.opt(id) as? String)?.takeIf { it.isNotBlank() }?.let { id to it }
                }.toMap() } ?: emptyMap(),
                deletedCreateMarkers = json.optJSONArray("deletedCreateMarkers")?.let { arr -> (0 until arr.length()).map { arr.optString(it) }.toSet() } ?: emptySet(),
                deletedCloudIdMarkers = json.optJSONObject("deletedCloudIdMarkers")?.let { obj -> obj.keys().asSequence().mapNotNull { id ->
                    (obj.opt(id) as? String)?.takeIf { it.isNotBlank() }?.let { id to it }
                }.toMap() } ?: emptyMap())
        }
    }
}

/** Case-only owner aliases describe the same account; preserve distinct UUIDs and durable queues. */
private fun mergeOwnerPartitions(primary: TopThreeStore, secondary: TopThreeStore): TopThreeStore {
    val names = primary.categoryNames + secondary.categoryNames.filterNot { it in primary.categoryNames }
    val history = (primary.history.keys + secondary.history.keys).associateWith { date ->
        val first = primary.history[date]
        val second = secondary.history[date]
        val groups = names.map { name ->
            val a = first?.taskGroups?.getOrNull(primary.categoryNames.indexOf(name)).orEmpty()
            val b = second?.taskGroups?.getOrNull(secondary.categoryNames.indexOf(name)).orEmpty()
            (a + b).distinctBy { it.id to it.movedToToday }
        }
        TopThreeDay(date, groups)
    }
    return primary.copy(categoryNames = names, history = history,
        categoryTagIds = secondary.categoryTagIds + primary.categoryTagIds,
        deletedCloudIds = primary.deletedCloudIds + secondary.deletedCloudIds,
        // Missing/conflicting legacy origins must not gain an archive exemption during alias migration.
        deletedCloudTaskOrigins = (secondary.deletedCloudTaskOrigins + primary.deletedCloudTaskOrigins).filter { (id, origin) ->
            (id !in primary.deletedCloudIds || primary.deletedCloudTaskOrigins[id] == origin) &&
                (id !in secondary.deletedCloudIds || secondary.deletedCloudTaskOrigins[id] == origin)
        },
        deletedCreateMarkers = primary.deletedCreateMarkers + secondary.deletedCreateMarkers,
        deletedCloudIdMarkers = secondary.deletedCloudIdMarkers + primary.deletedCloudIdMarkers,
        pendingTagNames = secondary.pendingTagNames + primary.pendingTagNames,
        pomodoroHabitId = primary.pomodoroHabitId ?: secondary.pomodoroHabitId,
        comboHabitId = primary.comboHabitId ?: secondary.comboHabitId)
}

/** Credential-free configuration retained for a focus and its following break/grace phases. */
data class TimerBusinessSnapshot(val settings: UserSettings, val cloudAccount: String?) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("cloudAccount", cloudAccount ?: JSONObject.NULL)
        put("business", settings.toJson().apply { remove("uid"); remove("apiToken"); remove("developerServerUrl") })
    }
    fun withCurrentCredentials(current: UserSettings): UserSettings? {
        if (cloudAccount == null || canonicalCloudAccount(cloudAccount) != current.cloudAccount() || !settings.connectHabitica || !current.connectHabitica) return null
        return settings.copy(uid = current.uid, apiToken = current.apiToken, developerServerUrl = current.developerServerUrl)
    }
    companion object {
        fun capture(settings: UserSettings) = TimerBusinessSnapshot(
            settings.copy(uid = "", apiToken = "", developerServerUrl = ""), settings.cloudAccount())
        fun fromJson(json: JSONObject): TimerBusinessSnapshot? = json.optJSONObject("business")?.let {
            TimerBusinessSnapshot(UserSettings.fromJson(it).copy(uid = "", apiToken = "", developerServerUrl = ""),
                canonicalCloudAccount(json.optString("cloudAccount").takeIf { owner -> owner.isNotBlank() && owner != "null" }))
        }
    }
}

private val habiticaUidPattern = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

/** Validate the literal credential; never trim or repair a user's UID. */
fun isValidHabiticaUid(uid: String): Boolean = habiticaUidPattern.matches(uid)

/** Project only a previously valid UID in a stored ownership key, not the credential itself. */
fun canonicalCloudAccount(owner: String?): String? {
    if (owner == null) return null
    val separator = owner.indexOf('|')
    if (separator < 0) return owner
    val uid = owner.substring(0, separator)
    return if (isValidHabiticaUid(uid)) uid.lowercase(Locale.ROOT) + owner.substring(separator) else owner
}

/** Stable ownership: token rotation and connect/disconnect are not a different account. */
fun UserSettings.cloudAccount(): String? = if (!isValidHabiticaUid(uid)) null else
    runCatching { "${uid.lowercase(Locale.ROOT)}|${HabiticaAPI.apiRoot(this)}" }.getOrNull()

// MARK: - Habitica 任务项 / 角色信息

data class HabiticaTaskItem(
    val id: String,
    val text: String,
    val notes: String,
    val value: Double,
    val completed: Boolean,
    val canUp: Boolean,
    val canDown: Boolean,
    val isDue: Boolean,
)

/**
 * 角色面板数据。上限公式与 Swift 端一致：
 * - maxHealth = 50（Habitica 固定）
 * - maxMP = 30 + 3*(level-1) + INT/2
 */
data class HabiticaProfile(
    val username: String = "",
    val className: String = "",
    val level: Int = 0,
    val exp: Double = 0.0,
    val hp: Double = 0.0,
    val mp: Double = 0.0,
    val gp: Double = 0.0,
    val str: Int = 0,
    val con: Int = 0,
    val int: Int = 0,
    val per: Int = 0,
    val streak: Int = 0,
    val perfectDays: Int = 0,
    val questsTotal: Int = 0,
    val registeredAt: String = "",
    val lastLoginAt: String = "",
) {
    val maxHealth: Double = 50.0
    val maxMP: Double get() = 30 + 3 * (0.coerceAtLeast(level - 1)) + int / 2.0

    /** 当前等级所需总经验公式（与 Swift 端 Role 页一致），用于 EXP 进度条 */
    val expToNextLevel: Double get() = level * level * 0.25 + 10 * level + 139.75

    /** 升级进度 0..1 */
    val expProgress: Double get() =
        if (expToNextLevel <= 0) 0.0 else (exp / expToNextLevel).coerceIn(0.0, 1.0)
}

/** Never index the eight defaults with an arbitrary 1...24 block count. */
fun UserSettings.normalized(): UserSettings {
    val count = blockCount.coerceIn(1, 24)
    return copy(
        pomoDurationMins = pomoDurationMins.coerceIn(1, 120), breakDuration = breakDuration.coerceIn(1, 60),
        longBreakDuration = longBreakDuration.coerceIn(1, 120), breakExtention = breakExtention.coerceIn(0, 30),
        pomoSetNum = pomoSetNum.coerceIn(1, 12), blockCount = count, blockPomoCount = blockPomoCount.coerceIn(1, 12),
        blockReminderMinutes = blockReminderMinutes.coerceIn(1, 60),
        pomoEndSoundVolume = pomoEndSoundVolume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.5,
        breakEndSoundVolume = breakEndSoundVolume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.5,
        ambientSoundVolume = ambientSoundVolume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.5,
        blockGoals = List(maxOf(count, blockGoals.size)) { blockGoals.getOrElse(it) { "" } },
        blockTasks = List(maxOf(count, blockTasks.size)) { blockTasks.getOrElse(it) { emptyList() } },
        blockTimeRanges = List(maxOf(count, blockTimeRanges.size)) { i -> blockTimeRanges.getOrElse(i) {
            // Preserve existing configured ranges; a missing extra slot starts after the last range.
            val end = blockTimeRanges.lastOrNull()?.endMinutes ?: 240
            val start = (end + (i - blockTimeRanges.size) * 60).mod(1440)
            val finish = (start + 60).mod(1440)
            BlockTimeRange(start / 60, start % 60, finish / 60, finish % 60)
        } },
    )
}

data class DayHistogram(val pomodoros: Int = 0, val minutes: Int = 0, val weekday: String = "") {
    fun toJson() = JSONObject().apply { put("pomodoros", pomodoros); put("minutes", minutes); put("weekday", weekday) }
    companion object { fun fromJson(j: JSONObject) = DayHistogram(j.optInt("pomodoros").coerceAtLeast(0), j.optInt("minutes").coerceAtLeast(0), j.optString("weekday")) }
}

// MARK: - 栖时场景库（assets audio/qishi_presets.json；字段名与 Apple 端 QishiTrack/QishiPreset 逐字一致）

data class QishiTrack(
    val id: String,
    val file: String,
    /** 栖时调好的场景混音比例 0-100；播放增益 = volume/100 × 用户环境音量 */
    val volume: Int,
)

data class QishiPreset(
    val id: String,
    val name: String,
    val subtitle: String,
    val tracks: List<QishiTrack>,
)

object QishiLibrary {
    /** 音频不随包（152MB）；统一从栖时公开站点流式播放（与 Apple 端 streamBase 一致）。 */
    const val STREAM_BASE = "https://allen7wang.github.io/qishi-meditation-web/audio/"
    const val ASSET_PATH = "audio/qishi_presets.json"

    /** 宽松解析：跳过缺 id 或没有任何可播轨道的条目；音量夹到 0..100。 */
    fun parse(json: JSONObject): List<QishiPreset> =
        json.optJSONArray("presets")?.let { arr ->
            (0 until arr.length()).mapNotNull { i -> arr.optJSONObject(i)?.let(::presetFrom) }
        } ?: emptyList()

    private fun presetFrom(json: JSONObject): QishiPreset? {
        val id = json.optString("id", "")
        if (id.isBlank()) return null
        val tracks = json.optJSONArray("tracks")?.let { arr ->
            (0 until arr.length()).mapNotNull { i -> arr.optJSONObject(i)?.let(::trackFrom) }
        } ?: emptyList()
        if (tracks.isEmpty()) return null
        return QishiPreset(id, json.optString("name", ""), json.optString("subtitle", ""), tracks)
    }

    private fun trackFrom(json: JSONObject): QishiTrack? {
        val file = json.optString("file", "")
        if (file.isBlank()) return null
        return QishiTrack(json.optString("id", ""), file, json.optInt("volume", 100).coerceIn(0, 100))
    }

    /** 随机一个场景；候选多于一个时避开 excluding（不与上个番茄重复）。与 Apple QishiSceneStore.randomPreset 一致。 */
    fun randomPreset(library: List<QishiPreset>, excluding: String?): QishiPreset? {
        if (library.isEmpty()) return null
        val pool = if (excluding != null && library.size > 1) library.filterNot { it.id == excluding } else library
        return (if (pool.isEmpty()) library else pool).random()
    }
}

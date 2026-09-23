package com.habitica.pomodoro.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * 数据模型 —— 字段名与 macOS/iOS 端 Swift Codable 保持逐字一致，
 * 使 Habitica todo/tag 的语义与三端对齐（本地 JSON 在 Android 上不跨端同步）。
 */

// MARK: - 用户设置（对应 Swift UserSettings 的子集 + 番茄钟/块参数）

data class UserSettings(
    var uid: String = "",
    var apiToken: String = "",
    var connectHabitica: Boolean = true,
    var pomoDurationMins: Int = 25,
    var breakDuration: Int = 5,
    var longBreakDuration: Int = 30,
    var pomoSetNum: Int = 4,
    var manualBreak: Boolean = true,
    var pomoHabitPlus: Boolean = false,
    var pomoHabitMinus: Boolean = false,
    var pomoEndSound: String = "None",
    var pomoEndSoundVolume: Double = 0.5,
    // 时间块：仅用于逻辑日边界（Android 端不做 B1-B8 完整块模式）
    var enableBlockMode: Boolean = false,
    var blockTimeRanges: List<BlockTimeRange> = BlockTimeRange.defaults(),
) {
    fun toJson(): JSONObject = JSONObject().apply {
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
        put("blockTimeRanges", JSONArray().apply {
            blockTimeRanges.forEach { r -> put(r.toJson()) }
        })
    }

    companion object {
        fun fromJson(json: JSONObject): UserSettings = UserSettings(
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
            blockTimeRanges = json.optJSONArray("blockTimeRanges")?.let { arr ->
                (0 until arr.length()).map { BlockTimeRange.fromJson(arr.getJSONObject(it)) }
            } ?: BlockTimeRange.defaults(),
        )
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

    fun toJson(): JSONObject = JSONObject().apply {
        put("startHour", startHour)
        put("startMinute", startMinute)
        put("endHour", endHour)
        put("endMinute", endMinute)
    }

    companion object {
        fun fromJson(json: JSONObject) = BlockTimeRange(
            startHour = json.optInt("startHour", 0),
            startMinute = json.optInt("startMinute", 0),
            endHour = json.optInt("endHour", 0),
            endMinute = json.optInt("endMinute", 0),
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
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("isCompleted", isCompleted)
        habiticaTaskId?.let { put("habiticaTaskId", it) } ?: put("habiticaTaskId", JSONObject.NULL)
        put("movedToToday", movedToToday)
    }

    companion object {
        fun fromJson(json: JSONObject) = TopThreeTask(
            id = json.optString("id", UUID.randomUUID().toString().uppercase()),
            title = json.optString("title", ""),
            isCompleted = json.optBoolean("isCompleted", false),
            habiticaTaskId = if (json.isNull("habiticaTaskId")) null else json.optString("habiticaTaskId"),
            movedToToday = json.optBoolean("movedToToday", false),
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
) {
    fun toJson(): JSONObject = JSONObject().apply {
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

            return TopThreeStore(categoryNames = names, categoryTagIds = tagIds, history = history)
        }
    }
}

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
) {
    val maxHealth: Double = 50.0
    val maxMP: Double get() = 30 + 3 * (0.coerceAtLeast(level - 1)) + int / 2.0

    /** 当前等级所需总经验公式（与 Swift 端 Role 页一致），用于 EXP 进度条 */
    val expToNextLevel: Double get() = level * level * 0.25 + 10 * level + 139.75

    /** 升级进度 0..1 */
    val expProgress: Double get() =
        if (expToNextLevel <= 0) 0.0 else (exp % expToNextLevel / expToNextLevel).coerceIn(0.0, 1.0)
}

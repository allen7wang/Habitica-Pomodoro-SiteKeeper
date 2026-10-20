package com.habitica.pomodoro.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID

/** JSON shapes match the Swift Codable block files; all UI snapshots are immutable. */
data class BlockTask(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val title: String,
    val isCompleted: Boolean = false,
    val estimatedPomo: Int = 1,
) {
    fun toJson() = JSONObject().apply {
        put("id", id); put("title", title); put("isCompleted", isCompleted); put("estimatedPomo", estimatedPomo)
    }
    companion object {
        fun fromJson(j: JSONObject) = BlockTask(
            j.optString("id", UUID.randomUUID().toString().uppercase()), j.optString("title"),
            j.optBoolean("isCompleted"), j.optInt("estimatedPomo", 1),
        )
    }
}

data class BlockProgress(val currentBlockIndex: Int = 0, val blockPomoCounter: Int = 0) {
    fun toJson() = JSONObject().apply {
        put("currentBlockIndex", currentBlockIndex); put("blockPomoCounter", blockPomoCounter)
        put("blockStartTime", JSONObject.NULL)
    }
    companion object {
        fun fromJson(j: JSONObject) = BlockProgress(j.optInt("currentBlockIndex"), j.optInt("blockPomoCounter"))
    }
}

data class DailyBlockProgress(val date: String, val blockProgress: List<Int>, val blockGoals: List<String>) {
    fun toJson() = JSONObject().apply {
        put("date", date); put("blockProgress", JSONArray(blockProgress)); put("blockGoals", JSONArray(blockGoals))
    }
    companion object {
        fun fromJson(j: JSONObject): DailyBlockProgress {
            val a = j.optJSONArray("blockProgress") ?: JSONArray()
            val g = j.optJSONArray("blockGoals") ?: JSONArray()
            return DailyBlockProgress(j.optString("date"), (0 until a.length()).map { a.optInt(it) }, (0 until g.length()).map { g.optString(it) })
        }
    }
}

/** Swift's default Codable Date encoding is seconds since 2001-01-01T00:00:00Z. */
data class BlockHistoryEntry(val date: String, val blockIndex: Int, val pomodoros: Int, val isComplete: Boolean, val completedAt: Double?) {
    fun toJson() = JSONObject().apply {
        put("date", date); put("blockIndex", blockIndex); put("pomodoros", pomodoros)
        put("isComplete", isComplete); put("completedAt", completedAt ?: JSONObject.NULL)
    }
    companion object {
        fun fromJson(j: JSONObject): BlockHistoryEntry {
            val completedAt = when (val raw = j.opt("completedAt")) {
                is Number -> raw.toDouble()
                is String -> raw.toDoubleOrNull() ?: runCatching {
                    (java.time.Instant.parse(raw).toEpochMilli() - 978307200000L) / 1000.0
                }.getOrNull()
                else -> null
            }?.takeIf { it.isFinite() }
            return BlockHistoryEntry(j.optString("date"), j.optInt("blockIndex"), j.optInt("pomodoros"), j.optBoolean("isComplete"), completedAt)
        }
    }
}

data class PlantDay(val attempts: List<List<String>> = emptyList(), val trees: List<Int> = emptyList()) {
    fun toJson() = JSONObject().apply {
        put("attempts", JSONArray().apply { attempts.forEach { put(JSONArray(it)) } })
        put("trees", JSONArray(trees))
    }
    companion object {
        fun fromJson(j: JSONObject): PlantDay {
            val a = j.optJSONArray("attempts") ?: JSONArray()
            val t = j.optJSONArray("trees") ?: JSONArray()
            return PlantDay((0 until a.length()).map { i ->
                val inner = a.optJSONArray(i) ?: JSONArray()
                (0 until inner.length()).map { inner.optString(it) }.filter { it == "shrub" || it == "wilted" }
            }, (0 until t.length()).map { t.optInt(it) })
        }
    }
}

fun currentBlockIndex(settings: UserSettings, date: java.util.Date = java.util.Date()): Int? {
    val c = Calendar.getInstance().apply { time = date }
    val minute = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
    return (0 until settings.blockCount).firstOrNull { i -> settings.blockTimeRanges.getOrNull(i)?.contains(minute) == true }
}

/** Plant journal uses calendar days like the macOS PlantJournal, not TopThree's logical day. */
fun calendarDayKey(date: java.util.Date = java.util.Date()): String = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(date)

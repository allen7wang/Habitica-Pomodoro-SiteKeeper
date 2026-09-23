package com.habitica.pomodoro.data

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 本地 JSON 文件存储。
 *
 * 文件名与 macOS/iOS 端一致（habitica_pomodoro_*.json），便于将来接同步方案；
 * Android 端因平台限制无法访问 iCloud Drive，数据存于应用私有目录，
 * 任务与习惯经 Habitica 云端跨端一致。
 */
class LocalStore(context: Context) {

    private val dir: File = File(context.filesDir, FOLDER_NAME).apply {
        if (!exists()) mkdirs()
    }

    // MARK: - 设置

    fun loadSettings(): UserSettings =
        readJson(FILE_SETTINGS)?.let { UserSettings.fromJson(it) } ?: UserSettings()

    fun saveSettings(settings: UserSettings) =
        writeJson(FILE_SETTINGS, settings.toJson())

    // MARK: - Top Three / Task

    fun loadTopThree(): TopThreeStore =
        readJson(FILE_TOP_THREE)?.let { TopThreeStore.fromJson(it) } ?: TopThreeStore()

    fun saveTopThree(store: TopThreeStore) =
        writeJson(FILE_TOP_THREE, store.toJson())

    // MARK: - 今日番茄计数（对应 Swift 端 loadTodayCount / histogram）

    fun loadPomoCount(): Map<String, Int> =
        readJson(FILE_POMO_COUNT)?.let { obj ->
            val map = mutableMapOf<String, Int>()
            obj.keys().forEach { k -> map[k] = obj.optInt(k, 0) }
            map
        } ?: emptyMap()

    fun savePomoCount(counts: Map<String, Int>) {
        val obj = JSONObject()
        counts.forEach { (k, v) -> obj.put(k, v) }
        writeJson(FILE_POMO_COUNT, obj)
    }

    // MARK: - 逻辑日（与 Swift TopThreeManager.logicalDateKey 一致）

    /**
     * 一天的开始 = 第一个 time block 的启动时间（默认 04:00）。
     * 例如边界 04:00 时，凌晨 02:00 仍算"昨天"。
     */
    fun logicalDateKey(settings: UserSettings, date: Date = Date()): String {
        val boundaryMinutes = settings.blockTimeRanges.firstOrNull()?.startMinutes ?: 0
        val cal = Calendar.getInstance().apply { time = date }
        val minuteOfDay = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        if (minuteOfDay < boundaryMinutes) {
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        return DATE_FORMAT.format(cal.time)
    }

    fun yesterdayKey(settings: UserSettings): String {
        val cal = Calendar.getInstance()
        cal.time = DATE_FORMAT.parse(logicalDateKey(settings)) ?: Date()
        cal.add(Calendar.DAY_OF_YEAR, -1)
        return DATE_FORMAT.format(cal.time)
    }

    /** 只有"今天"（逻辑日）的任务可修改 */
    fun isEditable(key: String, settings: UserSettings): Boolean =
        key == logicalDateKey(settings)

    // MARK: - 底层读写

    private fun readJson(name: String): JSONObject? {
        val file = File(dir, name)
        if (!file.exists()) return null
        return runCatching { JSONObject(file.readText()) }.getOrNull()
    }

    private fun writeJson(name: String, json: JSONObject) {
        runCatching {
            val file = File(dir, name)
            file.parentFile?.takeIf { !it.exists() }?.mkdirs()
            file.writeText(json.toString())
        }.onFailure { e ->
            android.util.Log.e(TAG, "写入失败 $name: ${e.message}")
        }
    }

    /** 数据目录（设置页展示用） */
    fun dataDirectoryPath(): String = dir.absolutePath

    companion object {
        private const val TAG = "LocalStore"
        private const val FOLDER_NAME = ".habitica-pomodoro"
        private const val FILE_SETTINGS = "habitica_pomodoro_settings.json"
        private const val FILE_TOP_THREE = "habitica_pomodoro_top_three.json"
        private const val FILE_POMO_COUNT = "habitica_pomodoro_pomo_count.json"

        private val DATE_FORMAT = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    }
}

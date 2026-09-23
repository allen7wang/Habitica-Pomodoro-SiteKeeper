package com.habitica.pomodoro.engine

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.HabiticaProfile
import com.habitica.pomodoro.data.LocalStore
import com.habitica.pomodoro.data.TopThreeStore
import com.habitica.pomodoro.data.UserSettings
import com.habitica.pomodoro.service.PomodoroTimerService
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 番茄钟引擎 —— 业务规则与 Swift 端 PomodoroEngine 对齐。
 *
 * 关键设计：用**绝对结束时刻**（phaseEndsAt）而不是递减计数器驱动 UI。
 * Android 后台会冻结协程/计时，回到前台时按真实时间重算剩余秒数
 * （与 iOS 端 resyncAfterForeground 同一思路），保证计时不会因后台被"暂停"而走慢。
 */
class PomodoroViewModel(app: Application) : AndroidViewModel(app) {

    enum class Phase { IDLE, POMODORO, BREAK, LONG_BREAK, MANUAL_BREAK }

    data class UiState(
        val phase: Phase = Phase.IDLE,
        val isRunning: Boolean = false,
        val remainingSeconds: Int = 0,
        val totalSeconds: Int = 0,
        val pomoSetCounter: Int = 0,
        val todayPomodoros: Int = 0,
        val settings: UserSettings = UserSettings(),
        val profile: HabiticaProfile? = null,
        val profileLoading: Boolean = false,
        val profileError: String? = null,
        val store: TopThreeStore = TopThreeStore(),
        val message: String? = null,
        val habiticaBusy: Boolean = false,
    )

    private val store = LocalStore(app)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var tickJob: Job? = null
    /** 当前阶段的绝对结束时刻（epoch millis）；暂停时为 null */
    private var phaseEndsAt: Long = 0L
    /** 暂停时剩余秒数，用于恢复后重算 phaseEndsAt */
    private var pausedRemainingSeconds: Int = 0

    init {
        loadAll()
    }

    // MARK: - 加载

    private fun loadAll() {
        val settings = store.loadSettings()
        val topThree = store.loadTopThree()
        val todayKey = store.logicalDateKey(settings)
        val counts = store.loadPomoCount()
        _state.value = _state.value.copy(
            settings = settings,
            store = topThree,
            todayPomodoros = counts[todayKey] ?: 0,
        )
        refreshProfile()
    }

    // MARK: - 计时核心

    /** 主按钮 / 通知栏动作的统一入口（对应 Swift activate()） */
    fun activate() {
        val s = _state.value
        when {
            !s.isRunning && s.phase == Phase.MANUAL_BREAK -> startBreak()
            s.isRunning && s.phase == Phase.POMODORO -> pause()
            s.isRunning && (s.phase == Phase.BREAK || s.phase == Phase.LONG_BREAK) -> pause()
            !s.isRunning && s.phase == Phase.IDLE -> startPomodoro()
            !s.isRunning -> resume()
            else -> startPomodoro()
        }
    }

    fun startPomodoro() {
        val duration = _state.value.settings.pomoDurationMins * 60
        beginPhase(Phase.POMODORO, duration)
        PomodoroTimerService.start(getApplication(), Phase.POMODORO, phaseEndsAt)
    }

    private fun startBreak() {
        val s = _state.value
        val isLong = s.pomoSetCounter >= s.settings.pomoSetNum
        val duration = if (isLong) s.settings.longBreakDuration * 60 else s.settings.breakDuration * 60
        val phase = if (isLong) Phase.LONG_BREAK else Phase.BREAK
        beginPhase(phase, duration)
        PomodoroTimerService.start(getApplication(), phase, phaseEndsAt)
    }

    private fun beginPhase(phase: Phase, totalSeconds: Int) {
        tickJob?.cancel()
        phaseEndsAt = System.currentTimeMillis() + totalSeconds * 1000L
        pausedRemainingSeconds = 0
        _state.value = _state.value.copy(
            phase = phase,
            isRunning = true,
            totalSeconds = totalSeconds,
            remainingSeconds = totalSeconds,
            message = null,
        )
        startTicking()
    }

    fun pause() {
        if (!_state.value.isRunning) return
        pausedRemainingSeconds = remainingNow()
        phaseEndsAt = 0L
        tickJob?.cancel()
        _state.value = _state.value.copy(isRunning = false, remainingSeconds = pausedRemainingSeconds)
        PomodoroTimerService.updatePaused(getApplication(), pausedRemainingSeconds)
    }

    fun resume() {
        val s = _state.value
        if (s.isRunning || s.phase == Phase.IDLE) return
        phaseEndsAt = System.currentTimeMillis() + pausedRemainingSeconds * 1000L
        _state.value = s.copy(isRunning = true, remainingSeconds = pausedRemainingSeconds)
        startTicking()
        PomodoroTimerService.start(getApplication(), s.phase, phaseEndsAt)
    }

    /** 结束当前阶段（对应 Swift reset）：清空计时，不触发计分 */
    fun stop() {
        tickJob?.cancel()
        phaseEndsAt = 0L
        pausedRemainingSeconds = 0
        _state.value = _state.value.copy(
            phase = Phase.IDLE,
            isRunning = false,
            remainingSeconds = 0,
            totalSeconds = 0,
        )
        PomodoroTimerService.stop(getApplication())
    }

    /** 跳过当前休息，直接回到空闲 */
    fun skipBreak() {
        if (_state.value.phase == Phase.BREAK || _state.value.phase == Phase.LONG_BREAK) {
            stop()
        }
    }

    private fun remainingNow(): Int {
        if (phaseEndsAt <= 0L) return pausedRemainingSeconds
        val remaining = ((phaseEndsAt - System.currentTimeMillis()) / 1000L).toInt()
        return remaining.coerceAtLeast(0)
    }

    private fun startTicking() {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            while (true) {
                val remaining = remainingNow()
                _state.value = _state.value.copy(remainingSeconds = remaining)
                if (remaining <= 0) {
                    onPhaseEnd()
                    break
                }
                delay(500)
            }
        }
    }

    /**
     * 回前台重同步：后台期间协程被冻结，按绝对结束时刻重算。
     * 若后台期间阶段已结束，补触发结束逻辑（计分/进休息不会丢）。
     */
    fun resyncAfterForeground() {
        val s = _state.value
        if (phaseEndsAt <= 0L) return
        val remaining = remainingNow()
        _state.value = s.copy(remainingSeconds = remaining)
        if (remaining <= 0) onPhaseEnd()
        else if (!s.isRunning) {
            // 系统可能杀了 tick 协程，重启
            startTicking()
        }
    }

    // MARK: - 阶段结束

    private fun onPhaseEnd() {
        tickJob?.cancel()
        phaseEndsAt = 0L
        val s = _state.value
        when (s.phase) {
            Phase.POMODORO -> onPomodoroEnds()
            Phase.BREAK, Phase.LONG_BREAK -> onBreakEnds()
            else -> stop()
        }
    }

    private fun onPomodoroEnds() {
        val s = _state.value
        val settings = s.settings

        // 今日番茄计数 +1（与 Swift histogramManager.incrementToday 对应）
        val todayKey = store.logicalDateKey(settings)
        val counts = store.loadPomoCount().toMutableMap()
        counts[todayKey] = (counts[todayKey] ?: 0) + 1
        store.savePomoCount(counts)

        val newSetCounter = s.pomoSetCounter + 1
        val setComplete = s.pomoSetCounter >= settings.pomoSetNum - 1

        _state.value = s.copy(
            todayPomodoros = counts[todayKey] ?: 0,
            pomoSetCounter = if (setComplete) 0 else newSetCounter,
            phase = if (settings.manualBreak) Phase.MANUAL_BREAK else Phase.IDLE,
            isRunning = false,
            remainingSeconds = 0,
            message = if (setComplete) "一组番茄完成！🎉 今日已完成 ${counts[todayKey]} 个" else "番茄结束！今日已完成 ${counts[todayKey]} 个",
        )

        PomodoroTimerService.stop(getApplication())

        // Habitica 计分（pomoHabitPlus 开启时）
        if (settings.connectHabitica && settings.uid.isNotBlank() && settings.apiToken.isNotBlank()) {
            viewModelScope.launch {
                _state.value = _state.value.copy(habiticaBusy = true)
                scorePomodoroHabit(settings, setComplete)
                _state.value = _state.value.copy(habiticaBusy = false)
            }
        }

        // 手动休息模式下不自动开始休息，等待用户点击
        if (!settings.manualBreak) {
            startBreak()
        }
    }

    /** 对应 Swift pomodoroEnds() 里的 scoreHabit(up) 分支 */
    private suspend fun scorePomodoroHabit(settings: UserSettings, setComplete: Boolean) {
        val habitId = PomodoroTimerService.habitTaskId
        if (habitId.isNullOrBlank()) return
        val result = HabiticaAPI.scoreTask(settings, habitId, "up")
        if (result is HabiticaAPI.Result.Error) {
            _state.value = _state.value.copy(message = result.message)
        }
        refreshProfile()
    }

    private fun onBreakEnds() {
        _state.value = _state.value.copy(
            phase = Phase.IDLE,
            isRunning = false,
            remainingSeconds = 0,
            message = "休息结束，开始下一个番茄吧",
        )
        PomodoroTimerService.stop(getApplication())
    }

    // MARK: - Habitica：Role 页

    fun refreshProfile() {
        val settings = _state.value.settings
        if (!settings.connectHabitica || settings.uid.isBlank() || settings.apiToken.isBlank()) {
            _state.value = _state.value.copy(
                profile = null,
                profileError = "未连接 Habitica：请在设置中填写 User ID 与 API Token",
            )
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(profileLoading = true, profileError = null)
            when (val result = HabiticaAPI.fetchProfile(settings)) {
                is HabiticaAPI.Result.Success -> _state.value = _state.value.copy(
                    profile = result.value,
                    profileLoading = false,
                    profileError = null,
                )
                is HabiticaAPI.Result.Error -> _state.value = _state.value.copy(
                    profileLoading = false,
                    profileError = result.message,
                )
            }
        }
    }

    // MARK: - 设置

    fun updateSettings(transform: (UserSettings) -> Unit) {
        val settings = _state.value.settings.copy()
        transform(settings)
        store.saveSettings(settings)
        _state.value = _state.value.copy(settings = settings)
        refreshProfile()
    }

    fun clearMessage() {
        _state.value = _state.value.copy(message = null)
    }

    // MARK: - Task（Top Three）

    fun addTask(categoryIndex: Int, title: String) {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return
        val settings = _state.value.settings
        val s = _state.value.store
        // Work/MyOwn（前 2 个分类）上限 3 条；其余（Chores）自由列表
        val limit = if (categoryIndex < FIXED_SLOT_CATEGORIES) MAX_FIXED_TASKS else Int.MAX_VALUE

        val todayKey = store.logicalDateKey(settings)
        val day = s.history[todayKey] ?: newDay(todayKey, s.categoryNames.size)
        val groups = day.taskGroups.toMutableList()
        while (groups.size <= categoryIndex) groups.add(emptyList())
        val group = groups[categoryIndex].toMutableList()
        if (group.size >= limit) {
            _state.value = _state.value.copy(message = "该分类最多 $limit 条任务")
            return
        }
        val newTask = com.habitica.pomodoro.data.TopThreeTask(title = trimmed)
        group.add(newTask)
        groups[categoryIndex] = group
        val newStore = s.copy(history = s.history + (todayKey to day.copy(taskGroups = groups)))
        persistStore(newStore)
        syncTaskToHabitica(categoryIndex, newTask)
    }

    private fun newDay(date: String, categoryCount: Int) =
        com.habitica.pomodoro.data.TopThreeDay(
            date = date,
            taskGroups = List(categoryCount) { emptyList() },
        )

    fun toggleTask(categoryIndex: Int, taskIndex: Int) {
        val s = _state.value.store
        val settings = _state.value.settings
        val todayKey = store.logicalDateKey(settings)
        val day = s.history[todayKey] ?: return
        val task = day.taskGroups.getOrNull(categoryIndex)?.getOrNull(taskIndex) ?: return
        val newCompleted = !task.isCompleted
        val newGroups = day.taskGroups.mapIndexed { gi, g ->
            if (gi == categoryIndex) g.mapIndexed { ti, t ->
                if (ti == taskIndex) t.copy(isCompleted = newCompleted) else t
            } else g
        }
        val newStore = s.copy(history = s.history + (todayKey to day.copy(taskGroups = newGroups)))
        persistStore(newStore)
        // 完成 → score up；取消完成 → score down（与 Swift 端一致）
        task.habiticaTaskId?.let { id ->
            viewModelScope.launch {
                HabiticaAPI.scoreTask(settings, id, if (newCompleted) "up" else "down")
                refreshProfile()
            }
        }
    }

    fun deleteTask(categoryIndex: Int, taskIndex: Int) {
        val s = _state.value.store
        val settings = _state.value.settings
        val todayKey = store.logicalDateKey(settings)
        val day = s.history[todayKey] ?: return
        val task = day.taskGroups.getOrNull(categoryIndex)?.getOrNull(taskIndex) ?: return
        val newGroups = day.taskGroups.mapIndexed { gi, g ->
            if (gi == categoryIndex) g.filterIndexed { ti, _ -> ti != taskIndex } else g
        }
        val newStore = s.copy(history = s.history + (todayKey to day.copy(taskGroups = newGroups)))
        persistStore(newStore)
        task.habiticaTaskId?.let { id ->
            viewModelScope.launch { HabiticaAPI.deleteTodo(settings, id) }
        }
    }

    /** 昨天未完成的任务移动到今天（对应 Swift moveTaskToToday） */
    fun moveTaskToToday(categoryIndex: Int, taskIndex: Int) {
        val s = _state.value.store
        val settings = _state.value.settings
        val yesterdayKey = store.yesterdayKey(settings)
        val todayKey = store.logicalDateKey(settings)
        val yesterday = s.history[yesterdayKey] ?: return
        val task = yesterday.taskGroups.getOrNull(categoryIndex)?.getOrNull(taskIndex) ?: return
        if (task.isCompleted || task.movedToToday) return

        val limit = if (categoryIndex < FIXED_SLOT_CATEGORIES) MAX_FIXED_TASKS else Int.MAX_VALUE
        val today = s.history[todayKey] ?: newDay(todayKey, s.categoryNames.size)
        val tGroups = today.taskGroups.toMutableList()
        while (tGroups.size <= categoryIndex) tGroups.add(emptyList())
        val tGroup = tGroups[categoryIndex].toMutableList()
        if (tGroup.size >= limit) {
            _state.value = _state.value.copy(message = "今天的该分类已满 $limit 条")
            return
        }
        tGroup.add(task.copy(movedToToday = false))
        tGroups[categoryIndex] = tGroup

        // 标记原任务已移动
        val yGroups = yesterday.taskGroups.mapIndexed { gi, g ->
            if (gi == categoryIndex) g.mapIndexed { ti, t ->
                if (ti == taskIndex) t.copy(movedToToday = true) else t
            } else g
        }
        val newStore = s.copy(
            history = s.history +
                (yesterdayKey to yesterday.copy(taskGroups = yGroups)) +
                (todayKey to today.copy(taskGroups = tGroups)),
        )
        persistStore(newStore)
    }

    fun renameCategory(index: Int, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        val s = _state.value.store
        val oldName = s.categoryNames.getOrNull(index) ?: return
        if (oldName == trimmed) return
        val newNames = s.categoryNames.mapIndexed { i, n -> if (i == index) trimmed else n }
        val newTagIds = s.categoryTagIds.toMutableMap()
        val tagId = newTagIds.remove(oldName)
        if (tagId != null) newTagIds[trimmed] = tagId
        persistStore(s.copy(categoryNames = newNames, categoryTagIds = newTagIds))
        // tag 映射跟随改名；已有 tag 同步重命名
        if (tagId != null) {
            val settings = _state.value.settings
            viewModelScope.launch { HabiticaAPI.updateTag(settings, tagId, trimmed) }
        }
    }

    private fun persistStore(s: TopThreeStore) {
        store.saveTopThree(s)
        _state.value = _state.value.copy(store = s)
    }

    /** 新增任务同步为 Habitica todo，分类名作为 tag（与 Swift 端一致） */
    private fun syncTaskToHabitica(categoryIndex: Int, task: com.habitica.pomodoro.data.TopThreeTask) {
        val settings = _state.value.settings
        if (!settings.connectHabitica || settings.uid.isBlank() || settings.apiToken.isBlank()) return
        val categoryName = _state.value.store.categoryNames.getOrNull(categoryIndex) ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(habiticaBusy = true)
            val tagResult = HabiticaAPI.ensureTag(settings, categoryName)
            val tagIds = when (tagResult) {
                is HabiticaAPI.Result.Success -> listOfNotNull(tagResult.value)
                is HabiticaAPI.Result.Error -> emptyList()
            }
            val created = HabiticaAPI.createTodo(
                settings = settings,
                text = task.title,
                notes = "From Habitica Pomodoro · $categoryName",
                tagIds = tagIds,
            )
            if (created is HabiticaAPI.Result.Success) {
                val id = created.value
                if (id != null) {
                    // 回写 habiticaTaskId（不可变链：构造新 store），保证后续完成/删除能同步
                    val s = _state.value.store
                    val todayKey = store.logicalDateKey(settings)
                    val day = s.history[todayKey]
                    if (day != null) {
                        val newGroups = day.taskGroups.mapIndexed { gi, g ->
                            if (gi == categoryIndex) g.map { t ->
                                if (t.id == task.id) t.copy(habiticaTaskId = id) else t
                            } else g
                        }
                        var newTagIds = s.categoryTagIds
                        if (tagResult is HabiticaAPI.Result.Success) {
                            tagResult.value?.let { tid ->
                                newTagIds = newTagIds + (categoryName to tid)
                            }
                        }
                        persistStore(
                            s.copy(
                                history = s.history + (todayKey to day.copy(taskGroups = newGroups)),
                                categoryTagIds = newTagIds,
                            ),
                        )
                    }
                }
            }
            _state.value = _state.value.copy(habiticaBusy = false)
        }
    }

    fun todayKey(): String = store.logicalDateKey(_state.value.settings)
    fun yesterdayKey(): String = store.yesterdayKey(_state.value.settings)
    fun isEditable(key: String): Boolean = store.isEditable(key, _state.value.settings)
    fun dataDirectoryPath(): String = store.dataDirectoryPath()

    companion object {
        /** 前 2 个分类（Work/MyOwn）固定槽位，与 Swift TopThreeManager.fixedSlotCategories 一致 */
        private const val FIXED_SLOT_CATEGORIES = 2
        private const val MAX_FIXED_TASKS = 3
    }
}

package com.habitica.pomodoro.engine

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.HabiticaProfile
import com.habitica.pomodoro.data.LocalStore
import com.habitica.pomodoro.data.BlockHistoryEntry
import com.habitica.pomodoro.data.BlockProgress
import com.habitica.pomodoro.data.BlockTask
import com.habitica.pomodoro.data.DailyBlockProgress
import com.habitica.pomodoro.data.PlantDay
import com.habitica.pomodoro.data.QishiLibrary
import com.habitica.pomodoro.data.QishiPreset
import com.habitica.pomodoro.data.HabiticaTaskItem
import com.habitica.pomodoro.data.calendarDayKey
import com.habitica.pomodoro.data.currentBlockIndex
import com.habitica.pomodoro.data.TopThreeStore
import com.habitica.pomodoro.data.mergeTopThreeTodos
import com.habitica.pomodoro.data.pendingCreateCandidates
import com.habitica.pomodoro.data.remoteIdOccupied
import com.habitica.pomodoro.data.quarantinesDeletedCreation
import com.habitica.pomodoro.data.parseTopThreeNotes
import com.habitica.pomodoro.data.topThreeNotes
import com.habitica.pomodoro.data.UserSettings
import com.habitica.pomodoro.data.normalized
import com.habitica.pomodoro.data.cloudAccount
import com.habitica.pomodoro.data.isValidHabiticaUid
import com.habitica.pomodoro.data.TimerBusinessSnapshot
import com.habitica.pomodoro.service.PomodoroTimerService
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * 番茄钟引擎 —— 业务规则与 Swift 端 PomodoroEngine 对齐。
 *
 * 关键设计：用**绝对结束时刻**（phaseEndsAt）而不是递减计数器驱动 UI。
 * Android 后台会冻结协程/计时，回到前台时按真实时间重算剩余秒数
 * （与 iOS 端 resyncAfterForeground 同一思路），保证计时不会因后台被"暂停"而走慢。
 */
class PomodoroViewModel(app: Application) : AndroidViewModel(app) {

    enum class Phase { IDLE, POMODORO, BREAK, LONG_BREAK, BREAK_EXTENSION, MANUAL_BREAK }

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
        val blockProgress: BlockProgress = BlockProgress(),
        val dailyBlocks: Map<String, DailyBlockProgress> = emptyMap(),
        val blockHistory: Map<String, List<BlockHistoryEntry>> = emptyMap(),
        val plants: Map<String, PlantDay> = emptyMap(),
        val pomoCounts: Map<String, Int> = emptyMap(),
        val histogram: Map<String, com.habitica.pomodoro.data.DayHistogram> = emptyMap(),
        val habits: List<HabiticaTaskItem> = emptyList(),
        val dailies: List<HabiticaTaskItem> = emptyList(),
        val tasksLoading: Boolean = false,
        val tasksError: String? = null,
        val topThreeSyncing: Boolean = false,
        val topThreeSyncError: String? = null,
        // FIX2(D2): non-null while a local store save is failing; the in-memory
        // state still advances, but the user must see that persistence failed.
        val persistenceError: String? = null,
        val scoringIds: Set<String> = emptySet(),
        /** 当前番茄激活的栖时场景（ambientSource=="qishi"）。专注开始时随机选出；
         *  暂停/回前台延续同一场景；每个环境音停止点清空。播放由前台服务的 refreshAudio 消费。 */
        val qishiScene: QishiPreset? = null,
    )

    private val store = LocalStore(app)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var tickJob: Job? = null
    /** 当前阶段的绝对结束时刻（epoch millis）；暂停时为 null */
    private var phaseEndsAt: Long = 0L
    /** 暂停时剩余秒数，用于恢复后重算 phaseEndsAt */
    private var pausedRemainingSeconds: Int = 0
    /** An old notification must never control a newer phase. */
    private var timerSessionId: String? = null
    private var serviceAttachAllowed = false
    private var customBreak = false
    private var completedSet = false
    private var phaseSnapshot: TimerBusinessSnapshot? = null
    private var processingDeadline = false
    private var accountGeneration = 0
    private var profileJob: Job? = null
    private var tasksJob: Job? = null
    private var tasksGeneration = 0
    private var topThreeSyncJob: Job? = null
    private var topThreeSyncGeneration = 0

    /** 场景库加载注入点：设备上由 PomoApplication 注入 assets 读取实现；fixtures 注入仓库文件读取。
     *  未注入或读取失败 → 空库（选择结果为 null，走"场景库不可用"提示）。 */
    var qishiLibraryLoader: (() -> List<QishiPreset>)? = null
    private var qishiLibraryCache: List<QishiPreset>? = null
    /** 跨番茄记忆：新番茄随机场景时避开上一个（激活场景清空后仍保留，与 Apple lastQishiSceneId 一致） */
    private var lastQishiSceneId: String? = null

    private fun isCurrentAccount(settings: UserSettings, generation: Int): Boolean {
        val now = _state.value.settings
        return generation == accountGeneration && now.uid == settings.uid &&
            now.apiToken == settings.apiToken && now.connectHabitica == settings.connectHabitica && now.developerServerUrl == settings.developerServerUrl
    }

    private val habitMutex = kotlinx.coroutines.sync.Mutex()
    private val taskMutex = kotlinx.coroutines.sync.Mutex()
    private var creatingTasks = 0
    private var localRevision = 0
    private val creationIds = mutableSetOf<String>()

    init {
        loadAll()
    }

    // MARK: - 加载

    private fun loadAll() {
        val settings = store.loadSettings()
        val topThree = store.loadTopThree().forAccount(settings.cloudAccount())
        val topThreeSaved = store.saveTopThree(topThree)
        val todayKey = calendarDayKey()
        val counts = store.loadPomoCount()
        _state.value = _state.value.copy(
            settings = settings,
            store = topThree,
            todayPomodoros = counts[todayKey] ?: 0,
            pomoCounts = counts,
            histogram = store.loadHistogram(),
            blockProgress = store.loadBlockProgress(),
            dailyBlocks = store.loadDailyBlocks(),
            blockHistory = store.loadBlockHistory(),
            plants = store.loadPlants(),
            persistenceError = if (topThreeSaved) null else TOP_THREE_PERSIST_FAILED,
        )
        refreshDay()
        restoreTimer()
        refreshProfile()
        refreshTopThreeFromCloud()
        ensureDefaultHabits()
        com.habitica.pomodoro.service.BlockReminderReceiver.schedule(getApplication(), settings)
    }

    // MARK: - 计时核心

    /** Main control pauses rather than abandoning; resets are explicit actions. */
    fun activate() {
        resyncTimer()
        val s = _state.value
        when {
            s.phase == Phase.MANUAL_BREAK -> startBreak()
            s.phase == Phase.BREAK_EXTENSION && !s.isRunning && s.remainingSeconds == 0 -> startPomodoro()
            s.isRunning -> pause()
            s.phase == Phase.IDLE -> startPomodoro()
            else -> resume()
        }
    }

    fun startPomodoro() {
        val s = _state.value
        if (s.phase == Phase.POMODORO) return
        customBreak = false
        if (completedSet) _state.value = s.copy(pomoSetCounter = 0)
        completedSet = false
        phaseSnapshot = TimerBusinessSnapshot.capture(s.settings)
        beginPhase(Phase.POMODORO, s.settings.pomoDurationMins * 60)
        // 栖时模式：每个番茄开始时随机选一个新场景（避开上个番茄）。放在 beginPhase 之后，
        // 因为 beginPhase 会清空 message，"场景库不可用"提示必须随后写入状态。
        selectQishiScene(s.settings)
    }

    private fun startBreak(startingAt: Long = System.currentTimeMillis()) {
        val settings = phaseSnapshot?.settings ?: _state.value.settings
        beginPhase(if (completedSet) Phase.LONG_BREAK else Phase.BREAK,
            (if (completedSet) settings.longBreakDuration else settings.breakDuration) * 60, startingAt)
    }

    fun takeBreak(minutes: Int) {
        resyncTimer()
        if (minutes !in listOf(1, 5, 15, 30)) return
        if (_state.value.phase != Phase.IDLE || _state.value.isRunning) return
        customBreak = true
        phaseSnapshot = TimerBusinessSnapshot.capture(_state.value.settings)
        beginPhase(Phase.LONG_BREAK, minutes * 60) // Independent custom break; never fabricate a completed set.
    }

    fun skipToBreak() {
        resyncTimer()
        if (_state.value.phase != Phase.POMODORO) return
        val settings = phaseSnapshot?.settings ?: _state.value.settings
        if (settings.enableBlockMode) recordPlant("wilted", false, settings)
        _state.value = _state.value.copy(pomoSetCounter = 0)
        completedSet = false
        startBreak() // No completion and no Habitica penalty for skip.
    }

    private fun beginPhase(phase: Phase, seconds: Int, startingAt: Long = System.currentTimeMillis()) {
        tickJob?.cancel()
        timerSessionId = UUID.randomUUID().toString()
        phaseEndsAt = startingAt + seconds * 1000L
        pausedRemainingSeconds = 0
        _state.value = _state.value.copy(phase = phase, isRunning = true, totalSeconds = seconds,
            remainingSeconds = seconds, message = null,
            // 进入非专注阶段（休息/延长）即清空激活场景；POMODORO 由紧随其后的选择逻辑写入
            qishiScene = if (phase == Phase.POMODORO) _state.value.qishiScene else null)
        persistTimer()
        if (!processingDeadline) { syncTimerService(); startTicking() }
    }

    fun pause() {
        if (!_state.value.isRunning) return
        if (remainingNow() <= 0) { onPhaseEnd(); return }
        pausedRemainingSeconds = remainingNow()
        phaseEndsAt = 0L
        tickJob?.cancel()
        timerSessionId = UUID.randomUUID().toString() // Invalidate the old notification controls.
        _state.value = _state.value.copy(isRunning = false, remainingSeconds = pausedRemainingSeconds)
        persistTimer()
        PomodoroTimerService.updatePaused(getApplication(), pausedRemainingSeconds, timerSessionId!!)
    }

    fun resume() {
        val s = _state.value
        if (s.isRunning || s.phase == Phase.IDLE || s.phase == Phase.MANUAL_BREAK) return
        if (pausedRemainingSeconds <= 0) { startPomodoro(); return }
        timerSessionId = UUID.randomUUID().toString()
        phaseEndsAt = System.currentTimeMillis() + pausedRemainingSeconds * 1000L
        _state.value = s.copy(isRunning = true, remainingSeconds = pausedRemainingSeconds)
        persistTimer()
        syncTimerService()
        startTicking()
    }

    fun handleNotificationAction(action: String?, sessionId: String?) {
        resyncTimer()
        if (sessionId == null || sessionId != timerSessionId) return
        when (action) {
            PomodoroTimerService.ACTION_PAUSE -> pause()
            PomodoroTimerService.ACTION_RESUME -> resume()
            PomodoroTimerService.ACTION_STOP -> stop()
        }
    }

    fun isCurrentTimer(id: String): Boolean = id.isNotBlank() && id == timerSessionId

    fun onServiceDeadline(sessionId: String) {
        if (sessionId == timerSessionId && _state.value.isRunning && remainingNow() <= 0) onPhaseEnd()
    }

    /** Explicit abandon resets the combo; pause and skip never score a failure. */
    fun stop() {
        if (_state.value.isRunning && phaseEndsAt > 0 && remainingNow() <= 0) { onPhaseEnd(); return }
        val s = _state.value
        val interrupted = s.phase == Phase.POMODORO
        val snapshot = phaseSnapshot
        val settings = snapshot?.settings ?: s.settings
        if (interrupted && settings.enableBlockMode) recordPlant("wilted", false, settings)
        resetTimer(resetCombo = true)
        if (interrupted && settings.pomoHabitMinus) snapshot?.withCurrentCredentials(_state.value.settings)?.let { scoreFailure(it, captured = true) }
    }

    private fun resetTimer(resetCombo: Boolean) {
        tickJob?.cancel(); phaseEndsAt = 0; pausedRemainingSeconds = 0; timerSessionId = null
        customBreak = false
        phaseSnapshot = null
        if (resetCombo) completedSet = false
        _state.value = _state.value.copy(phase = Phase.IDLE, isRunning = false, remainingSeconds = 0,
            totalSeconds = 0, pomoSetCounter = if (resetCombo) 0 else _state.value.pomoSetCounter,
            qishiScene = null)
        persistTimer()
        PomodoroTimerService.stop(getApplication())
    }

    fun skipBreak() {
        resyncTimer()
        val s = _state.value
        if (s.phase !in listOf(Phase.BREAK, Phase.LONG_BREAK, Phase.BREAK_EXTENSION, Phase.MANUAL_BREAK)) return
        resetTimer(!customBreak && completedSet)
        startPomodoro()
    }

    private fun remainingNow(): Int = if (phaseEndsAt <= 0) pausedRemainingSeconds else
        ((phaseEndsAt - System.currentTimeMillis() + 999) / 1000L).toInt().coerceAtLeast(0)

    private fun startTicking() {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            while (true) {
                val remaining = remainingNow()
                _state.value = _state.value.copy(remainingSeconds = remaining)
                if (remaining <= 0) { onPhaseEnd(); break }
                delay(500)
            }
        }
    }

    fun resyncAfterForeground() {
        refreshDay(); refreshTopThreeFromCloud(); resyncTimer(); refreshDay()
        // 进程恢复后正在运行的专注可能丢失了内存中的场景：补选一次；已有场景绝不重随机。
        ensureQishiSceneForRunningFocus()
        com.habitica.pomodoro.service.BlockReminderReceiver.schedule(getApplication(), _state.value.settings)
    }
    private fun resyncTimer() {
        if (phaseEndsAt <= 0 || processingDeadline) return
        processingDeadline = true
        try {
            // At most focus -> break -> grace. Never create an unattended focus during restoration.
            repeat(6) {
                if (!_state.value.isRunning || phaseEndsAt <= 0 || remainingNow() > 0) return@repeat
                val deadline = phaseEndsAt
                tickJob?.cancel(); phaseEndsAt = 0; pausedRemainingSeconds = 0; timerSessionId = null
                when (_state.value.phase) {
                    Phase.POMODORO -> onPomodoroEnds(deadline)
                    Phase.BREAK, Phase.LONG_BREAK -> onBreakEnds(deadline)
                    Phase.BREAK_EXTENSION -> onExtensionEnds()
                    else -> resetTimer(false)
                }
            }
        } finally { processingDeadline = false }
        _state.value = _state.value.copy(remainingSeconds = remainingNow())
        if (_state.value.isRunning && phaseEndsAt > 0) {
            syncTimerService()
            if (tickJob?.isActive != true) startTicking()
        }
    }

    private fun persistTimer() {
        val s = _state.value
        store.saveTimer(org.json.JSONObject().apply {
            put("phase", s.phase.name); put("phaseID", timerSessionId ?: org.json.JSONObject.NULL)
            put("endsAt", phaseEndsAt); put("pausedRemaining", pausedRemainingSeconds)
            put("totalSeconds", s.totalSeconds); put("combo", s.pomoSetCounter); put("running", s.isRunning)
            put("customBreak", customBreak); put("completedSet", completedSet)
            put("phaseSnapshot", phaseSnapshot?.toJson() ?: org.json.JSONObject.NULL)
        })
    }
    private fun restoreTimer() {
        val json = store.loadTimer() ?: return
        val phase = runCatching { Phase.valueOf(json.optString("phase")) }.getOrDefault(Phase.IDLE)
        timerSessionId = json.optString("phaseID").takeIf { it.isNotBlank() && it != "null" }
        customBreak = json.optBoolean("customBreak", false)
        completedSet = json.optBoolean("completedSet", json.optInt("combo") >= _state.value.settings.pomoSetNum)
        // Old snapshots had no captured settings. Preserve their known duration; never invent an owner for scoring.
        phaseSnapshot = json.optJSONObject("phaseSnapshot")?.let(TimerBusinessSnapshot::fromJson)
            ?: if (phase != Phase.IDLE) TimerBusinessSnapshot.capture(_state.value.settings).copy(cloudAccount = null) else null
        phaseEndsAt = json.optLong("endsAt"); pausedRemainingSeconds = json.optInt("pausedRemaining").coerceAtLeast(0)
        _state.value = _state.value.copy(phase = phase, isRunning = json.optBoolean("running") && phaseEndsAt > 0,
            totalSeconds = json.optInt("totalSeconds").coerceAtLeast(0), remainingSeconds = remainingNow(),
            pomoSetCounter = json.optInt("combo").coerceAtLeast(0))
        // No background FGS launch in Application/boot receivers. Activity resume attaches it.
        resyncTimer()
    }
    fun attachTimerService() {
        serviceAttachAllowed = true // Only the resumed Activity may initiate a first FGS.
        resyncTimer()
        syncTimerService()
    }
    private fun syncTimerService() {
        if (!serviceAttachAllowed || !_state.value.isRunning || phaseEndsAt <= 0 || timerSessionId == null) return
        if (!PomodoroTimerService.start(getApplication(), _state.value.phase, phaseEndsAt, timerSessionId!!))
            _state.value = _state.value.copy(message = "系统未允许启动前台计时服务；当前只能保证前台计时，请重新打开应用")
    }

    private fun onPhaseEnd() { resyncTimer() }

    private fun onPomodoroEnds(deadline: Long) {
        val before = _state.value
        val snapshot = phaseSnapshot ?: TimerBusinessSnapshot.capture(before.settings).copy(cloudAccount = null)
        val settings = snapshot.settings
        val date = java.util.Date(deadline)
        val day = calendarDayKey(date)
        val old = before.histogram[day] ?: com.habitica.pomodoro.data.DayHistogram()
        // Duration is the completed phase snapshot, NOT the setting at completion.
        val histogram = before.histogram + (day to old.copy(pomodoros = old.pomodoros + 1,
            minutes = old.minutes + before.totalSeconds / 60,
            weekday = java.text.SimpleDateFormat("EEEE", java.util.Locale.getDefault()).format(date)))
        store.saveHistogram(histogram)
        val combo = before.pomoSetCounter + 1
        val setComplete = combo >= settings.pomoSetNum
        completedSet = setComplete
        if (settings.enableBlockMode) recordPlant("shrub", setComplete, settings, date)
        val s = _state.value
        val index = s.blockProgress.currentBlockIndex
        val blockComplete = settings.enableBlockMode &&
            s.blockHistory[day].orEmpty().any { it.blockIndex == index && it.isComplete } &&
            before.blockHistory[day].orEmpty().none { it.blockIndex == index && it.isComplete }
        val message = if (blockComplete) "时间块 B${index + 1} 完成！🎉\n${settings.blockGoals.getOrNull(index).orEmpty()}\n${breakSuggestion(index, settings, date)}"
            else if (setComplete) "一组番茄完成！🎉" else "番茄完成！"
        _state.value = s.copy(histogram = histogram, pomoCounts = histogram.mapValues { it.value.pomodoros },
            todayPomodoros = histogram[calendarDayKey()]?.pomodoros ?: 0, pomoSetCounter = combo,
            phase = if (settings.manualBreak) Phase.MANUAL_BREAK else Phase.IDLE, isRunning = false,
            remainingSeconds = 0, totalSeconds = 0, message = message, qishiScene = null)
        persistTimer()
        PomodoroTimerService.endSignal(getApplication(), if (setComplete) "一组番茄完成" else "番茄结束", message,
            settings.pomoEndSound, settings.pomoEndSoundVolume)
        PomodoroTimerService.stop(getApplication())
        snapshot.withCurrentCredentials(_state.value.settings)?.let { scoringSettings ->
            val generation = accountGeneration
            viewModelScope.launch { scorePomodoroHabit(scoringSettings, setComplete, blockComplete, generation) }
        }
        if (!settings.manualBreak) startBreak(deadline)
    }

    private suspend fun scorePomodoroHabit(settings: UserSettings, setComplete: Boolean, blockComplete: Boolean, generation: Int) {
        val needsPomo = settings.pomoHabitPlus || (blockComplete && settings.blockRewardEnabled)
        if (!needsPomo && !(setComplete && settings.pomoSetHabitPlus)) return
        val pomo = if (needsPomo) resolveHabit(settings, false, generation, captured = true) else null
        val combo = if (setComplete && settings.pomoSetHabitPlus) resolveHabit(settings, true, generation, captured = true) else null
        val ids = buildList {
            if (settings.pomoHabitPlus) pomo?.let(::add)
            if (setComplete && settings.pomoSetHabitPlus) combo?.let(::add)
            // The block reward is separate from the regular completion reward, like macOS.
            if (blockComplete && settings.blockRewardEnabled) pomo?.let(::add)
        }
        for (id in ids) {
            if (!isCurrentAccount(settings, generation)) return
            val result = HabiticaAPI.scoreTask(settings, id, "up")
            if (!isCurrentAccount(settings, generation)) return
            if (result is HabiticaAPI.Result.Error) _state.value = _state.value.copy(message = result.message + "；本机完成记录已保留，未自动重试以免重复奖励")
        }
        if (isCurrentAccount(settings, generation)) refreshProfile()
    }

    private fun scoreFailure(settings: UserSettings, captured: Boolean = false) {
        val generation = accountGeneration
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        viewModelScope.launch {
            val id = resolveHabit(settings, false, generation, captured) ?: return@launch
            if (!isCurrentAccount(settings, generation)) return@launch
            val result = HabiticaAPI.scoreTask(settings, id, "down")
            if (!isCurrentAccount(settings, generation)) return@launch
            if (result is HabiticaAPI.Result.Error) _state.value = _state.value.copy(message = result.message)
            else refreshProfile()
        }
    }

    private fun onBreakEnds(deadline: Long) {
        val s = _state.value
        val snapshot = phaseSnapshot
        val settings = snapshot?.settings ?: s.settings
        val long = s.phase == Phase.LONG_BREAK
        val message = if (long) "长休息结束" else "短休息结束，回到专注"
        resetTimer(long && !customBreak)
        _state.value = _state.value.copy(message = message)
        PomodoroTimerService.endSignal(getApplication(), message, "开始下一个番茄吧", settings.breakEndSound, settings.breakEndSoundVolume)
        snapshot?.withCurrentCredentials(_state.value.settings)?.let {
            sendBreakMessage(it, if (long) settings.longBreakNotify else settings.breakExtentionNotify && settings.breakExtention > 0,
                if (long) "Long Break is over" else "Back to work! ${settings.breakExtention} minutes left for Break Extension.")
        }
        if (!long && settings.breakExtention > 0) {
            phaseSnapshot = snapshot
            beginPhase(Phase.BREAK_EXTENSION, settings.breakExtention * 60, deadline)
        }
        // Zero extension ends the break directly: no timeout, penalty, or combo reset.
    }

    private fun onExtensionEnds() {
        val snapshot = phaseSnapshot
        val settings = snapshot?.settings ?: _state.value.settings
        resetTimer(settings.resetPomoAfterBreak)
        _state.value = _state.value.copy(message = if (settings.resetPomoAfterBreak) "休息延长结束，本组已重置" else "休息延长结束，连击保留，开始专注吧")
        // Zero extension is a grace-free transition, not a spurious interruption penalty.
        if (settings.breakExtention > 0 && settings.breakExtentionFails) snapshot?.withCurrentCredentials(_state.value.settings)?.let { scoreFailure(it, captured = true) }
        persistTimer()
    }

    private fun sendBreakMessage(settings: UserSettings, enabled: Boolean, message: String) {
        if (!enabled || !settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        val generation = accountGeneration
        viewModelScope.launch {
            val r = HabiticaAPI.sendPrivateMessage(settings, message)
            if (isCurrentAccount(settings, generation) && r is HabiticaAPI.Result.Error) _state.value = _state.value.copy(message = r.message)
        }
    }

    private fun breakSuggestion(index: Int, settings: UserSettings, date: java.util.Date): String {
        val c = java.util.Calendar.getInstance().apply { time = date }
        val now = c.get(java.util.Calendar.HOUR_OF_DAY) * 60 + c.get(java.util.Calendar.MINUTE)
        val next = settings.blockTimeRanges.getOrNull((index + 1) % settings.blockCount)
        val until = next?.let { (it.startMinutes - now).mod(1440) }
        return when {
            until != null && until in 1..10 -> "建议短休息 2 分钟：下一块即将开始"
            (index + 1) % 2 == 0 -> "建议长休息 15–20 分钟"
            else -> "建议普通休息 5–10 分钟"
        }
    }

    private suspend fun resolveHabit(settings: UserSettings, combo: Boolean, generation: Int, captured: Boolean = false): String? {
        habitMutex.lock()
        try {
            if (!isCurrentAccount(settings, generation)) return null
            val r = HabiticaAPI.ensureHabit(settings, combo)
            if (!isCurrentAccount(settings, generation)) return null
            if (r is HabiticaAPI.Result.Error) { _state.value = _state.value.copy(message = r.message); return null }
            val current = _state.value.settings
            val configurationMatches = (if (combo) current.customSetTask == settings.customSetTask else current.customPomodoroTask == settings.customPomodoroTask) &&
                (if (combo && settings.customSetTask) current.pomodoroSetTaskId == settings.pomodoroSetTaskId else if (!combo && settings.customPomodoroTask) current.pomodoroTaskId == settings.pomodoroTaskId else true)
            if (!captured && !configurationMatches) return null
            val id = (r as HabiticaAPI.Result.Success).value
            if (configurationMatches) updateSettings { if (combo) it.copy(pomodoroSetTaskId = id) else it.copy(pomodoroTaskId = id) }
            return id
        } finally { habitMutex.unlock() }
    }
    fun ensureDefaultHabits() {
        val settings = _state.value.settings
        val generation = accountGeneration
        if (!isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank() || !settings.connectHabitica) return
        viewModelScope.launch {
            _state.value = _state.value.copy(habiticaBusy = true)
            resolveHabit(settings, false, generation); resolveHabit(settings, true, generation)
            if (isCurrentAccount(settings, generation)) _state.value = _state.value.copy(habiticaBusy = false)
        }
    }

    // MARK: - Habitica：Role 页

    fun refreshProfile() {
        val settings = _state.value.settings
        profileJob?.cancel()
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) {
            _state.value = _state.value.copy(
                profile = null,
                profileLoading = false,
                profileError = "未连接 Habitica：请在设置中填写 User ID 与 API Token",
            )
            return
        }
        val generation = accountGeneration
        profileJob = viewModelScope.launch {
            _state.value = _state.value.copy(profileLoading = true, profileError = null)
            val result = HabiticaAPI.fetchProfile(settings)
            if (!isCurrentAccount(settings, generation)) return@launch
            when (result) {
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

    fun updateSettings(transform: (UserSettings) -> UserSettings) {
        val old = _state.value.settings
        var settings = transform(old).normalized()
        if (settings.uid != old.uid && !isValidHabiticaUid(settings.uid)) {
            _state.value = _state.value.copy(message = "User ID 必须是完整 UUID，不能包含空白；原账号和设置未改变")
            return
        }
        if (old.cloudAccount() != settings.cloudAccount()) {
            val previous = _state.value.store.copy(pomodoroHabitId = old.pomodoroTaskId, comboHabitId = old.pomodoroSetTaskId)
            val next = previous.forAccount(settings.cloudAccount())
            persistStore(next)
            settings = settings.copy(pomodoroTaskId = next.pomodoroHabitId, pomodoroSetTaskId = next.comboHabitId)
        }
        val settingsSaved = store.saveSettings(settings)
        _state.value = _state.value.copy(settings = settings,
            // FIX2(D2): surface a failed settings save; keep an active Top3 error otherwise.
            persistenceError = if (settingsSaved) _state.value.persistenceError else SETTINGS_PERSIST_FAILED)
        refreshDay()
        if (old.uid != settings.uid || old.apiToken != settings.apiToken || old.connectHabitica != settings.connectHabitica || old.developerServerUrl != settings.developerServerUrl) {
            accountGeneration++
            tasksGeneration++
            topThreeSyncGeneration++
            profileJob?.cancel()
            tasksJob?.cancel()
            topThreeSyncJob?.cancel()
            _state.value = _state.value.copy(profile = null, habits = emptyList(), dailies = emptyList(),
                profileLoading = false, tasksLoading = false, tasksError = null, scoringIds = emptySet(), habiticaBusy = false,
                topThreeSyncing = false, topThreeSyncError = null,
                profileError = if (!isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank() || !settings.connectHabitica) "未连接 Habitica" else null)
            refreshTopThreeFromCloud()
        }
        if (old.blockStartReminder != settings.blockStartReminder || old.enableBlockMode != settings.enableBlockMode ||
            old.blockCount != settings.blockCount || old.blockReminderMinutes != settings.blockReminderMinutes || old.blockTimeRanges != settings.blockTimeRanges || old.blockGoals != settings.blockGoals)
            com.habitica.pomodoro.service.BlockReminderReceiver.schedule(getApplication(), settings)
        // 运行中的专注切到 qishi（或恢复后场景缺失）：立即补选场景，随后的 refreshAudio 就能播放
        ensureQishiSceneForRunningFocus()
        PomodoroTimerService.refreshAudio(getApplication())
    }

    /** Histogram/blocks/plants use calendar days; Task alone uses the logical boundary. */
    fun refreshDay() {
        val s = _state.value
        val key = calendarDayKey()
        val index = currentBlockIndex(s.settings) ?: s.blockProgress.currentBlockIndex.coerceIn(0, s.settings.blockCount - 1)
        val count = s.dailyBlocks[key]?.blockProgress?.getOrNull(index) ?: 0
        val progress = BlockProgress(index, count)
        if (progress != s.blockProgress) store.saveBlockProgress(progress)
        val counts = store.loadPomoCount()
        _state.value = s.copy(blockProgress = progress, todayPomodoros = counts[calendarDayKey()] ?: 0, pomoCounts = counts, histogram = store.loadHistogram())
    }

    private fun recordPlant(outcome: String, combo: Boolean, settings: UserSettings, date: java.util.Date = java.util.Date()) {
        val s = _state.value
        val key = calendarDayKey(date)
        val index = currentBlockIndex(settings, date) ?: s.blockProgress.currentBlockIndex.coerceIn(0, settings.blockCount - 1)
        val existing = s.dailyBlocks[key] ?: DailyBlockProgress(key, List(settings.blockCount) { 0 }, settings.blockGoals)
        val completed = existing.blockProgress.getOrElse(index) { 0 }
        val oldPlant = s.plants[key] ?: PlantDay()
        val attempts = oldPlant.attempts.getOrElse(index) { emptyList() }
        val missing = (completed - attempts.count { it == "shrub" }).coerceAtLeast(0)
        val aligned = List(missing) { "shrub" } + attempts
        val newAttempts = List(maxOf(oldPlant.attempts.size, settings.blockCount)) { i ->
            if (i == index) aligned + outcome else oldPlant.attempts.getOrElse(i) { emptyList() }
        }
        val newTrees = List(maxOf(oldPlant.trees.size, settings.blockCount)) { i ->
            oldPlant.trees.getOrElse(i) { 0 } + if (i == index && combo) 1 else 0
        }
        val plants = s.plants + (key to PlantDay(newAttempts, newTrees))
        store.savePlants(plants)
        if (outcome == "wilted") {
            _state.value = s.copy(plants = plants)
            return
        }
        val next = completed + 1
        val progressList = List(maxOf(existing.blockProgress.size, settings.blockCount)) { i ->
            if (i == index) next else existing.blockProgress.getOrElse(i) { 0 }
        }
        val days = s.dailyBlocks + (key to existing.copy(blockProgress = progressList, blockGoals = settings.blockGoals))
        store.saveDailyBlocks(days)
        var history = s.blockHistory
        if (next >= settings.blockPomoCount && history[key].orEmpty().none { it.blockIndex == index && it.isComplete }) {
            val entry = BlockHistoryEntry(key, index, next, true, (date.time - 978307200000L) / 1000.0)
            history = history + (key to (history[key].orEmpty() + entry))
            store.saveBlockHistory(history)
        }
        val progress = BlockProgress(index, next)
        store.saveBlockProgress(progress)
        _state.value = s.copy(plants = plants, dailyBlocks = days, blockHistory = history, blockProgress = progress)
        val reminderKey = "$key-$index"
        val preferences = getApplication<Application>().getSharedPreferences("block_reminders", 0)
        if (settings.blockSprintReminder && settings.blockPomoCount == 6 && next == 4 && preferences.getString("sprint", "") != reminderKey) {
            preferences.edit().putString("sprint", reminderKey).apply()
            PomodoroTimerService.alert(getApplication(), "冲刺时间 🚀", "B${index + 1}: 4/6 番茄完成 · ${settings.blockGoals.getOrNull(index).orEmpty()}", 2200 + index)
        }
    }

    fun updateBlockGoal(index: Int, goal: String) {
        if (index !in 0 until _state.value.settings.blockCount) return
        updateSettings { s -> s.copy(blockGoals = List(maxOf(s.blockCount, s.blockGoals.size)) { i -> if (i == index) goal else s.blockGoals.getOrElse(i) { "" } }) }
    }

    fun updateBlockRange(index: Int, range: com.habitica.pomodoro.data.BlockTimeRange) {
        if (index !in 0 until _state.value.settings.blockCount) return
        updateSettings { s -> s.copy(blockTimeRanges = s.normalized().blockTimeRanges.mapIndexed { i, r -> if (i == index) range else r }) }
    }

    fun addBlockTask(index: Int, title: String) {
        if (title.isBlank() || index !in 0 until _state.value.settings.blockCount) return
        updateSettings { s -> s.copy(blockTasks = List(maxOf(s.blockCount, s.blockTasks.size)) { i ->
            val tasks = s.blockTasks.getOrElse(i) { emptyList() }
            if (i == index) tasks + BlockTask(title = title.trim()) else tasks
        }) }
    }

    fun toggleBlockTask(index: Int, taskId: String) = updateSettings { s ->
        s.copy(blockTasks = s.blockTasks.mapIndexed { i, tasks -> if (i == index) tasks.map { if (it.id == taskId) it.copy(isCompleted = !it.isCompleted) else it } else tasks })
    }

    fun deleteBlockTask(index: Int, taskId: String) = updateSettings { s ->
        s.copy(blockTasks = s.blockTasks.mapIndexed { i, tasks -> if (i == index) tasks.filterNot { it.id == taskId } else tasks })
    }

    fun editBlockTask(index: Int, id: String, title: String, estimate: Int) {
        if (title.isBlank() || estimate !in 1..12) return
        updateSettings { s -> s.copy(blockTasks = s.blockTasks.mapIndexed { i, list ->
            if (i == index) list.map { if (it.id == id) it.copy(title = title.trim(), estimatedPomo = estimate) else it } else list
        }) }
    }
    fun resetCurrentBlock() {
        refreshDay()
        val s = _state.value; val key = calendarDayKey(); val index = s.blockProgress.currentBlockIndex
        val day = s.dailyBlocks[key] ?: DailyBlockProgress(key, List(s.settings.blockCount) { 0 }, s.settings.blockGoals)
        val days = s.dailyBlocks + (key to day.copy(blockProgress = List(maxOf(s.settings.blockCount, day.blockProgress.size)) { if (it == index) 0 else day.blockProgress.getOrElse(it) { 0 } }))
        val progress = BlockProgress(index, 0)
        store.saveDailyBlocks(days); store.saveBlockProgress(progress)
        _state.value = s.copy(dailyBlocks = days, blockProgress = progress, message = "当前块计数已重置；已有植物与达标奖励记录保留，不重复奖励")
    }
    fun clearHistogram() {
        store.saveHistogram(emptyMap()); _state.value = _state.value.copy(histogram = emptyMap(), pomoCounts = emptyMap(), todayPomodoros = 0)
    }

    fun clearBlockHistory() {
        store.saveDailyBlocks(emptyMap()); store.saveBlockHistory(emptyMap()); store.savePlants(emptyMap())
        store.saveBlockProgress(BlockProgress())
        _state.value = _state.value.copy(dailyBlocks = emptyMap(), blockHistory = emptyMap(), plants = emptyMap(), blockProgress = BlockProgress())
        refreshDay()
    }

    fun refreshHabiticaTasks(type: String) {
        if (type != "habits" && type != "dailys") return
        val settings = _state.value.settings
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        tasksJob?.cancel()
        val generation = accountGeneration
        val request = ++tasksGeneration
        tasksJob = viewModelScope.launch {
            _state.value = _state.value.copy(tasksLoading = true, tasksError = null)
            val result = HabiticaAPI.fetchTaskItems(settings, type)
            if (!isCurrentAccount(settings, generation) || request != tasksGeneration) return@launch
            when (result) {
                is HabiticaAPI.Result.Success -> {
                    _state.value = if (type == "habits") _state.value.copy(habits = result.value.sortedBy { it.value }, tasksLoading = false)
                    else _state.value.copy(dailies = result.value, tasksLoading = false)
                }
                is HabiticaAPI.Result.Error -> _state.value = _state.value.copy(tasksLoading = false, tasksError = result.message)
            }
        }
    }

    fun scoreHabiticaTask(type: String, item: HabiticaTaskItem, direction: String) {
        if (type !in listOf("habits", "dailys") || direction !in listOf("up", "down") || item.id in _state.value.scoringIds) return
        val settings = _state.value.settings
        val generation = accountGeneration
        viewModelScope.launch {
            _state.value = _state.value.copy(scoringIds = _state.value.scoringIds + item.id, tasksError = null)
            val result = HabiticaAPI.scoreTask(settings, item.id, direction)
            if (!isCurrentAccount(settings, generation)) return@launch
            when (result) {
                is HabiticaAPI.Result.Error -> _state.value = _state.value.copy(tasksError = result.message)
                is HabiticaAPI.Result.Success -> {
                    if (type == "habits") _state.value = _state.value.copy(habits = _state.value.habits.map { if (it.id == item.id) it.copy(value = it.value + if (direction == "up") 1 else -1) else it })
                    else _state.value = _state.value.copy(dailies = _state.value.dailies.map { if (it.id == item.id) it.copy(completed = !it.completed) else it })
                    refreshProfile()
                }
            }
            _state.value = _state.value.copy(scoringIds = _state.value.scoringIds - item.id)
        }
    }

    fun refreshRuntimeAudio() { PomodoroTimerService.refreshAudio(getApplication()) }

    // MARK: - 栖时随机场景（ambientSource == "qishi"）
    // 选择与延续逻辑全部在 VM 层（可离线测试）；MediaPlayer 多轨流式播放只在 PomoAudio。

    private fun qishiLibrary(): List<QishiPreset> = qishiLibraryCache
        ?: (runCatching { qishiLibraryLoader?.invoke() }.getOrNull() ?: emptyList<QishiPreset>()).also { qishiLibraryCache = it }

    /** 新番茄开始：随机选一个场景并避开上个番茄；custom 模式清空场景状态。 */
    private fun selectQishiScene(settings: UserSettings) {
        if (settings.ambientSource != AMBIENT_SOURCE_QISHI) {
            if (_state.value.qishiScene != null) _state.value = _state.value.copy(qishiScene = null)
            return
        }
        val chosen = QishiLibrary.randomPreset(qishiLibrary(), excluding = lastQishiSceneId)
        if (chosen == null) {
            _state.value = _state.value.copy(qishiScene = null, message = QISHI_LIBRARY_UNAVAILABLE)
            return
        }
        lastQishiSceneId = chosen.id
        _state.value = _state.value.copy(qishiScene = chosen)
    }

    /** 正在运行的专注缺失场景（中途切到 qishi / 进程恢复后）时补选一次；已有场景绝不重随机。 */
    private fun ensureQishiSceneForRunningFocus() {
        val s = _state.value
        if (s.settings.ambientSource == AMBIENT_SOURCE_QISHI && s.qishiScene == null && s.isRunning && s.phase == Phase.POMODORO)
            selectQishiScene(s.settings)
    }

    /** 设置页试听：随机场景，不写 lastQishiSceneId、不影响当前番茄（试听播放器独立于前台服务）。 */
    fun randomQishiPreviewScene(): QishiPreset? = QishiLibrary.randomPreset(qishiLibrary(), excluding = null)

    /** 场景总数（设置页文案用）。 */
    fun qishiSceneCount(): Int = qishiLibrary().size

    /** 设备端播放错误（如栖时流式全轨失败）经既有 message 通道提示。 */
    fun reportAudioError(text: String) {
        _state.value = _state.value.copy(message = text)
    }

    fun clearMessage() {
        _state.value = _state.value.copy(message = null)
    }

    // MARK: - Task（Top Three）

    /** A failed/partial fetch never changes disk; merge against current local edits on success. */
    fun refreshTopThreeFromCloud() {
        val settings = _state.value.settings.copy()
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        if (creatingTasks > 0) return
        topThreeSyncJob?.cancel()
        val generation = accountGeneration
        val request = ++topThreeSyncGeneration
        val revision = localRevision
        topThreeSyncJob = viewModelScope.launch {
            // FIX3(D4): no optimistic clear at cycle start — an error whose condition
            // is still active (markers, delete protection, persistence failure) must
            // stay displayed. Clearing happens at successful completion, guarded.
            _state.value = _state.value.copy(topThreeSyncing = true)
            val result = HabiticaAPI.fetchTopThreeTodos(settings)
            if (!isCurrentAccount(settings, generation) || request != topThreeSyncGeneration) return@launch
            when (result) {
                is HabiticaAPI.Result.Success -> {
                    val current = _state.value.store
                    val merged = if (revision == localRevision && creatingTasks == 0) mergeTopThreeTodos(current, result.value) else current
                    if (merged != current) persistStore(merged)
                    val deletionConflict = result.value.any { it.id !in current.deletedCloudIds && current.quarantinesDeletedCreation(it) }
                    // FIX3(D4): a stale error must not survive a clean successful cycle, but
                    // never clear while an error condition is still active: quarantine
                    // conflict (this cycle), unresolved create markers, delete protection for
                    // a queued id, or a persistence failure (FIX2) of this cycle's save.
                    val latest = _state.value.store
                    val markersPending = latest.deletedCreateMarkers.isNotEmpty()
                    val deleteProtectionActive = latest.deletedCloudIds.any { id ->
                        latest.history.values.any { day -> day.taskGroups.flatten().any {
                            it.cloudAccount == latest.cloudAccount && it.habiticaTaskId == id &&
                                !(latest.deletedCloudTaskOrigins[id] == it.id && it.movedToToday)
                        } }
                    }
                    _state.value = _state.value.copy(topThreeSyncing = false,
                        topThreeSyncError = when {
                            deletionConflict -> "未确认创建请求的删除仍待核对；同日期 notes 的未知任务已隔离（包括改名任务），请人工核对，未按 notes 删除"
                            markersPending || deleteProtectionActive || _state.value.persistenceError != null -> _state.value.topThreeSyncError
                            else -> null
                        })
                }
                is HabiticaAPI.Result.Error -> _state.value = _state.value.copy(topThreeSyncing = false, topThreeSyncError = result.message)
            }
        }
    }

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
        if (group.count { !it.movedToToday } >= limit) {
            _state.value = _state.value.copy(message = "该分类最多 $limit 条任务")
            return
        }
        val newTask = com.habitica.pomodoro.data.TopThreeTask(title = trimmed, syncPending = true, cloudAccount = settings.cloudAccount())
        group.add(newTask)
        groups[categoryIndex] = group
        val newStore = s.copy(history = s.history + (todayKey to day.copy(taskGroups = groups)))
        persistStore(newStore)
        syncTaskToHabitica(categoryIndex, newTask, todayKey)
    }

    private fun newDay(date: String, categoryCount: Int) =
        com.habitica.pomodoro.data.TopThreeDay(
            date = date,
            taskGroups = List(categoryCount) { emptyList() },
        )

    fun editTask(categoryIndex: Int, taskIndex: Int, title: String) {
        val key = todayKey(); val day = _state.value.store.history[key] ?: return
        val task = day.taskGroups.getOrNull(categoryIndex)?.getOrNull(taskIndex) ?: return
        if (task.movedToToday || title.isBlank() || title.trim() == task.title) return
        replaceTask(task.id) { if (it.movedToToday) it else it.copy(title = title.trim(), syncPending = true, syncError = null, syncVersion = it.syncVersion + 1) }
        if (task.habiticaTaskId != null) syncExistingTask(task.id)
    }

    fun toggleTask(categoryIndex: Int, taskIndex: Int) {
        val day = _state.value.store.history[todayKey()] ?: return
        val task = day.taskGroups.getOrNull(categoryIndex)?.getOrNull(taskIndex) ?: return
        if (task.movedToToday) return
        replaceTask(task.id) { if (it.movedToToday) it else it.copy(isCompleted = !task.isCompleted, syncPending = true, syncError = null, syncVersion = it.syncVersion + 1) }
        if (task.habiticaTaskId != null) syncExistingTask(task.id)
    }

    fun deleteTask(categoryIndex: Int, taskIndex: Int) {
        val s = _state.value.store; val key = todayKey(); val day = s.history[key] ?: return
        val task = day.taskGroups.getOrNull(categoryIndex)?.getOrNull(taskIndex) ?: return
        if (task.movedToToday) return
        val groups = day.taskGroups.mapIndexed { gi, g -> if (gi == categoryIndex) g.filterNot { it.id == task.id && !it.movedToToday } else g }
        val owner = _state.value.settings.cloudAccount()
        val owned = owner != null && s.cloudAccount == owner && task.cloudAccount == owner
        val id = task.habiticaTaskId.takeIf { owned }
        // Persist tombstone BEFORE attempting delete; inbound refresh cannot resurrect a failed delete.
        val marker = if (owned) task.pendingCreateTitle?.let { title -> task.pendingCreateNotes?.let { "$it\n$title" } } else null
        persistStore(s.copy(history = s.history + (key to day.copy(taskGroups = groups)), deletedCloudIds = s.deletedCloudIds + listOfNotNull(id),
            deletedCloudTaskOrigins = if (id == null) s.deletedCloudTaskOrigins else s.deletedCloudTaskOrigins + (id to task.id),
            // D1: link the queued remote id to its lost-creation marker so any later
            // marker-less consumption of the queue entry retires the marker atomically.
            deletedCloudIdMarkers = if (id == null || marker == null) s.deletedCloudIdMarkers else s.deletedCloudIdMarkers + (id to marker),
            deletedCreateMarkers = s.deletedCreateMarkers + listOfNotNull(marker)))
        id?.let { deleteCloudTask(it) }
        if (marker != null) retryDeletedCreations()
    }

    private fun deleteCloudTask(id: String, marker: String? = null) {
        val settings = _state.value.settings; val generation = accountGeneration
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) {
            _state.value = _state.value.copy(topThreeSyncError = "删除已保留在本机；连接 Habitica 后可重试待同步操作")
            return
        }
        viewModelScope.launch {
            if (!isCurrentAccount(settings, generation)) return@launch
            val current = _state.value.store
            val originalId = current.deletedCloudTaskOrigins[id]
            fun mayDelete(): Boolean {
                if (!isCurrentAccount(settings, generation)) return false
                val latest = _state.value.store
                if (latest.cloudAccount != settings.cloudAccount() || id !in latest.deletedCloudIds ||
                    latest.deletedCloudTaskOrigins[id] != originalId) return false
                if (latest.history.values.any { day -> day.taskGroups.flatten().any {
                    it.cloudAccount == latest.cloudAccount && it.habiticaTaskId == id &&
                        !(originalId != null && it.id == originalId && it.movedToToday)
                } }) {
                    _state.value = _state.value.copy(topThreeSyncError = "待删除 ID 已绑定本地任务；删除保护保留，请人工核对")
                    return false
                }
                return true
            }
            if (!mayDelete()) return@launch
            val result = HabiticaAPI.deleteTodo(settings, id)
            if (!mayDelete()) return@launch
            val readBack = HabiticaAPI.fetchTodo(settings, id)
            if (!mayDelete()) return@launch
            if (readBack is HabiticaAPI.Result.Error && readBack.statusCode == 404) {
                val s = _state.value.store
                // D1: a restart retry consumes the queue with marker == null; retire the marker
                // linked to this remote id in the SAME atomic save, or it orphans forever —
                // re-erroring every sync and quarantining future legitimate cloud todos.
                val resolvedMarker = marker ?: s.deletedCloudIdMarkers[id]
                persistStore(s.copy(deletedCloudIds = s.deletedCloudIds - id, deletedCloudTaskOrigins = s.deletedCloudTaskOrigins - id,
                    deletedCloudIdMarkers = s.deletedCloudIdMarkers - id,
                    deletedCreateMarkers = if (resolvedMarker == null) s.deletedCreateMarkers else s.deletedCreateMarkers - resolvedMarker))
            } else _state.value = _state.value.copy(topThreeSyncError = "远端删除尚未确认；本机删除保留，可重试")
        }
    }

    private fun findTask(id: String): Triple<String, Int, com.habitica.pomodoro.data.TopThreeTask>? =
        _state.value.store.history.entries.sortedByDescending { it.key }.firstNotNullOfOrNull { (date, day) ->
            day.taskGroups.withIndex().firstNotNullOfOrNull { (index, group) -> group.firstOrNull { it.id == id && !it.movedToToday }?.let { Triple(date, index, it) } }
        }
    private fun replaceTask(id: String, transform: (com.habitica.pomodoro.data.TopThreeTask) -> com.habitica.pomodoro.data.TopThreeTask) {
        val s = _state.value.store
        persistStore(s.copy(history = s.history.mapValues { (_, day) -> day.copy(taskGroups = day.taskGroups.map { list -> list.map { if (it.id == id) transform(it) else it } }) }))
    }

    private data class TaskSyncSnapshot(
        val date: String, val categoryIndex: Int, val category: String, val owner: String?,
        val localId: String, val remoteId: String, val title: String, val completed: Boolean, val version: Long,
    )
    private fun syncSnapshot(localId: String): TaskSyncSnapshot? {
        val (date, index, task) = findTask(localId) ?: return null
        val category = _state.value.store.categoryNames.getOrNull(index) ?: return null
        return TaskSyncSnapshot(date, index, category, task.cloudAccount, task.id,
            task.habiticaTaskId ?: return null, task.title, task.isCompleted, task.syncVersion)
    }

    /** Reconcile completion before score; only a full, unchanged write snapshot may acknowledge dirty. */
    private fun maySyncTask(snapshot: TaskSyncSnapshot, settings: UserSettings, generation: Int): Boolean {
        if (!isCurrentAccount(settings, generation)) return false
        val current = _state.value.store
        val reason = when {
            current.cloudAccount != settings.cloudAccount() || snapshot.owner != settings.cloudAccount() -> "任务所属账号已变化"
            current.remoteIdOccupied(snapshot.remoteId, snapshot.localId) -> "远端 ID 已绑定其他本地任务，请人工核对"
            syncSnapshot(snapshot.localId) != snapshot -> "原任务已移除或修改，同步快照已变化"
            else -> return true
        }
        val message = "$reason；本机修改保留，未继续写入或确认"
        replaceTask(snapshot.localId) { if (it.cloudAccount == snapshot.owner) it.copy(syncError = message) else it }
        _state.value = _state.value.copy(topThreeSyncError = message)
        return false
    }

    private fun syncExistingTask(localId: String) {
        val settings = _state.value.settings; val generation = accountGeneration
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        viewModelScope.launch {
            taskMutex.lock()
            try {
                repeat(4) {
                    if (!isCurrentAccount(settings, generation)) return@launch
                    val found = findTask(localId) ?: return@launch
                    val (date, categoryIndex, task) = found
                    if (task.cloudAccount != settings.cloudAccount()) return@launch
                    val remoteId = task.habiticaTaskId ?: return@launch
                    if (!task.syncPending) return@launch
                    val snapshot = syncSnapshot(localId) ?: return@launch
                    val category = snapshot.category
                    if (!maySyncTask(snapshot, settings, generation)) return@launch
                    val tag = resolveCategoryTag(settings, category, generation) { maySyncTask(snapshot, settings, generation) }
                    if (!maySyncTask(snapshot, settings, generation)) return@launch
                    if (tag !is HabiticaAPI.Result.Success || tag.value.isNullOrBlank()) {
                        replaceTask(localId) { it.copy(syncError = "分类 tag 同步失败，本机修改保留") }; return@launch
                    }
                    val notes = topThreeNotes(category, date)
                    val updated = HabiticaAPI.updateTodo(settings, remoteId, task.title, notes, listOf(tag.value!!))
                    if (!maySyncTask(snapshot, settings, generation)) return@launch
                    if (updated is HabiticaAPI.Result.Error) {
                        replaceTask(localId) { it.copy(syncError = updated.message) }; return@launch
                    }
                    var remote = HabiticaAPI.fetchTodo(settings, remoteId)
                    if (!maySyncTask(snapshot, settings, generation)) return@launch
                    if (remote is HabiticaAPI.Result.Success && remote.value.completed != task.isCompleted) {
                        val score = HabiticaAPI.scoreTask(settings, remoteId, if (task.isCompleted) "up" else "down")
                        if (!maySyncTask(snapshot, settings, generation)) return@launch
                        if (score is HabiticaAPI.Result.Error) {
                            replaceTask(localId) { it.copy(syncError = score.message) }; return@launch
                        }
                        remote = HabiticaAPI.fetchTodo(settings, remoteId)
                        if (!maySyncTask(snapshot, settings, generation)) return@launch
                    }
                    if (!maySyncTask(snapshot, settings, generation)) return@launch
                    if (remote is HabiticaAPI.Result.Success && remote.value.id == snapshot.remoteId && remote.value.title == task.title &&
                        remote.value.completed == task.isCompleted && remote.value.notes == notes && tag.value in remote.value.tags) {
                        replaceTask(localId) { it.copy(syncPending = false, syncError = null) }
                        val current = _state.value.store
                        persistStore(current.copy(categoryTagIds = current.categoryTagIds + (category to tag.value!!)))
                        refreshProfile()
                    } else replaceTask(localId) { it.copy(syncError = "远端结果未确认；本机修改保留，可重试") }
                    return@launch
                }
            } finally { taskMutex.unlock() }
        }
    }

    private fun retryDeletedCreations() {
        val settings = _state.value.settings; val generation = accountGeneration
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        viewModelScope.launch {
            val r = HabiticaAPI.fetchTopThreeTodos(settings)
            if (!isCurrentAccount(settings, generation)) return@launch
            if (r is HabiticaAPI.Result.Error) { _state.value = _state.value.copy(topThreeSyncError = r.message); return@launch }
            for (marker in _state.value.store.deletedCreateMarkers) {
                val current = _state.value.store
                val linked = current.history.values.flatMap { it.taskGroups.flatten() }.filter { it.cloudAccount == current.cloudAccount }.mapNotNull { it.habiticaTaskId }.toSet()
                val matches = (r as HabiticaAPI.Result.Success).value.distinctBy { it.id }.filter {
                    it.id.isNotBlank() && it.id !in linked && parseTopThreeNotes(it.notes) != null && "${it.notes}\n${it.title}" == marker
                }
                if (matches.size == 1) {
                    val id = matches.single().id
                    // D1: persist the id->marker link with the enqueue so a restart retry that
                    // consumes the id with marker == null can still retire this marker.
                    persistStore(current.copy(deletedCloudIds = current.deletedCloudIds + id,
                        deletedCloudIdMarkers = current.deletedCloudIdMarkers + (id to marker)))
                    deleteCloudTask(id, marker)
                }
                else _state.value = _state.value.copy(topThreeSyncError = "未确认创建请求的删除已保护在本机；云端匹配不唯一或尚不可见，请稍后重试/人工核对")
            }
        }
    }

    fun retryPendingTasks() {
        retryCategoryTags()
        _state.value.store.deletedCloudIds.forEach { deleteCloudTask(it) }
        retryDeletedCreations()
        _state.value.store.history.forEach { (date, day) -> day.taskGroups.forEachIndexed { i, group -> group.filter { it.syncPending && !it.movedToToday }.forEach {
            if (it.habiticaTaskId == null) syncTaskToHabitica(i, it, date) else syncExistingTask(it.id)
        } } }
    }

    /**
     * FIX1(P0): user-confirmed manual cleanup for orphaned creation markers.
     * Markers queued before the D1 fix have no remote-id association and can
     * never resolve automatically: every retry re-errors and the quarantine
     * keeps blocking same-signature inbound todos. Clears deletedCreateMarkers
     * and deletedCloudIdMarkers for the CURRENT owner partition only, persisted
     * via the normal store save (which also refreshes the counts the settings
     * entry displays). NEVER touches deletedCloudIds / deletedCloudTaskOrigins
     * (explicit delete intents are sacred) nor other owners' accountStores
     * partitions. The UI must gate this behind an explicit confirmation;
     * there is no automatic or time-based cleanup.
     */
    fun clearQuarantinedCreateMarkers() {
        val s = _state.value.store
        persistStore(s.copy(deletedCreateMarkers = emptySet(), deletedCloudIdMarkers = emptyMap()))
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
        if (tGroup.count { !it.movedToToday } >= limit) {
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
        replaceTask(task.id) { it.copy(syncPending = true, syncError = null, syncVersion = it.syncVersion + 1) }
        if (task.habiticaTaskId != null) syncExistingTask(task.id)
    }

    fun renameCategory(index: Int, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        val s = _state.value.store
        val oldName = s.categoryNames.getOrNull(index) ?: return
        if (oldName == trimmed || s.categoryNames.any { it == trimmed }) return
        val newNames = s.categoryNames.mapIndexed { i, n -> if (i == index) trimmed else n }
        val newTagIds = s.categoryTagIds.toMutableMap()
        val tagId = newTagIds.remove(oldName)
        if (tagId != null) newTagIds[trimmed] = tagId
        persistStore(s.copy(categoryNames = newNames, categoryTagIds = newTagIds,
            pendingTagNames = if (tagId == null) s.pendingTagNames else s.pendingTagNames + (tagId to trimmed)))
        val tasks = _state.value.store.history.values.flatMap { it.taskGroups.getOrNull(index).orEmpty() }.distinctBy { it.id }
        tasks.forEach { task -> replaceTask(task.id) { it.copy(syncPending = true, syncError = null, syncVersion = it.syncVersion + 1) } }
        retryCategoryTags()
        tasks.filter { it.habiticaTaskId != null }.forEach { syncExistingTask(it.id) }
    }

    /** Honor cached IDs and pending offline names; never replace a rename with a new tag POST. */
    private suspend fun resolveCategoryTag(settings: UserSettings, category: String, generation: Int,
        stillValid: () -> Boolean = { true }): HabiticaAPI.Result<String?> {
        if (!stillValid()) return HabiticaAPI.Result.Error("任务同步快照已变化")
        if (!isCurrentAccount(settings, generation)) return HabiticaAPI.Result.Error("账号已变化")
        val current = _state.value.store
        val known = current.categoryTagIds[category]
        if (known != null) {
            val desired = current.pendingTagNames[known]
            if (desired != null) {
                if (desired != category) return HabiticaAPI.Result.Error("分类名称已变化；修改保留")
                val result = HabiticaAPI.updateTag(settings, known, desired)
                if (!stillValid()) return HabiticaAPI.Result.Error("任务同步快照已变化")
                if (!isCurrentAccount(settings, generation)) return HabiticaAPI.Result.Error("账号已变化")
                if (result is HabiticaAPI.Result.Error) return result
            }
            val tags = HabiticaAPI.fetchTags(settings)
            if (!isCurrentAccount(settings, generation)) return HabiticaAPI.Result.Error("账号已变化")
            if (tags is HabiticaAPI.Result.Error) return tags
            if (!stillValid()) return HabiticaAPI.Result.Error("任务同步快照已变化")
            if ((tags as HabiticaAPI.Result.Success).value[category] != known) return HabiticaAPI.Result.Error("分类 tag 改名未确认；本机保留，可重试旧 ID")
            val latest = _state.value.store
            if (latest.categoryTagIds[category] != known || latest.pendingTagNames[known] != desired) return HabiticaAPI.Result.Error("分类名称已变化；修改保留")
            if (desired != null) persistStore(latest.copy(pendingTagNames = latest.pendingTagNames - known))
            return HabiticaAPI.Result.Success(known)
        }
        val result = HabiticaAPI.ensureTag(settings, category)
        if (!stillValid()) return HabiticaAPI.Result.Error("任务同步快照已变化")
        if (!isCurrentAccount(settings, generation)) return HabiticaAPI.Result.Error("账号已变化")
        if (result is HabiticaAPI.Result.Success && !result.value.isNullOrBlank()) {
            val tags = HabiticaAPI.fetchTags(settings)
            if (!isCurrentAccount(settings, generation)) return HabiticaAPI.Result.Error("账号已变化")
            if (tags !is HabiticaAPI.Result.Success || tags.value[category] != result.value) return HabiticaAPI.Result.Error("分类 tag 创建未确认；本机保留")
            if (!stillValid()) return HabiticaAPI.Result.Error("任务同步快照已变化")
            val latest = _state.value.store
            if (category !in latest.categoryNames) return HabiticaAPI.Result.Error("分类名称已变化；修改保留")
            persistStore(latest.copy(categoryTagIds = latest.categoryTagIds + (category to result.value!!)))
        }
        return result
    }

    private fun retryCategoryTags() {
        val settings = _state.value.settings; val generation = accountGeneration
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank()) return
        viewModelScope.launch {
            taskMutex.lock()
            try {
                for (name in _state.value.store.pendingTagNames.values.toSet()) {
                    val result = resolveCategoryTag(settings, name, generation)
                    if (!isCurrentAccount(settings, generation)) return@launch
                    if (result is HabiticaAPI.Result.Error) _state.value = _state.value.copy(topThreeSyncError = result.message)
                }
            } finally { taskMutex.unlock() }
        }
    }

    private fun persistStore(s: TopThreeStore) {
        localRevision++
        // FIX2(D2): a failed save must surface; memory keeps advancing as before.
        val saved = store.saveTopThree(s)
        _state.value = _state.value.copy(store = s,
            persistenceError = if (saved) null else TOP_THREE_PERSIST_FAILED)
    }

    /** Creation has no idempotency token: never automatically retry an ambiguous response. */
    private fun syncTaskToHabitica(categoryIndex: Int, task: com.habitica.pomodoro.data.TopThreeTask, dateKey: String) {
        val settings = _state.value.settings
        if (!settings.connectHabitica || !isValidHabiticaUid(settings.uid) || settings.apiToken.isBlank() || task.id in creationIds) return
        if (task.cloudAccount != settings.cloudAccount()) return
        val category = _state.value.store.categoryNames.getOrNull(categoryIndex) ?: return
        val generation = accountGeneration
        creationIds += task.id; creatingTasks++
        viewModelScope.launch {
            try {
                val initial = findTask(task.id) ?: return@launch
                fun unchanged(expected: Triple<String, Int, com.habitica.pomodoro.data.TopThreeTask>): Boolean {
                    if (!isCurrentAccount(settings, generation)) return false
                    val latest = findTask(task.id)
                    if (_state.value.store.cloudAccount == settings.cloudAccount() && expected.third.cloudAccount == settings.cloudAccount() &&
                        latest != null && latest == expected && _state.value.store.categoryNames.getOrNull(latest.second) == category) return true
                    val message = "原创建任务已移除、所属账号或完整快照已变化；本机待同步保留，请人工核对"
                    replaceTask(task.id) { if (it.cloudAccount == settings.cloudAccount()) it.copy(syncError = message) else it }
                    _state.value = _state.value.copy(topThreeSyncError = message)
                    return false
                }
                if (!unchanged(initial)) return@launch
                val tag = resolveCategoryTag(settings, category, generation) { unchanged(initial) }
                if (!isCurrentAccount(settings, generation)) return@launch
                if (!unchanged(initial)) return@launch
                if (tag !is HabiticaAPI.Result.Success || tag.value.isNullOrBlank()) {
                    replaceTask(task.id) { it.copy(syncError = "分类 tag 同步失败；尚未创建 todo") }; return@launch
                }
                // Before creating, reconcile a unique exact owned record (e.g. POST succeeded but response was lost).
                val cloud = HabiticaAPI.fetchTopThreeTodos(settings)
                if (!isCurrentAccount(settings, generation)) return@launch
                if (!unchanged(initial)) return@launch
                if (cloud is HabiticaAPI.Result.Error) { replaceTask(task.id) { it.copy(syncError = cloud.message) }; return@launch }
                val notes = topThreeNotes(category, dateKey)
                val currentTask = findTask(task.id)?.third ?: return@launch
                if (currentTask.habiticaTaskId != null) { syncExistingTask(task.id); return@launch }
                val hasAttempt = currentTask.pendingCreateTitle != null && currentTask.pendingCreateNotes != null
                val matches = if (hasAttempt) (cloud as HabiticaAPI.Result.Success).value.distinctBy { it.id }.filter {
                    it.title == currentTask.pendingCreateTitle && it.notes == currentTask.pendingCreateNotes
                } else emptyList()
                val candidates = if (hasAttempt) _state.value.store.pendingCreateCandidates(
                    currentTask.pendingCreateTitle!!, currentTask.pendingCreateNotes!!) else emptyList()
                val occupied = matches.any { _state.value.store.remoteIdOccupied(it.id, task.id) }
                if (hasAttempt && (candidates.singleOrNull()?.id != task.id || matches.size != 1 || occupied)) {
                    replaceTask(task.id) { it.copy(syncError = "先前创建结果不明：云端尚不可见、匹配不唯一或 ID 已绑定其他任务；请稍后核对，未重复 POST") }
                    return@launch
                }
                var bindingSnapshot = findTask(task.id) ?: return@launch
                val created = if (hasAttempt) HabiticaAPI.Result.Success(matches.single().id)
                    else {
                        val latest = findTask(task.id) ?: return@launch
                        val latestCategory = _state.value.store.categoryNames.getOrNull(latest.second) ?: return@launch
                        // The captured category/tag must still describe this UUID at the POST boundary.
                        if (latest.first != dateKey || latest.second != categoryIndex || latestCategory != category || latest.third.syncVersion != currentTask.syncVersion) return@launch
                        replaceTask(task.id) { it.copy(pendingCreateTitle = latest.third.title, pendingCreateNotes = notes) }
                        bindingSnapshot = findTask(task.id) ?: return@launch
                        HabiticaAPI.createTodo(settings, latest.third.title, notes, listOf(tag.value!!))
                    }
                if (!isCurrentAccount(settings, generation)) return@launch
                if (created is HabiticaAPI.Result.Success && !created.value.isNullOrBlank()) {
                    val id = created.value!!
                    // Recheck the latest partition at binding, including changes while the POST was in flight.
                    val latestStore = _state.value.store
                    val attemptTitle = bindingSnapshot.third.pendingCreateTitle ?: return@launch
                    val attemptNotes = bindingSnapshot.third.pendingCreateNotes ?: return@launch
                    val deletionMarker = "$attemptNotes\n$attemptTitle"
                    if (findTask(task.id) == null && deletionMarker in latestStore.deletedCreateMarkers && !latestStore.remoteIdOccupied(id, task.id)) {
                        // D1: same enqueue-time id->marker link as retryDeletedCreations.
                        persistStore(latestStore.copy(deletedCloudIds = latestStore.deletedCloudIds + id,
                            deletedCloudIdMarkers = latestStore.deletedCloudIdMarkers + (id to deletionMarker)))
                        deleteCloudTask(id, deletionMarker)
                        return@launch
                    }
                    if (!unchanged(bindingSnapshot)) return@launch
                    if (latestStore.remoteIdOccupied(id, task.id) ||
                        latestStore.pendingCreateCandidates(attemptTitle, attemptNotes).singleOrNull()?.id != task.id) {
                        replaceTask(task.id) { it.copy(syncError = "创建匹配不唯一或远端 ID 已绑定其他本地任务；请人工核对，未重复创建") }
                        return@launch
                    }
                    replaceTask(task.id) { if (it.cloudAccount == settings.cloudAccount()) it.copy(habiticaTaskId = id, syncPending = true, pendingCreateTitle = null, pendingCreateNotes = null, syncVersion = it.syncVersion + 1) else it }
                    syncExistingTask(task.id)
                } else replaceTask(task.id) { it.copy(syncError = "todo 创建结果未确认；本机保留，重试前会先核对云端以避免重复") }
            } finally { creationIds -= task.id; creatingTasks-- }
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
        // FIX2(D2): user-visible persistence failure messages.
        private const val TOP_THREE_PERSIST_FAILED = "本地写入失败：Top3 任务数据未保存，重启后本次改动将丢失"
        private const val SETTINGS_PERSIST_FAILED = "本地写入失败：设置未保存，重启后将恢复旧设置"
        /** ambientSource 的栖时取值（与 Apple 端设置 JSON 一致）；其他值一律按 custom 处理 */
        const val AMBIENT_SOURCE_QISHI = "qishi"
        private const val QISHI_LIBRARY_UNAVAILABLE = "栖时场景库不可用（qishi_presets.json 缺失或为空）"
    }
}

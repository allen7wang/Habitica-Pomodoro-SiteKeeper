import Foundation
import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - Notification Names
extension Notification.Name {
    static let badgeUpdate = Notification.Name("badgeUpdate")
}

// MARK: - Timer State
enum TimerPhase: String { case idle, pomodoro, breakTime, breakExtension, manualBreak }
enum TomatoState { case wait, progress, freeze, breakTime, win, warning }

// MARK: - Pomodoro Engine
class PomodoroEngine: ObservableObject {
    static let shared = PomodoroEngine()

    // Published state
    @Published var timerString: String = "00:00"
    @Published var timerValue: Int = 0
    @Published var isRunning: Bool = false
    @Published var isFrozen: Bool = false
    @Published var phase: TimerPhase = .idle
    @Published var pomoSetCounter: Int = 0
    @Published var tomatoState: TomatoState = .wait
    @Published var todayPomodoros: Int = 0
    @Published var habiticaMonies: Double = 0
    @Published var habiticaExp: Double = 0
    @Published var habiticaHp: Double = 0
    @Published var habiticaConnected: Bool = false
    @Published var lastNotification: String = ""

    // Internal
    private var timer: Timer?
    private var duringHandler: (() -> Void)?
    private var endHandler: (() -> Void)?
    /// 当前阶段的绝对结束时刻（iOS 后台 Timer 会被挂起，回前台据此重算剩余时间）
    private(set) var phaseEndsAt: Date?
    private var pomodoroTaskId: String?
    private var pomodoroSetTaskId: String?
    private var api = HabiticaAPI.shared
    private var settingsManager = SettingsManager.shared
    private var audioManager = AudioManager.shared
    private var histogramManager = HistogramManager.shared

    #if os(iOS)
    static let backgroundEndNotificationId = "pomo-phase-end"
    #endif

    var settings: UserSettings { settingsManager.settings }

    // MARK: - Activate (main button / hotkey)
    func activate() {
        if isFrozen {
            unfreeze()
        } else if phase == .manualBreak {
            startBreak()
        } else if !isRunning || phase == .breakTime || phase == .breakExtension {
            if pomoSetCounter == settings.pomoSetNum {
                reset()
            } else {
                startPomodoro()
            }
        } else {
            // Running pomodoro → interrupted
            pomodoroInterrupted(breakStreak: true)
        }
    }

    // MARK: - Start Pomodoro
    func startPomodoro() {
        #if os(iOS)
        requestNotificationPermissionIfNeeded()
        #endif
        stopTimer()
        let duration = settings.pomoDurationMins * 60
        isRunning = true
        phase = .pomodoro
        isFrozen = false
        startTimer(duration: duration, during: { [weak self] in
            self?.duringPomodoro()
        }, end: { [weak self] in
            Task { await self?.pomodoroEnds() }
        })
        updateTomato()
        audioManager.playAmbient(sound: settings.ambientSound, volume: settings.ambientSoundVolume)
    }

    // MARK: - During Pomodoro
    private func duringPomodoro() {
        updateTomato()
        audioManager.playAmbient(sound: settings.ambientSound, volume: settings.ambientSoundVolume)
        // Notify badge to update
        NotificationCenter.default.post(name: .badgeUpdate, object: nil)
    }

    // MARK: - Pomodoro Ends
    func pomodoroEnds() async {
        stopTimer()
        audioManager.stopAmbient()
        histogramManager.incrementToday(pomodoros: 1, minutes: settings.pomoDurationMins)
        await MainActor.run {
            self.todayPomodoros = histogramManager.getToday()?.pomodoros ?? 0
        }

        var msg = "Pomodoro ended.\nYou have done \(histogramManager.getToday()?.pomodoros ?? 0) today!"
        let setComplete = pomoSetCounter >= settings.pomoSetNum - 1

        // MARK: - Block Mode Logic
        if settings.enableBlockMode {
            // 根据当前时间确定属于哪个块
            BlockProgressManager.shared.recordPomoInCurrentBlock(settings: settings)

            let (completed, total) = BlockProgressManager.shared.getCurrentBlockCompletion(settings: settings)
            let bp = BlockProgressManager.shared.blockProgress

            if completed >= total {
                // Block Complete
                BlockProgressManager.shared.recordBlockComplete(settings: settings)
                let goal = bp.getBlockGoal(goals: settings.blockGoals)
                let blockIdx = bp.currentBlockIndex
                
                // 发送块奖励
                await BlockRewardManager.shared.sendBlockReward(settings: settings, blockIndex: blockIdx, blockGoal: goal)
                
                // 获取休息建议
                let breakSuggestion = BlockRewardManager.shared.suggestBreakType(settings: settings, blockIndex: blockIdx)
                
                msg = "Block \(blockIdx + 1) Complete! 🎉\nGoal: \(goal.isEmpty ? "No goal" : goal)\n\n\(breakSuggestion)"

                // 不再自动切换块，让时间决定块索引
                BlockProgressManager.shared.saveProgress()
            } else {
                // Still working on current block
                let goal = bp.getBlockGoal(goals: settings.blockGoals)
                msg = "Pomodoro ended.\nCurrent Block (\(bp.currentBlockIndex + 1)): \(completed)/\(total)\nGoal: \(goal)"
            }
            // Notify badge to update
            NotificationCenter.default.post(name: .badgeUpdate, object: nil)
        }

        if settings.pomoHabitPlus || (setComplete && settings.pomoSetHabitPlus) {
            await api.fetchUserData(settings: settings, silent: true)
            let habitId = setComplete && settings.pomoSetHabitPlus ? pomodoroSetTaskId : pomodoroTaskId
            if let hid = habitId, let result = await api.scoreHabit(taskId: hid, direction: "up", settings: settings) {
                let deltaGold = (result["gp"] ?? 0) - api.monies
                let deltaExp = (result["exp"] ?? 0) - api.exp
                let expText = deltaExp < 0 ? "You leveled up!" : "You Earned Exp: +\(String(format: "%.2f", deltaExp))"
                if !settings.enableBlockMode {
                    msg = "You Earned Gold: +\(String(format: "%.2f", deltaGold))\n\(expText)"
                }
                await api.fetchUserData(settings: settings, silent: true)
                await MainActor.run {
                    self.habiticaMonies = api.monies
                    self.habiticaExp = api.exp
                    self.habiticaHp = api.hp
                }
            }
        }

        await MainActor.run {
            self.pomoSetCounter += 1
            if setComplete { self.sendNotification(title: "Pomodoro Set Complete!", body: msg) }
            else { self.sendNotification(title: "Time's Up", body: msg) }
        }

        if settings.manualBreak {
            await MainActor.run { self.manualBreak() }
        } else {
            startBreak()
        }

        await MainActor.run {
            self.audioManager.playSound(self.settings.pomoEndSound, volume: self.settings.pomoEndSoundVolume)
            self.isFrozen = false
            self.updateTomato()
        }
    }

    // MARK: - Start Break
    func startBreak() {
        stopTimer()
        let duration: Int
        if pomoSetCounter == settings.pomoSetNum {
            duration = settings.longBreakDuration * 60
        } else {
            duration = settings.breakDuration * 60
        }
        isRunning = true
        phase = .breakTime
        isFrozen = false
        startTimer(duration: duration, during: { [weak self] in
            self?.duringBreak()
        }, end: { [weak self] in
            self?.breakEnds()
        })
        updateTomato()
    }

    // MARK: - Manual Break (waiting for user click)
    func manualBreak() {
        stopTimer()
        isRunning = false
        phase = .manualBreak
        timerString = "GOOD!"
        updateTomato()
    }

    private func duringBreak() {
        updateTomato()
    }

    // MARK: - Break Ends
    func breakEnds() {
        let onManualTakeBreak = false
        stopTimer()
        var msg: String

        if pomoSetCounter == settings.pomoSetNum {
            msg = "Long Break is over"
            reset()
            if settings.longBreakNotify {
                Task { await api.sendPrivateMessage(msg, settings: settings) }
            }
        } else {
            msg = "Back to work"
            startBreakExtension(duration: settings.breakExtention * 60)
        }

        sendNotification(title: "Time's Up", body: msg)
        audioManager.playSound(settings.breakEndSound, volume: settings.breakEndSoundVolume)
        _ = onManualTakeBreak
        updateTomato()
    }

    // MARK: - Break Extension
    func startBreakExtension(duration: Int) {
        stopTimer()
        isRunning = true
        phase = .breakExtension
        isFrozen = false
        let endFunc: () -> Void = settings.resetPomoAfterBreak ? { [weak self] in
            self?.pomodoroInterrupted(breakStreak: true)
        } : { [weak self] in
            self?.pomodoroInterrupted(breakStreak: false)
        }
        startTimer(duration: duration, during: { [weak self] in
            self?.duringBreakExtension()
        }, end: endFunc)
        if settings.breakExtentionNotify {
            Task { await api.sendPrivateMessage("Back to work! \(settings.breakExtention) minutes left for Break Extension.", settings: settings) }
        }
        updateTomato()
    }

    private func duringBreakExtension() {
        updateTomato()
    }

    // MARK: - Pomodoro Interrupted
    func pomodoroInterrupted(breakStreak: Bool) {
        audioManager.stopAmbient()
        let failedBreakExtension = settings.breakExtentionFails && phase == .breakExtension
        let breakExtensionZero = !settings.breakExtentionFails && settings.breakExtention == 0

        if breakStreak {
            reset()
        } else {
            pauseTimer()
            timerString = "GO!"
        }

        if breakExtensionZero { return }

        if settings.pomoHabitMinus || failedBreakExtension {
            Task {
                await api.fetchUserData(settings: settings, silent: true)
                if let hid = pomodoroTaskId, let result = await api.scoreHabit(taskId: hid, direction: "down", settings: settings) {
                    let deltaHp = (result["hp"] ?? 0) - api.hp
                    await MainActor.run {
                        self.sendNotification(title: "Pomodoro Failed!", body: "You Lost Health: \(String(format: "%.2f", deltaHp))")
                        self.habiticaHp = result["hp"] ?? self.habiticaHp
                    }
                    await api.fetchUserData(settings: settings, silent: true)
                }
            }
        }
        updateTomato()
    }

    // MARK: - Toggle Start/Pause (快捷键 ⌘⇧P)
    // 已暂停 → 继续；番茄进行中 → 暂停；其余情况 → 启动番茄
    func togglePomodoro() {
        if isFrozen {
            unfreeze()
        } else if isRunning && phase == .pomodoro {
            freeze()
        } else {
            activate()
        }
        NotificationCenter.default.post(name: .badgeUpdate, object: nil)
    }

    // MARK: - Freeze / Unfreeze
    func freeze() {
        isFrozen = true
        pauseTimer()
        audioManager.stopAmbient()
        updateTomato()
    }

    func unfreeze() {
        isFrozen = false
        startTimer(duration: timerValue, during: { [weak self] in
            self?.duringPomodoro()
        }, end: { [weak self] in
            Task { await self?.pomodoroEnds() }
        })
        updateTomato()
    }

    // MARK: - Skip to Break
    func skipToBreak() {
        audioManager.stopAmbient()
        stopTimer()
        pomoSetCounter += 1
        startBreak()
        sendNotification(title: "Time's Up", body: "Take a break")
        isFrozen = false
        updateTomato()
    }

    // MARK: - Take Manual Break (custom duration)
    func takeBreak(duration: Int) {
        stopTimer()
        pomoSetCounter = settings.pomoSetNum
        isRunning = true
        phase = .breakTime
        startTimer(duration: duration * 60, during: { [weak self] in
            self?.duringBreak()
        }, end: { [weak self] in
            self?.breakEnds()
        })
        updateTomato()
    }

    // MARK: - Reset
    func reset() {
        audioManager.stopAmbient()
        stopTimer()
        pomoSetCounter = 0
        isFrozen = false
        updateTomato()
    }

    // MARK: - Timer core
    private func startTimer(duration: Int, during: @escaping () -> Void, end: @escaping () -> Void) {
        var remaining = duration
        timerValue = remaining
        timerString = formatTime(remaining)
        duringHandler = during
        endHandler = end
        phaseEndsAt = Date().addingTimeInterval(TimeInterval(duration))
        #if os(iOS)
        scheduleBackgroundEndNotification(after: TimeInterval(duration))
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            remaining -= 1
            self.timerValue = remaining
            self.timerString = self.formatTime(remaining)
            during()
            if remaining <= 0 {
                t.invalidate()
                self.timer = nil
                self.phaseEndsAt = nil
                #if os(iOS)
                self.cancelBackgroundEndNotification()
                #endif
                end()
            }
        }
    }

    /// iOS：应用回到前台时按 phaseEndsAt 重算剩余时间。
    /// 后台期间 Timer 被系统挂起，若不重同步，番茄会一直停在进入后台的时刻。
    func resyncAfterForeground(chain: Int = 0) {
        guard isRunning, !isFrozen, let endsAt = phaseEndsAt else { return }
        let remaining = Int(ceil(endsAt.timeIntervalSince(Date())))
        timer?.invalidate()
        timer = nil

        if remaining > 0 {
            // 阶段尚未结束：用真实剩余时间重建计时器
            timerValue = remaining
            timerString = formatTime(remaining)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard let self = self else { t.invalidate(); return }
                self.timerValue -= 1
                self.timerString = self.formatTime(max(0, self.timerValue))
                self.duringHandler?()
                if self.timerValue <= 0 {
                    t.invalidate()
                    self.timer = nil
                    self.phaseEndsAt = nil
                    self.endHandler?()
                }
            }
            return
        }

        // 后台期间阶段已结束 → 触发结束逻辑（Habitica 计分、统计、进入休息等）
        phaseEndsAt = nil
        #if os(iOS)
        cancelBackgroundEndNotification()
        #endif
        endHandler?()

        // 连锁处理（如后台跨过了 番茄结束→休息结束），限制深度避免失控
        if chain < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.resyncAfterForeground(chain: chain + 1)
            }
        }
    }

    #if os(iOS)
    // 首次启动番茄时请求通知权限（懒加载，避免启动即弹窗）
    private static var permissionRequested = false
    private func requestNotificationPermissionIfNeeded() {
        guard !Self.permissionRequested else { return }
        Self.permissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // 后台/锁屏时通过本地通知告知阶段结束（Timer 挂起时用户仍能被提醒）
    private func scheduleBackgroundEndNotification(after interval: TimeInterval) {
        cancelBackgroundEndNotification()
        let content = UNMutableNotificationContent()
        switch phase {
        case .pomodoro:
            content.title = "Time's Up"
            content.body = "番茄钟结束，休息一下 🍅"
        case .breakTime, .breakExtension:
            content.title = "Time's Up"
            content.body = "休息结束，回到工作"
        default:
            return
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let req = UNNotificationRequest(identifier: Self.backgroundEndNotificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func cancelBackgroundEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.backgroundEndNotificationId])
    }
    #endif

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        phaseEndsAt = nil
        #if os(iOS)
        cancelBackgroundEndNotification()
        #endif
        timerString = "00:00"
        isRunning = false
        phase = .idle
        isFrozen = false
        updateTomato()
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
        phaseEndsAt = nil
        #if os(iOS)
        cancelBackgroundEndNotification()
        #endif
    }

    // MARK: - Tomato state
    private func updateTomato() {
        if phase == .breakExtension {
            tomatoState = .warning
        } else if phase == .breakTime || phase == .manualBreak {
            tomatoState = phase == .manualBreak ? .win : .breakTime
        } else if phase == .pomodoro || phase == .idle && isRunning {
            tomatoState = isFrozen ? .freeze : .progress
        } else {
            tomatoState = .wait
        }
    }

    // MARK: - Helpers
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func sendNotification(title: String, body: String) {
        lastNotification = "\(title): \(body)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Init Habitica tasks
    func initHabiticaTasks() async {
        guard settings.connectHabitica else { return }
        await api.fetchUserData(settings: settings)
        pomodoroTaskId = await api.ensurePomodoroHabit(settings: settings)
        pomodoroSetTaskId = await api.ensurePomodoroSetHabit(settings: settings)
        await MainActor.run {
            self.habiticaMonies = api.monies
            self.habiticaExp = api.exp
            self.habiticaHp = api.hp
            self.habiticaConnected = api.isAuthenticated
        }
    }

    func refreshHabitica() async {
        await api.fetchUserData(settings: settings)
        await MainActor.run {
            self.habiticaMonies = api.monies
            self.habiticaExp = api.exp
            self.habiticaHp = api.hp
            self.habiticaConnected = api.isAuthenticated
        }
    }

    func loadTodayCount() {
        todayPomodoros = histogramManager.getToday()?.pomodoros ?? 0
    }
}

import Foundation
import SwiftUI
import Combine
import AVFoundation
import UserNotifications

extension Notification.Name {
    static let badgeUpdate = Notification.Name("badgeUpdate")
}

enum TimerPhase: String { case idle, pomodoro, breakTime, breakExtension, manualBreak }
enum TomatoState { case wait, progress, freeze, breakTime, win, warning }

/// One phase machine on both platforms. Local completion is synchronous; network work never owns transitions.
class PomodoroEngine: ObservableObject {
    static let shared = PomodoroEngine()
    @Published var timerString = "00:00"
    @Published var timerValue = 0
    @Published var isRunning = false
    @Published var isFrozen = false
    @Published var phase: TimerPhase = .idle
    @Published var pomoSetCounter = 0
    @Published var tomatoState: TomatoState = .wait
    @Published var todayPomodoros = 0
    @Published var habiticaMonies: Double = 0
    @Published var habiticaExp: Double = 0
    @Published var habiticaHp: Double = 0
    @Published var habiticaConnected = false
    @Published var lastNotification = ""

    private var timer: Timer?
    private var phaseRevision = 0
    private var foregroundRecovery: UUID?
    private var endHandler: ((Date) -> Void)?
    private(set) var phaseEndsAt: Date?
    private var phaseDuration = 0

    /// Display-only progress of the current phase (0...1). Never used for scheduling.
    var phaseProgress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - Double(timerValue) / Double(phaseDuration)))
    }
    private var lastTickAt: Date?
    private var activePomodoroSettings: UserSettings?
    private var activeBreakSettings: UserSettings?
    private var activeBreakExtensionSettings: UserSettings?
    private var completedSet = false
    private var customBreak = false
    private var pendingBreakSeconds = 0
    private var pomodoroTaskId: String?
    private var pomodoroSetTaskId: String?
    private var taskAccountSignature = ""
    private var settingsSubscription: AnyCancellable?
    private let api = HabiticaAPI.shared
    private let settingsManager = SettingsManager.shared
    private let audioManager = AudioManager.shared
    private let histogramManager = HistogramManager.shared

    #if os(iOS)
    static let backgroundEndNotificationId = "pomo-phase-end"
    #endif
    var settings: UserSettings { settingsManager.settings }

    init() {
        settingsSubscription = settingsManager.$settings
            .map { [weak self] in "\(self?.accountSignature($0) ?? "")|\($0.connectHabitica)" }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.pomodoroTaskId = nil
                self.pomodoroSetTaskId = nil
                self.taskAccountSignature = ""
                self.habiticaMonies = 0
                self.habiticaExp = 0
                self.habiticaHp = 0
                self.habiticaConnected = false
                self.api.monies = 0
                self.api.exp = 0
                self.api.hp = 0
                self.api.isAuthenticated = false
                self.api.lastError = nil
            }
        NotificationCenter.default.addObserver(forName: .histogramChanged, object: nil, queue: .main) { [weak self] _ in
            self?.loadTodayCount()
        }
    }

    func activate() {
        if isFrozen { unfreeze() }
        else if phase == .manualBreak { startBreak() }
        else if !isRunning || phase == .breakTime || phase == .breakExtension { startPomodoro() }
        else { pomodoroInterrupted(breakStreak: true) }
    }

    func togglePomodoro() {
        if isFrozen { unfreeze() }
        else if isRunning && phase == .pomodoro { freeze() }
        else { activate() }
        notifyBadge()
    }

    func startPomodoro() {
        guard phase != .pomodoro else { return }
        #if os(iOS)
        requestNotificationPermissionIfNeeded()
        #endif
        if completedSet { pomoSetCounter = 0 }
        completedSet = false
        customBreak = false
        let configuration = phaseSnapshot(settings)
        activePomodoroSettings = configuration
        activeBreakSettings = nil
        activeBreakExtensionSettings = nil
        beginPhase(.pomodoro, duration: configuration.pomoDurationMins * 60) { [weak self] date in
            self?.completePomodoro(at: date)
        }
        audioManager.playAmbientFor(settings: configuration, newSession: true)
    }

    /// Compatibility entry point; duplicate callbacks after a transition cannot count twice.
    func pomodoroEnds() async {
        await MainActor.run { self.completePomodoro(at: self.phaseEndsAt ?? Date()) }
    }

    private func completePomodoro(at date: Date) {
        guard foregroundRecovery == nil, phase == .pomodoro, !isFrozen,
              let configuration = activePomodoroSettings else { return }
        activePomodoroSettings = nil
        stopTimer()
        audioManager.stopAmbient()
        histogramManager.incrementToday(pomodoros: 1, minutes: configuration.pomoDurationMins, date: date)
        loadTodayCount()
        pomoSetCounter += 1
        completedSet = pomoSetCounter >= configuration.pomoSetNum
        pendingBreakSeconds = (completedSet ? configuration.longBreakDuration : configuration.breakDuration) * 60
        activeBreakSettings = configuration
        var message = "Pomodoro ended.\nYou have done \(todayPomodoros) today!"
        var rewardBlock: Int?
        var rewardGoal = ""
        if configuration.enableBlockMode {
            let manager = BlockProgressManager.shared
            manager.recordPomoInCurrentBlock(settings: configuration, comboCompleted: completedSet, date: date)
            let index = manager.blockProgress.currentBlockIndex
            let progress = manager.progress(settings: configuration, date: date)
            let count = progress.indices.contains(index) ? progress[index] : 0
            rewardGoal = manager.blockProgress.getBlockGoal(goals: configuration.blockGoals)
            if count >= configuration.blockPomoCount && manager.recordBlockComplete(settings: configuration, date: date) {
                rewardBlock = index
                message = "Block \(index + 1) Complete! 🎉\nGoal: \(rewardGoal)\n\(BlockRewardManager.shared.suggestBreakType(settings: configuration, blockIndex: index))"
            } else {
                message = "Pomodoro ended.\nCurrent Block (\(index + 1)): \(count)/\(configuration.blockPomoCount)\nGoal: \(rewardGoal)"
            }
            BlockNotificationManager.shared.checkReminders(settings: configuration)
        }
        sendNotification(title: completedSet ? "Pomodoro Set Complete!" : "Time's Up", body: message)
        audioManager.playSound(configuration.pomoEndSound, volume: configuration.pomoEndSoundVolume)
        let setComplete = completedSet
        // Advance before awaiting anything: offline/slow scoring must never delay the break or resurrect a reset.
        if configuration.manualBreak { manualBreak() }
        else { startBreak(at: date) }
        Task {
            guard var requestSettings = self.phaseRequestSettings(configuration) else { return }
            let signature = self.accountSignature(configuration)
            let pomoId = signature == self.taskAccountSignature ? self.pomodoroTaskId : nil
            let setId = signature == self.taskAccountSignature ? self.pomodoroSetTaskId : nil
            let needsPomo = configuration.pomoHabitPlus || (rewardBlock != nil && configuration.blockRewardEnabled)
            var resolvedPomo: String? = pomoId
            if needsPomo && resolvedPomo == nil { resolvedPomo = await self.api.ensurePomodoroHabit(settings: requestSettings) }
            if configuration.pomoHabitPlus, let id = resolvedPomo {
                guard let refreshed = self.phaseRequestSettings(configuration) else { return }
                requestSettings = refreshed
                _ = await self.api.scoreHabit(taskId: id, direction: "up", settings: requestSettings)
            }
            if setComplete && configuration.pomoSetHabitPlus {
                guard let refreshed = self.phaseRequestSettings(configuration) else { return }
                requestSettings = refreshed
                var resolved = setId
                if resolved == nil { resolved = await self.api.ensurePomodoroSetHabit(settings: requestSettings) }
                if let id = resolved, let refreshed = self.phaseRequestSettings(configuration) {
                    _ = await self.api.scoreHabit(taskId: id, direction: "up", settings: refreshed)
                }
            }
            if let index = rewardBlock, let refreshed = self.phaseRequestSettings(configuration) {
                await BlockRewardManager.shared.sendBlockReward(settings: refreshed, blockIndex: index, blockGoal: rewardGoal, habitId: resolvedPomo)
            }
            await self.refreshHabitica()
        }
    }

    func startBreak() { startBreak(at: Date()) }
    private func startBreak(at date: Date) {
        let configuration = activeBreakSettings ?? phaseSnapshot(settings)
        activeBreakSettings = configuration
        activeBreakExtensionSettings = nil
        audioManager.stopAmbient()
        let duration = pendingBreakSeconds > 0 ? pendingBreakSeconds : (completedSet ? configuration.longBreakDuration : configuration.breakDuration) * 60
        beginPhase(.breakTime, duration: duration, startingAt: date) { [weak self] date in
            self?.finishBreak(at: date)
        }
    }

    func manualBreak() {
        stopTimer()
        phase = .manualBreak
        timerString = "GOOD!"
        updateTomato()
        notifyBadge()
    }

    func breakEnds() { finishBreak(at: phaseEndsAt ?? Date()) }
    private func finishBreak(at date: Date) {
        guard foregroundRecovery == nil, phase == .breakTime else { return }
        let isLong = completedSet || customBreak
        let breakConfiguration = activeBreakSettings ?? phaseSnapshot(settings)
        activeBreakSettings = nil
        stopTimer()
        if isLong {
            if completedSet { pomoSetCounter = 0 }
            completedSet = false
            customBreak = false
            pendingBreakSeconds = 0
            if breakConfiguration.longBreakNotify {
                Task {
                    guard let configuration = self.phaseRequestSettings(breakConfiguration) else { return }
                    await api.sendPrivateMessage("Long Break is over", settings: configuration)
                }
            }
        } else {
            // Remind once at short-break completion, including zero grace. Not at grace startup.
            if breakConfiguration.breakExtentionNotify {
                let minutes = breakConfiguration.breakExtention
                Task {
                    guard let configuration = self.phaseRequestSettings(breakConfiguration) else { return }
                    let message = minutes > 0 ? "Back to work! \(minutes) minutes left for Break Extension." : "Back to work!"
                    await api.sendPrivateMessage(message, settings: configuration)
                }
            }
            if breakConfiguration.breakExtention > 0 {
                startBreakExtension(duration: breakConfiguration.breakExtention * 60, at: date, configuration: breakConfiguration)
            } else {
                // No grace countdown and no failure: preserve the earned combo.
                timerString = "GO!"
                pendingBreakSeconds = 0
            }
        }
        sendNotification(title: "Time's Up", body: isLong ? "Break is over" : "Back to work")
        audioManager.playSound(breakConfiguration.breakEndSound, volume: breakConfiguration.breakEndSoundVolume)
        updateTomato()
        notifyBadge()
    }

    func startBreakExtension(duration: Int) {
        startBreakExtension(duration: duration, at: Date(), configuration: phaseSnapshot(settings))
    }
    private func startBreakExtension(duration: Int, at date: Date, configuration: UserSettings) {
        guard duration > 0 else {
            activeBreakExtensionSettings = nil
            stopTimer()
            timerString = "GO!"
            return
        }
        activeBreakExtensionSettings = configuration
        pendingBreakSeconds = 0
        beginPhase(.breakExtension, duration: duration, startingAt: date) { [weak self] _ in
            guard let self = self else { return }
            self.pomodoroInterrupted(breakStreak: configuration.resetPomoAfterBreak)
        }

    }

    func pomodoroInterrupted(breakStreak: Bool) {
        let interruptedFocus = phase == .pomodoro
        guard interruptedFocus || phase == .breakExtension else { return }
        let configuration = (interruptedFocus ? activePomodoroSettings : activeBreakExtensionSettings) ?? phaseSnapshot(settings)
        let failedExtension = phase == .breakExtension && configuration.breakExtentionFails
        if interruptedFocus && configuration.enableBlockMode {
            BlockProgressManager.shared.recordAbandonedPomo(settings: configuration)
        }
        activePomodoroSettings = nil
        activeBreakSettings = nil
        activeBreakExtensionSettings = nil
        audioManager.stopAmbient()
        stopTimer()
        pendingBreakSeconds = 0
        if breakStreak { pomoSetCounter = 0; completedSet = false }
        else { timerString = "GO!" }
        if (interruptedFocus && configuration.pomoHabitMinus) || failedExtension {
            Task {
                guard let requestSettings = self.phaseRequestSettings(configuration) else { return }
                if let id = await api.ensurePomodoroHabit(settings: requestSettings),
                   let refreshed = self.phaseRequestSettings(configuration) {
                    _ = await api.scoreHabit(taskId: id, direction: "down", settings: refreshed)
                    await refreshHabitica()
                }
            }
        }
        updateTomato()
        notifyBadge()
    }

    func freeze() {
        guard isRunning, !isFrozen, phaseEndsAt != nil else { return }
        tick(at: Date())
        guard isRunning, phaseEndsAt != nil else { return }
        phaseRevision += 1
        timer?.invalidate()
        timer = nil
        phaseEndsAt = nil
        isFrozen = true
        audioManager.pauseAmbient()
        #if os(iOS)
        cancelBackgroundEndNotification()
        #endif
        updateTomato()
        notifyBadge()
    }

    func unfreeze() {
        guard isFrozen, let handler = endHandler else { return }
        isFrozen = false
        // Preserve the handler belonging to the paused phase; a break must never complete a pomodoro.
        beginPhase(phase, duration: timerValue, end: handler)
        if phase == .pomodoro, let configuration = activePomodoroSettings {
            audioManager.playAmbientFor(settings: configuration, newSession: false)
        }
    }

    func skipToBreak() {
        guard phase == .pomodoro else { return }
        let skippedConfiguration = activePomodoroSettings ?? phaseSnapshot(settings)
        if skippedConfiguration.enableBlockMode {
            BlockProgressManager.shared.recordAbandonedPomo(settings: skippedConfiguration)
        }
        activePomodoroSettings = nil
        audioManager.stopAmbient()
        pomoSetCounter = 0
        completedSet = false
        customBreak = false
        pendingBreakSeconds = skippedConfiguration.breakDuration * 60
        activeBreakSettings = skippedConfiguration
        startBreak()
        sendNotification(title: "Time's Up", body: "Take a break")
    }

    /// Idle-only custom breaks do not fabricate a completed set or clear earned combo progress.
    func takeBreak(duration: Int) {
        guard phase == .idle, !isRunning, !isFrozen, duration > 0 else { return }
        #if os(iOS)
        requestNotificationPermissionIfNeeded()
        #endif
        customBreak = true
        pendingBreakSeconds = duration * 60
        activeBreakSettings = phaseSnapshot(settings)
        startBreak()
    }

    func reset() {
        audioManager.stopAmbient()
        stopTimer()
        activePomodoroSettings = nil
        activeBreakSettings = nil
        activeBreakExtensionSettings = nil
        pomoSetCounter = 0
        completedSet = false
        customBreak = false
        pendingBreakSeconds = 0
        notifyBadge()
    }

    private func beginPhase(_ next: TimerPhase, duration: Int, startingAt date: Date = Date(), end: @escaping (Date) -> Void) {
        phaseRevision += 1
        timer?.invalidate()
        timer = nil
        phase = next
        isRunning = true
        isFrozen = false
        phaseDuration = max(1, duration)
        timerValue = phaseDuration
        timerString = formatTime(timerValue)
        endHandler = end
        phaseEndsAt = date.addingTimeInterval(TimeInterval(phaseDuration))
        lastTickAt = date
        #if os(iOS)
        scheduleBackgroundEndNotification(after: max(1, phaseEndsAt!.timeIntervalSinceNow))
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick(at: Date()) }
        updateTomato()
        notifyBadge()
    }

    private func tick(at date: Date) {
        guard isRunning, !isFrozen, let deadline = phaseEndsAt else { return }
        let raw = Int(ceil(deadline.timeIntervalSince(date)))
        if (lastTickAt.map { date < $0 } ?? false) || raw > phaseDuration {
            // Any observed wall-clock rollback rebases to the already displayed remaining time.
            // Checking only the configured duration would still permit smaller rollbacks to add time.
            phaseEndsAt = date.addingTimeInterval(TimeInterval(timerValue))
            lastTickAt = date
            #if os(iOS)
            scheduleBackgroundEndNotification(after: TimeInterval(timerValue))
            #endif
            return
        }
        lastTickAt = date
        timerValue = max(0, raw)
        timerString = formatTime(timerValue)
        if timerValue == 0 {
            // Keep displaying elapsed time, but even a real scheduled Timer may not
            // settle against stale stores while foreground reads own recovery.
            guard foregroundRecovery == nil else { updateTomato(); notifyBadge(); return }
            let handler = endHandler
            timer?.invalidate()
            timer = nil
            phaseEndsAt = nil
            endHandler = nil
            #if os(iOS)
            cancelBackgroundEndNotification()
            #endif
            handler?(deadline)
        } else if phase == .pomodoro, let configuration = activePomodoroSettings {
            audioManager.playAmbientFor(settings: configuration, newSession: false)
        }
        updateTomato()
        notifyBadge()
    }

    /// One foreground boundary for both platforms: accept the asynchronous snapshot
    /// before any elapsed phase can write. Production samples the clock at completion;
    /// an explicit `now` is only a deterministic caller clock (used by CLI fixtures).
    func resyncAfterForeground(chain: Int = 0, now: Date? = nil, completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.resyncAfterForeground(chain: chain, now: now, completion: completion) }
            return
        }
        let monitor = PomodoroFileChanges.shared
        let directory = monitor.directoryIdentity()
        let phaseRevision = self.phaseRevision
        let recovery = UUID()
        foregroundRecovery = recovery
        monitor.syncFromDiskIfNeeded { [weak self] in
            defer { completion?() }
            guard let self = self, self.foregroundRecovery == recovery else { return }
            let samePhase = self.phaseRevision == phaseRevision
            let sameDirectory = monitor.directoryIdentity() == directory
            if samePhase && !sameDirectory {
                // Never let the next scheduled tick settle the old folder's elapsed
                // phase into the new folder. A user may explicitly resume it later.
                self.freeze()
            }
            self.foregroundRecovery = nil
            guard samePhase, sameDirectory else { return }
            self.catchUpElapsedPhases(at: now ?? Date())
        }
    }

    /// Catch up elapsed work → break → grace, never invent unattended focus sessions.
    private func catchUpElapsedPhases(at now: Date) {
        for _ in 0..<6 {
            guard isRunning, !isFrozen, let deadline = phaseEndsAt else { break }
            tick(at: now)
            if deadline > now { break }
        }
        loadTodayCount()
    }

    private func stopTimer() {
        phaseRevision += 1
        timer?.invalidate()
        timer = nil
        phaseEndsAt = nil
        endHandler = nil
        lastTickAt = nil
        timerString = "00:00"
        timerValue = 0
        isRunning = false
        phase = .idle
        isFrozen = false
        #if os(iOS)
        cancelBackgroundEndNotification()
        #endif
        updateTomato()
    }

    private func updateTomato() {
        if isFrozen { tomatoState = .freeze }
        else if phase == .breakExtension { tomatoState = .warning }
        else if phase == .manualBreak { tomatoState = .win }
        else if phase == .breakTime { tomatoState = .breakTime }
        else if phase == .pomodoro { tomatoState = .progress }
        else { tomatoState = .wait }
    }
    private func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
    private func notifyBadge() { NotificationCenter.default.post(name: .badgeUpdate, object: nil) }
    private func sendNotification(title: String, body: String) {
        lastNotification = "\(title): \(body)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func accountSignature(_ settings: UserSettings) -> String {
        "\(api.cloudAccount(settings: settings) ?? "")|\(settings.customPomodoroTask)|\(settings.pomodoroTaskId ?? "")|\(settings.customSetTask)|\(settings.pomodoroSetTaskId ?? "")"
    }

    /// Business snapshots retain connection intent and owner/IDs, never credentials.
    private func phaseSnapshot(_ configuration: UserSettings) -> UserSettings {
        var snapshot = configuration
        snapshot.apiToken = ""
        return snapshot
    }

    /// Both captured and current connection intent must allow the same UID/API owner's current key.
    private func phaseRequestSettings(_ phaseSettings: UserSettings) -> UserSettings? {
        let current = settings
        guard phaseSettings.connectHabitica, current.connectHabitica, !current.apiToken.isEmpty,
              let owner = api.cloudAccount(settings: phaseSettings), owner == api.cloudAccount(settings: current) else { return nil }
        var request = phaseSettings
        request.apiToken = current.apiToken
        request.developerServerUrl = current.developerServerUrl
        return request
    }
    func initHabiticaTasks() async {
        let configuration = settings
        let signature = accountSignature(configuration)
        guard configuration.connectHabitica, !configuration.uid.isEmpty, !configuration.apiToken.isEmpty else {
            await MainActor.run { self.habiticaConnected = false }
            return
        }
        await api.fetchUserData(settings: configuration)
        let pomo = await api.ensurePomodoroHabit(settings: configuration)
        let combo = await api.ensurePomodoroSetHabit(settings: configuration)
        await MainActor.run {
            guard self.accountSignature(self.settings) == signature else { return }
            self.pomodoroTaskId = pomo
            self.pomodoroSetTaskId = combo
            self.taskAccountSignature = signature
            self.updateHabiticaState()
        }
    }
    func refreshHabitica() async {
        let configuration = settings
        let signature = accountSignature(configuration)
        await api.fetchUserData(settings: configuration)
        await MainActor.run {
            guard self.accountSignature(self.settings) == signature else { return }
            self.updateHabiticaState()
        }
    }
    private func updateHabiticaState() {
        habiticaMonies = api.monies
        habiticaExp = api.exp
        habiticaHp = api.hp
        habiticaConnected = api.isAuthenticated
    }
    func loadTodayCount() { todayPomodoros = histogramManager.getToday()?.pomodoros ?? 0 }

    #if os(iOS)
    private static var permissionRequested = false
    private func requestNotificationPermissionIfNeeded() {
        guard !Self.permissionRequested else { return }
        Self.permissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    BlockNotificationManager.shared.startReminderTimer(settings: SettingsManager.shared.settings)
                }
            }
        }
    }
    private func scheduleBackgroundEndNotification(after interval: TimeInterval) {
        cancelBackgroundEndNotification()
        let content = UNMutableNotificationContent()
        content.title = "Time's Up"
        content.body = phase == .pomodoro ? "番茄钟结束，休息一下 🍅" : "休息结束，回到工作"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.backgroundEndNotificationId, content: content, trigger: trigger))
    }
    private func cancelBackgroundEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.backgroundEndNotificationId])
    }
    #endif
}

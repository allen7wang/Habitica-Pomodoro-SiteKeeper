import Foundation
import UserNotifications

// MARK: - Block Notification Manager (块通知管理)
class BlockNotificationManager: ObservableObject {
    static let shared = BlockNotificationManager()

    private var reminderTimer: Timer?
    private var lastSprintKey: String?
    #if os(iOS)
    private static let notificationPrefix = "block-start-"
    private var schedulingSignature: String?
    private var schedulingGeneration = 0
    #else
    private var lastStartDay = ""
    private var sentStartBlocks = Set<Int>()
    #endif

    private init() {}

    // Sprint reminders still depend on actual progress; iOS block-start reminders are scheduled separately.
    func checkReminders(settings: UserSettings) {
        guard settings.enableBlockMode else { return }
        guard settings.blockStartReminder || settings.blockSprintReminder else { return }

        #if os(macOS)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let currentMinutes = hour * 60 + minute
        let day = calendar.startOfDay(for: Date()).description
        if day != lastStartDay {
            lastStartDay = day
            sentStartBlocks.removeAll()
        }

        for (index, range) in settings.blockTimeRanges.prefix(max(0, settings.blockCount)).enumerated() {
            if settings.blockStartReminder {
                let reminderMinutes = ((range.startMinutes - settings.blockReminderMinutes) % 1440 + 1440) % 1440
                if currentMinutes == reminderMinutes && !sentStartBlocks.contains(index) {
                    sentStartBlocks.insert(index)
                    sendBlockStartReminder(
                        blockIndex: index, timeRange: range,
                        goal: index < settings.blockGoals.count ? settings.blockGoals[index] : "",
                        settings: settings
                    )
                }
            }
        }
        #endif

        if settings.blockSprintReminder {
            checkSprintReminder(settings: settings)
        }
    }

    private func checkSprintReminder(settings: UserSettings) {
        BlockProgressManager.shared.updateBlockIndexFromTime(settings: settings)
        let currentBlockIdx = BlockProgressManager.shared.blockProgress.currentBlockIndex
        guard currentBlockIdx >= 0, currentBlockIdx < settings.blockCount,
              currentBlockIdx < settings.blockTimeRanges.count else { return }

        let progress = BlockProgressManager.shared.getTodayBlockProgress(settings: settings)
        let completed = currentBlockIdx < progress.count ? progress[currentBlockIdx] : 0
        let key = "\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)-\(currentBlockIdx)"
        #if os(iOS)
        let alreadySent = UserDefaults.standard.string(forKey: "block_sprint_last_sent") == key
        #else
        let alreadySent = lastSprintKey == key
        #endif
        let threshold = max(1, (settings.blockPomoCount * 2 + 2) / 3)
        if completed >= threshold && completed < settings.blockPomoCount && !alreadySent {
            lastSprintKey = key
            #if os(iOS)
            UserDefaults.standard.set(key, forKey: "block_sprint_last_sent")
            #endif
            sendSprintReminder(
                blockIndex: currentBlockIdx, completed: completed, total: settings.blockPomoCount,
                goal: currentBlockIdx < settings.blockGoals.count ? settings.blockGoals[currentBlockIdx] : ""
            )
        }
    }

    #if os(macOS)
    private func sendBlockStartReminder(blockIndex: Int, timeRange: BlockTimeRange, goal: String, settings: UserSettings) {
        let content = UNMutableNotificationContent()
        content.title = "Block \(blockIndex + 1) Starting Soon!"
        content.body = "Starting in \(settings.blockReminderMinutes) minutes (\(timeRange.displayString))"
        if !goal.isEmpty {
            content.body += "\nGoal: \(goal)"
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
    #endif

    private func sendSprintReminder(blockIndex: Int, completed: Int, total: Int, goal: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sprint Time! 🚀"
        content.body = "Block \(blockIndex + 1): \(completed)/\(total) pomodoros complete"
        if !goal.isEmpty {
            content.body += "\nGoal: \(goal)"
        }
        content.body += "\nAlmost there! Keep going!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    func startReminderTimer(settings: UserSettings) {
        #if os(iOS)
        refreshScheduledReminders(settings: settings, force: true)
        #else
        reminderTimer?.invalidate()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkReminders(settings: SettingsManager.shared.settings)
        }
        #endif
    }

    func stopReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        #if os(iOS)
        schedulingSignature = nil
        schedulingGeneration += 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (0..<24).map { Self.notificationPrefix + String($0) }
        )
        #endif
    }

    #if os(iOS)
    /// Invoked only by a user changing block reminder settings, never during app launch.
    func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { permission in
            guard permission.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        self.refreshScheduledReminders(settings: SettingsManager.shared.settings, force: true)
                    }
                }
            }
        }
    }

    /// Rebuild daily calendar requests when relevant settings change or the app reopens.
    /// Stable IDs replace obsolete schedules; the in-process timer never sends block-start alerts on iOS.
    func refreshScheduledReminders(settings: UserSettings, force: Bool = false) {
        let ranges = settings.blockTimeRanges.prefix(max(0, min(settings.blockCount, 24)))
        let signature = "\(settings.enableBlockMode)|\(settings.blockStartReminder)|\(settings.blockCount)|\(settings.blockReminderMinutes)|" +
            ranges.enumerated().map { index, range in
                "\(range.startHour):\(range.startMinute):\(index < settings.blockGoals.count ? settings.blockGoals[index] : "")"
            }.joined(separator: "|")
        guard force || signature != schedulingSignature else { return }
        schedulingSignature = signature
        schedulingGeneration += 1
        let generation = schedulingGeneration
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<24).map { Self.notificationPrefix + String($0) }
        )
        guard settings.enableBlockMode && settings.blockStartReminder else { return }
        center.getNotificationSettings { [weak self] permission in
            DispatchQueue.main.async {
                guard let self = self, self.schedulingGeneration == generation,
                      permission.authorizationStatus == .authorized ||
                      permission.authorizationStatus == .provisional else { return }
                for (index, range) in ranges.enumerated() {
                    let minutes = ((range.startMinutes - settings.blockReminderMinutes) % 1440 + 1440) % 1440
                    let content = UNMutableNotificationContent()
                    content.title = "Block \(index + 1) Starting Soon!"
                    content.body = "Starting in \(settings.blockReminderMinutes) minutes (\(range.displayString))"
                    if index < settings.blockGoals.count, !settings.blockGoals[index].isEmpty {
                        content.body += "\nGoal: \(settings.blockGoals[index])"
                    }
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true
                    )
                    center.add(UNNotificationRequest(
                        identifier: Self.notificationPrefix + String(index), content: content, trigger: trigger
                    ))
                }
            }
        }
    }
    #endif
}

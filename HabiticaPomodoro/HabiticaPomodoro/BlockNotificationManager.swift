import Foundation
import UserNotifications

// MARK: - Block Notification Manager (块通知管理)
class BlockNotificationManager: ObservableObject {
    static let shared = BlockNotificationManager()
    
    private var reminderTimer: Timer?
    private var lastCheckedBlock: Int = -1
    
    private init() {}
    
    // 检查并发送提醒
    func checkReminders(settings: UserSettings) {
        guard settings.enableBlockMode else { return }
        guard settings.blockStartReminder || settings.blockSprintReminder else { return }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let currentMinutes = hour * 60 + minute
        
        // 检查每个块
        for (index, range) in settings.blockTimeRanges.enumerated() {
            let blockStartMinutes = range.startMinutes
            
            // 块开始前提醒
            if settings.blockStartReminder {
                let reminderMinutes = blockStartMinutes - settings.blockReminderMinutes
                if currentMinutes == reminderMinutes && currentMinutes > 0 {
                    sendBlockStartReminder(
                        blockIndex: index,
                        timeRange: range,
                        goal: index < settings.blockGoals.count ? settings.blockGoals[index] : "",
                        settings: settings
                    )
                }
            }
        }
        
        // 检查冲刺提醒
        if settings.blockSprintReminder {
            checkSprintReminder(settings: settings)
        }
    }
    
    // 检查冲刺提醒
    private func checkSprintReminder(settings: UserSettings) {
        let currentBlockIdx = BlockProgressManager.shared.blockProgress.currentBlockIndex
        guard currentBlockIdx < settings.blockTimeRanges.count else { return }
        
        let progress = BlockProgressManager.shared.getTodayBlockProgress(settings: settings)
        let completed = currentBlockIdx < progress.count ? progress[currentBlockIdx] : 0
        let total = settings.blockPomoCount
        
        // 4/6 提醒
        if completed == 4 && total == 6 && currentBlockIdx != lastCheckedBlock {
            sendSprintReminder(
                blockIndex: currentBlockIdx,
                goal: currentBlockIdx < settings.blockGoals.count ? settings.blockGoals[currentBlockIdx] : ""
            )
            lastCheckedBlock = currentBlockIdx
        }
    }
    
    // 发送块开始提醒
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
    
    // 发送冲刺提醒
    private func sendSprintReminder(blockIndex: Int, goal: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sprint Time! 🚀"
        content.body = "Block \(blockIndex + 1): 4/6 pomodoros complete"
        if !goal.isEmpty {
            content.body += "\nGoal: \(goal)"
        }
        content.body += "\nAlmost there! Keep going!"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
    
    // 开始定时检查提醒
    func startReminderTimer(settings: UserSettings) {
        reminderTimer?.invalidate()
        
        guard settings.enableBlockMode else { return }
        
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkReminders(settings: settings)
        }
    }
    
    // 停止提醒定时器
    func stopReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }
}
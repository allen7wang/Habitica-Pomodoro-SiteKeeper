import Foundation

// MARK: - Block Reward Manager (块奖励管理)
class BlockRewardManager {
    static let shared = BlockRewardManager()
    
    private let habiticaAPI = HabiticaAPI.shared
    
    // 块完成后发送奖励
    func sendBlockReward(settings: UserSettings, blockIndex: Int, blockGoal: String) async {
        guard settings.blockRewardEnabled else { return }
        guard settings.connectHabitica else { return }
        
        let taskTitle = "Block \(blockIndex + 1) Complete"
        let taskNote = "Completed block with goal: \(blockGoal.isEmpty ? "None" : blockGoal)"
        
        // 使用现有的 pomodoro habit 来奖励（可以扩展为专用 habit）
        let habitId = settings.pomodoroTaskId
        guard let hid = habitId else { return }
        
        if let result = await habiticaAPI.scoreHabit(
            taskId: hid,
            direction: "up",
            settings: settings
        ) {
            print("Block reward sent: +\(result["gp"] ?? 0) gold, +\(result["exp"] ?? 0) exp")
        }
    }
    
    // 块间休息建议
    func suggestBreakType(settings: UserSettings, blockIndex: Int) -> String {
        let nextBlockIndex = (blockIndex + 1) % settings.blockCount
        
        // 如果下一个块即将开始（1 分钟内），建议短休息
        if nextBlockIndex < settings.blockTimeRanges.count {
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let currentMinutes = hour * 60 + minute
            
            let nextBlock = settings.blockTimeRanges[nextBlockIndex]
            let minutesUntilNext = nextBlock.startMinutes - currentMinutes
            
            if minutesUntilNext > 0 && minutesUntilNext <= 10 {
                return "Short break (2 min) - Next block starts soon"
            }
        }
        
        // 每 2 个块后建议长休息
        if (blockIndex + 1) % 2 == 0 {
            return "Long break (15-20 min) - You've worked hard!"
        }
        
        return "Normal break (5-10 min)"
    }
}
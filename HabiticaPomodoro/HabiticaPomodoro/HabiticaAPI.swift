import Foundation

// MARK: - User Settings (mirrors the extension's UserSettings)
struct UserSettings: Codable {
    var uid: String = ""
    var apiToken: String = ""
    var connectHabitica: Bool = true
    var pomoDurationMins: Int = 25
    var breakDuration: Int = 5
    var breakExtention: Int = 2
    var longBreakDuration: Int = 30
    var pomoSetNum: Int = 4
    var manualBreak: Bool = true
    var breakFreePass: Bool = false
    var breakExtentionFails: Bool = false
    var breakExtentionNotify: Bool = false
    var resetPomoAfterBreak: Bool = false
    var longBreakNotify: Bool = false
    var vacationMode: Bool = false
    var pomoHabitPlus: Bool = false
    var pomoHabitMinus: Bool = false
    var pomoSetHabitPlus: Bool = false
    var customPomodoroTask: Bool = false
    var customSetTask: Bool = false
    var pomodoroTaskId: String? = nil
    var pomodoroSetTaskId: String? = nil
    var pomoEndSound: String = "None"
    var breakEndSound: String = "None"
    var ambientSound: String = "None"
    var pomoEndSoundVolume: Double = 0.5
    var breakEndSoundVolume: Double = 0.5
    var ambientSoundVolume: Double = 0.5
    /// 环境音来源："custom" = 内置环境音（老方案）；"qishi" = 每个番茄随机播放一个栖时场景混音
    var ambientSource: String = "custom"
    var developerServerUrl: String = ""

    // MARK: - Block Settings (时间块功能)
    var enableBlockMode: Bool = false // 启用时间块模式
    var blockCount: Int = 8 // 每天分几块（默认 8 块）
    var blockPomoCount: Int = 6 // 每块几个 pomo（默认 6 个）
    var blockGoals: [String] = [] // 每块的目标（可选）
    var blockTimeRanges: [BlockTimeRange] = [] // 每块的时间范围（如 4:00-7:00）
    var blockTasks: [[BlockTask]] = [] // 每块的任务列表
    var blockRewardEnabled: Bool = true // 块完成后 Habitica 奖励
    var blockSprintReminder: Bool = true // 块进度 4/6 时提醒冲刺
    var blockStartReminder: Bool = true // 块开始前 5 分钟提醒
    var blockReminderMinutes: Int = 5 // 块开始前提醒分钟数

    init() {
        // 初始化默认块时间范围（4:00 开始，每块 3 小时）
        blockTimeRanges = [
            BlockTimeRange(startHour: 4, startMinute: 0, endHour: 7, endMinute: 0),   // 4:00-7:00
            BlockTimeRange(startHour: 7, startMinute: 0, endHour: 10, endMinute: 0),  // 7:00-10:00
            BlockTimeRange(startHour: 10, startMinute: 0, endHour: 13, endMinute: 0),  // 10:00-13:00
            BlockTimeRange(startHour: 13, startMinute: 0, endHour: 16, endMinute: 0),  // 13:00-16:00
            BlockTimeRange(startHour: 16, startMinute: 0, endHour: 19, endMinute: 0),  // 16:00-19:00
            BlockTimeRange(startHour: 19, startMinute: 0, endHour: 22, endMinute: 0),  // 19:00-22:00
            BlockTimeRange(startHour: 22, startMinute: 0, endHour: 1, endMinute: 0),   // 22:00-01:00
            BlockTimeRange(startHour: 1, startMinute: 0, endHour: 4, endMinute: 0),    // 01:00-04:00
        ]
        
        // 初始化默认块任务列表
        blockTasks = Array(repeating: [], count: 8)
        normalize()
    }

    enum CodingKeys: String, CodingKey { case uid, apiToken, connectHabitica, pomoDurationMins, breakDuration, breakExtention, longBreakDuration, pomoSetNum, manualBreak, breakFreePass, breakExtentionFails, breakExtentionNotify, resetPomoAfterBreak, longBreakNotify, vacationMode, pomoHabitPlus, pomoHabitMinus, pomoSetHabitPlus, customPomodoroTask, customSetTask, pomodoroTaskId, pomodoroSetTaskId, pomoEndSound, breakEndSound, ambientSound, pomoEndSoundVolume, breakEndSoundVolume, ambientSoundVolume, ambientSource, developerServerUrl, enableBlockMode, blockCount, blockPomoCount, blockGoals, blockTimeRanges, blockTasks, blockRewardEnabled, blockSprintReminder, blockStartReminder, blockReminderMinutes }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? uid
        apiToken = try c.decodeIfPresent(String.self, forKey: .apiToken) ?? apiToken
        connectHabitica = try c.decodeIfPresent(Bool.self, forKey: .connectHabitica) ?? connectHabitica
        pomoDurationMins = try c.decodeIfPresent(Int.self, forKey: .pomoDurationMins) ?? pomoDurationMins
        breakDuration = try c.decodeIfPresent(Int.self, forKey: .breakDuration) ?? breakDuration
        breakExtention = try c.decodeIfPresent(Int.self, forKey: .breakExtention) ?? breakExtention
        longBreakDuration = try c.decodeIfPresent(Int.self, forKey: .longBreakDuration) ?? longBreakDuration
        pomoSetNum = try c.decodeIfPresent(Int.self, forKey: .pomoSetNum) ?? pomoSetNum
        manualBreak = try c.decodeIfPresent(Bool.self, forKey: .manualBreak) ?? manualBreak
        breakFreePass = try c.decodeIfPresent(Bool.self, forKey: .breakFreePass) ?? breakFreePass
        breakExtentionFails = try c.decodeIfPresent(Bool.self, forKey: .breakExtentionFails) ?? breakExtentionFails
        breakExtentionNotify = try c.decodeIfPresent(Bool.self, forKey: .breakExtentionNotify) ?? breakExtentionNotify
        resetPomoAfterBreak = try c.decodeIfPresent(Bool.self, forKey: .resetPomoAfterBreak) ?? resetPomoAfterBreak
        longBreakNotify = try c.decodeIfPresent(Bool.self, forKey: .longBreakNotify) ?? longBreakNotify
        vacationMode = try c.decodeIfPresent(Bool.self, forKey: .vacationMode) ?? vacationMode
        pomoHabitPlus = try c.decodeIfPresent(Bool.self, forKey: .pomoHabitPlus) ?? pomoHabitPlus
        pomoHabitMinus = try c.decodeIfPresent(Bool.self, forKey: .pomoHabitMinus) ?? pomoHabitMinus
        pomoSetHabitPlus = try c.decodeIfPresent(Bool.self, forKey: .pomoSetHabitPlus) ?? pomoSetHabitPlus
        customPomodoroTask = try c.decodeIfPresent(Bool.self, forKey: .customPomodoroTask) ?? customPomodoroTask
        customSetTask = try c.decodeIfPresent(Bool.self, forKey: .customSetTask) ?? customSetTask
        pomodoroTaskId = try c.decodeIfPresent(String.self, forKey: .pomodoroTaskId)
        pomodoroSetTaskId = try c.decodeIfPresent(String.self, forKey: .pomodoroSetTaskId)
        pomoEndSound = try c.decodeIfPresent(String.self, forKey: .pomoEndSound) ?? pomoEndSound
        breakEndSound = try c.decodeIfPresent(String.self, forKey: .breakEndSound) ?? breakEndSound
        ambientSound = try c.decodeIfPresent(String.self, forKey: .ambientSound) ?? ambientSound
        pomoEndSoundVolume = try c.decodeIfPresent(Double.self, forKey: .pomoEndSoundVolume) ?? pomoEndSoundVolume
        breakEndSoundVolume = try c.decodeIfPresent(Double.self, forKey: .breakEndSoundVolume) ?? breakEndSoundVolume
        ambientSoundVolume = try c.decodeIfPresent(Double.self, forKey: .ambientSoundVolume) ?? ambientSoundVolume
        ambientSource = try c.decodeIfPresent(String.self, forKey: .ambientSource) ?? ambientSource
        developerServerUrl = try c.decodeIfPresent(String.self, forKey: .developerServerUrl) ?? developerServerUrl
        enableBlockMode = try c.decodeIfPresent(Bool.self, forKey: .enableBlockMode) ?? enableBlockMode
        blockCount = try c.decodeIfPresent(Int.self, forKey: .blockCount) ?? blockCount
        blockPomoCount = try c.decodeIfPresent(Int.self, forKey: .blockPomoCount) ?? blockPomoCount
        blockGoals = try c.decodeIfPresent([String].self, forKey: .blockGoals) ?? blockGoals
        blockTimeRanges = try c.decodeIfPresent([BlockTimeRange].self, forKey: .blockTimeRanges) ?? blockTimeRanges
        blockTasks = try c.decodeIfPresent([[BlockTask]].self, forKey: .blockTasks) ?? blockTasks
        blockRewardEnabled = try c.decodeIfPresent(Bool.self, forKey: .blockRewardEnabled) ?? blockRewardEnabled
        blockSprintReminder = try c.decodeIfPresent(Bool.self, forKey: .blockSprintReminder) ?? blockSprintReminder
        blockStartReminder = try c.decodeIfPresent(Bool.self, forKey: .blockStartReminder) ?? blockStartReminder
        blockReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .blockReminderMinutes) ?? blockReminderMinutes
        normalize()
    }

    /// Preserve surplus arrays when the count is lowered; expand safely when it grows.
    mutating func normalize() {
        blockCount = min(24, max(1, blockCount))
        blockPomoCount = min(12, max(1, blockPomoCount))
        pomoDurationMins = min(120, max(1, pomoDurationMins))
        breakDuration = min(60, max(1, breakDuration))
        longBreakDuration = min(120, max(1, longBreakDuration))
        breakExtention = min(30, max(0, breakExtention))
        pomoSetNum = min(12, max(1, pomoSetNum))
        blockReminderMinutes = min(60, max(1, blockReminderMinutes))
        while blockGoals.count < blockCount { blockGoals.append("") }
        while blockTasks.count < blockCount { blockTasks.append([]) }
        while blockTimeRanges.count < blockCount {
            let start = (4 * 60 + blockTimeRanges.count * 180) % 1440
            let end = (start + 180) % 1440
            blockTimeRanges.append(BlockTimeRange(startHour: start / 60, startMinute: start % 60, endHour: end / 60, endMinute: end % 60))
        }
    }
}

// MARK: - Block Time Range (块时间范围)
struct BlockTimeRange: Codable, Equatable {
    var startHour: Int // 开始小时（0-23）
    var startMinute: Int // 开始分钟（0-59）
    var endHour: Int // 结束小时
    var endMinute: Int // 结束分钟

    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }

    // 判断给定时间是否在此块内
    func contains(hour: Int, minute: Int) -> Bool {
        let minutes = hour * 60 + minute
        if startMinutes > endMinutes {
            return minutes >= startMinutes || minutes < endMinutes // spans midnight
        }
        if startMinutes == endMinutes { return true } // equal endpoints represent a full day
        return minutes >= startMinutes && minutes < endMinutes
    }

    // 获取时间范围字符串
    var displayString: String {
        return String(format: "%02d:%02d-%02d:%02d", startHour, startMinute, endHour, endMinute)
    }
}

// MARK: - Block Progress (当前块进度)
struct BlockProgress: Codable {
    var currentBlockIndex: Int = 0 // 当前块索引 (0-based)
    var blockPomoCounter: Int = 0 // 当前块内完成 pomo 数
    var blockStartTime: Date? = nil // 块开始时间
    var progressDate: String = "" // calendar date owning the cached count

    // 获取当前时间点对应的块索引
    static func getCurrentBlockIndex(timeRanges: [BlockTimeRange], date: Date = Date()) -> Int? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        for (index, range) in timeRanges.enumerated() {
            if range.contains(hour: hour, minute: minute) {
                return index
            }
        }
        return nil
    }

    func getBlockGoal(goals: [String]) -> String {
        if currentBlockIndex < goals.count && !goals[currentBlockIndex].isEmpty {
            return goals[currentBlockIndex]
        }
        return "Block \(currentBlockIndex + 1)"
    }

    func getBlockProgress(pomoCount: Int) -> (completed: Int, total: Int) {
        return (blockPomoCounter, pomoCount)
    }

    mutating func incrementBlockPomo() {
        blockPomoCounter += 1
    }

    mutating func moveToNextBlock() {
        currentBlockIndex += 1
        blockPomoCounter = 0
        blockStartTime = Date()
    }

    mutating func resetBlock() {
        currentBlockIndex = 0
        blockPomoCounter = 0
        blockStartTime = nil
    }

    func isBlockComplete(pomoCount: Int) -> Bool {
        return blockPomoCounter >= pomoCount
    }
}

// MARK: - Block Task (块内的任务)
struct BlockTask: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
    var estimatedPomo: Int = 1 // 预计需要几个 pomo
}

// MARK: - Daily Block History (每日块历史)
struct DailyBlockHistory: Codable {
    var date: String // yyyy-MM-dd
    var blocks: [BlockHistoryEntry]
}

// MARK: - Block History (历史块记录)
struct BlockHistoryEntry: Codable {
    var date: String // yyyy-MM-dd
    var blockIndex: Int
    var pomodoros: Int
    var isComplete: Bool
    var completedAt: Date?
}

// MARK: - Daily Block Progress (每天的块进度)
struct DailyBlockProgress: Codable {
    var date: String // yyyy-MM-dd
    var blockProgress: [Int] // 每个块完成的 pomo 数（索引 0 = block 1）
    var blockGoals: [String] // 每个块的目标
}

typealias BlockHistory = [String: [BlockHistoryEntry]] // date -> entries
typealias DailyBlocksHistory = [String: DailyBlockProgress] // date -> daily progress

// MARK: - Top Three (当天最重要的三件事，按分类 Work / MyOwn / 琐事)
struct TopThreeTask: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
    var habiticaTaskId: String? = nil // 对应的 Habitica todo id
    var movedToToday: Bool = false    // 原日期保留的已转移副本
    var syncPending: Bool = false
    var cloudAccount: String? = nil // UID + canonical HTTPS API root; never credentials
    var cloudCreateAttempt: CloudCreateAttempt? = nil

    var isUnfinished: Bool {
        !isCompleted && !movedToToday && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey { case id, title, isCompleted, habiticaTaskId, movedToToday, syncPending, cloudAccount, cloudCreateAttempt }

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, habiticaTaskId: String? = nil, movedToToday: Bool = false, syncPending: Bool = false, cloudAccount: String? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.habiticaTaskId = habiticaTaskId
        self.movedToToday = movedToToday
        self.syncPending = syncPending
        self.cloudAccount = cloudAccount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        habiticaTaskId = try c.decodeIfPresent(String.self, forKey: .habiticaTaskId)
        movedToToday = try c.decodeIfPresent(Bool.self, forKey: .movedToToday) ?? false
        syncPending = try c.decodeIfPresent(Bool.self, forKey: .syncPending) ?? false
        cloudAccount = try c.decodeIfPresent(String.self, forKey: .cloudAccount)
        cloudCreateAttempt = try c.decodeIfPresent(CloudCreateAttempt.self, forKey: .cloudCreateAttempt)
    }
}

/// Persist the exact attempted POST version so a lost response is reconciled before retrying.
struct CloudCreateAttempt: Codable, Equatable {
    var title: String
    var notes: String
    var tags: [String]
}

/// A removed local UUID may already exist remotely even when its POST response was lost.
struct DeletedCloudCreateAttempt: Codable, Equatable {
    var id: UUID
    var attempt: CloudCreateAttempt
}

struct TopThreeCloudState: Codable {
    var categoryTagIds: [String: String] = [:]
    var deletedCloudIds: [String] = []
    var confirmedDeletedCloudIds: [String] = []
    var pendingTagRenames: [String: String] = [:] // tag ID -> desired name
    var deletedCreateAttempts: [DeletedCloudCreateAttempt] = []

    init(categoryTagIds: [String: String] = [:], deletedCloudIds: [String] = [], confirmedDeletedCloudIds: [String] = [], pendingTagRenames: [String: String] = [:], deletedCreateAttempts: [DeletedCloudCreateAttempt] = []) {
        self.categoryTagIds = categoryTagIds
        self.deletedCloudIds = deletedCloudIds
        self.confirmedDeletedCloudIds = confirmedDeletedCloudIds
        self.pendingTagRenames = pendingTagRenames
        self.deletedCreateAttempts = deletedCreateAttempts
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryTagIds = try c.decodeIfPresent([String: String].self, forKey: .categoryTagIds) ?? [:]
        deletedCloudIds = try c.decodeIfPresent([String].self, forKey: .deletedCloudIds) ?? []
        confirmedDeletedCloudIds = try c.decodeIfPresent([String].self, forKey: .confirmedDeletedCloudIds) ?? []
        pendingTagRenames = try c.decodeIfPresent([String: String].self, forKey: .pendingTagRenames) ?? [:]
        deletedCreateAttempts = try c.decodeIfPresent([DeletedCloudCreateAttempt].self, forKey: .deletedCreateAttempts) ?? []
    }
    enum CodingKeys: String, CodingKey { case categoryTagIds, deletedCloudIds, confirmedDeletedCloudIds, pendingTagRenames, deletedCreateAttempts }
}

struct TopThreeDay: Codable {
    var date: String // yyyy-MM-dd（逻辑日，以第一个 time block 启动时间为界）
    var taskGroups: [[TopThreeTask]] = [] // 每个分类一组；Work/MyOwn 固定 3 槽位，琐事为自由列表

    enum CodingKeys: String, CodingKey { case date, taskGroups }

    init(date: String, taskGroups: [[TopThreeTask]] = []) {
        self.date = date
        self.taskGroups = taskGroups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        taskGroups = try c.decodeIfPresent([[TopThreeTask]].self, forKey: .taskGroups) ?? []
    }
}

// 持久化单元：分类名可自定义 + Habitica tag 映射 + 历史记录
struct TopThreeStore: Codable {
    var categoryNames: [String] = ["Work", "MyOwn", "Chores"]
    var categoryTagIds: [String: String] = [:] // 分类名 -> Habitica tag id
    var history: [String: TopThreeDay] = [:] // logical date -> day record
    var deletedCloudIds: [String] = [] // durable tombstones: stale reads cannot resurrect deletions
    var confirmedDeletedCloudIds: [String] = [] // acknowledged deletes need no repeated HTTP request
    var cloudAccount: String = "" // UID + API root only; never store a token here
    var pendingTagRenames: [String: String] = [:]
    var cloudStates: [String: TopThreeCloudState] = [:]
    var deletedCreateAttempts: [DeletedCloudCreateAttempt] = [] // active owner's unresolved removals

    enum CodingKeys: String, CodingKey { case categoryNames, categoryTagIds, history, deletedCloudIds, confirmedDeletedCloudIds, cloudAccount, pendingTagRenames, cloudStates, deletedCreateAttempts }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryNames = try c.decodeIfPresent([String].self, forKey: .categoryNames) ?? ["Work", "MyOwn", "Chores"]
        categoryTagIds = try c.decodeIfPresent([String: String].self, forKey: .categoryTagIds) ?? [:]
        history = try c.decodeIfPresent([String: TopThreeDay].self, forKey: .history) ?? [:]
        deletedCloudIds = try c.decodeIfPresent([String].self, forKey: .deletedCloudIds) ?? []
        confirmedDeletedCloudIds = try c.decodeIfPresent([String].self, forKey: .confirmedDeletedCloudIds) ?? []
        cloudAccount = try c.decodeIfPresent(String.self, forKey: .cloudAccount) ?? ""
        pendingTagRenames = try c.decodeIfPresent([String: String].self, forKey: .pendingTagRenames) ?? [:]
        cloudStates = try c.decodeIfPresent([String: TopThreeCloudState].self, forKey: .cloudStates) ?? [:]
        deletedCreateAttempts = try c.decodeIfPresent([DeletedCloudCreateAttempt].self, forKey: .deletedCreateAttempts) ?? []
    }
}

typealias TopThreeHistory = [String: TopThreeDay] // logical date -> day record

// MARK: - Histogram (daily pomodoro counts)
struct DayHistogram: Codable, Equatable {
    var pomodoros: Int
    var minutes: Int
    var weekday: String
}

typealias Histogram = [String: DayHistogram]

// Additive schema defaults keep old Mac/iPhone JSON readable.
extension BlockTimeRange {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startHour = try c.decodeIfPresent(Int.self, forKey: .startHour) ?? 4
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0
        endHour = try c.decodeIfPresent(Int.self, forKey: .endHour) ?? 7
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute) ?? 0
    }
}
extension BlockProgress {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentBlockIndex = try c.decodeIfPresent(Int.self, forKey: .currentBlockIndex) ?? 0
        blockPomoCounter = try c.decodeIfPresent(Int.self, forKey: .blockPomoCounter) ?? 0
        blockStartTime = try c.decodeIfPresent(Date.self, forKey: .blockStartTime)
        progressDate = try c.decodeIfPresent(String.self, forKey: .progressDate) ?? ""
    }
}
extension BlockTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        estimatedPomo = try c.decodeIfPresent(Int.self, forKey: .estimatedPomo) ?? 1
    }
}
extension BlockHistoryEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        blockIndex = try c.decodeIfPresent(Int.self, forKey: .blockIndex) ?? 0
        pomodoros = try c.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 0
        isComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}
extension DailyBlockProgress {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        blockProgress = try c.decodeIfPresent([Int].self, forKey: .blockProgress) ?? []
        blockGoals = try c.decodeIfPresent([String].self, forKey: .blockGoals) ?? []
    }
}
extension DayHistogram {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pomodoros = try c.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 0
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        weekday = try c.decodeIfPresent(String.self, forKey: .weekday) ?? ""
    }
}


// MARK: - Habitica API Constants
struct HabiticaConsts {
    static let xClientHeader = "5a8238ab-1819-4f7f-a750-f23264719a2d-HabiticaPomodoroSiteKeeper-v2"
    static let serverUrl = "https://habitica.com/api/v3/"
    static let pathUser = "user/"
    static let pathUserTasks = "tasks/user"
    static let pathUserHabits = "tasks/user?type=habits"
    static let pathPomodoroHabit = "tasks/sitepassPomodoro"
    static let pathPomodoroSetHabit = "tasks/sitepassPomodoroSet"
    static let pathReward = "tasks/sitepass"
}

// MARK: - Habitica Task Item (habits / dailies 列表项)
struct HabiticaTaskItem: Identifiable, Equatable {
    let id: String
    let text: String
    let notes: String
    let value: Double
    let completed: Bool
    let canUp: Bool
    let canDown: Bool
    let isDue: Bool // dailies: 今天是否到期
}

/// One rolling budget per UID/API root, shared by every feature. Admission is synchronous:
/// delaying a write here would invalidate the caller's identity/revision check before dispatch.
struct HabiticaRequestBudget {
    static let localLimit = 24 // Habitica allows 30/minute; leave room for other clients.
    private var starts: [TimeInterval] = []
    private var serverRemaining: Int?
    private var serverReset: TimeInterval = 0
    private var cooldownUntil: TimeInterval = 0
    private(set) var received429 = false

    mutating func delay(at uptime: TimeInterval) -> TimeInterval {
        starts.removeAll { $0 <= uptime - 60 }
        if uptime >= serverReset { serverRemaining = nil }
        if uptime >= cooldownUntil { received429 = false }
        let localDelay = starts.count >= Self.localLimit ? (starts.first! + 60 - uptime) : 0
        let serverDelay = serverRemaining == 0 ? serverReset - uptime : 0
        return max(0, localDelay, serverDelay, cooldownUntil - uptime)
    }

    /// Reject instead of queueing/replaying writes. Unacknowledged local edits stay pending.
    mutating func reserve(at uptime: TimeInterval) -> TimeInterval {
        let wait = delay(at: uptime)
        guard wait <= 0 else { return wait }
        starts.append(uptime)
        if let remaining = serverRemaining { serverRemaining = max(0, remaining - 1) }
        return 0
    }

    mutating func observe(_ response: HTTPURLResponse, at uptime: TimeInterval, date: Date) {
        // Use the server's Date when available so a skewed local clock cannot shorten a reset.
        let reference = response.value(forHTTPHeaderField: "Date").flatMap(Self.httpDate) ?? date
        let resetDelay = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap { value -> TimeInterval? in
            let reset = Double(value).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
                ?? Self.httpDate(value)
            return reset.map { max(0, $0.timeIntervalSince(reference)) }
        }
        if let value = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"), let remaining = Int(value) {
            if uptime >= serverReset { serverRemaining = nil }
            // Out-of-order responses may lower the allowance, never replenish it mid-window.
            serverRemaining = min(serverRemaining ?? max(0, remaining), max(0, remaining))
            serverReset = max(serverReset, uptime + (resetDelay ?? 60) + 1)
        }
        if response.statusCode == 429 {
            let retryDelay = response.value(forHTTPHeaderField: "Retry-After").flatMap { value -> TimeInterval? in
                if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
                return Self.httpDate(value).map { max(0, $0.timeIntervalSince(reference)) }
            }
            cooldownUntil = max(cooldownUntil, uptime + max(retryDelay ?? resetDelay ?? 60, resetDelay ?? 0) + 1)
            serverRemaining = 0
            serverReset = max(serverReset, cooldownUntil)
            received429 = true
        }
    }

    private static func httpDate(_ value: String) -> Date? {
        let clean = value.components(separatedBy: " (")[0]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE MMM dd yyyy HH:mm:ss 'GMT'Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: clean) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

// MARK: - Habitica API Client
class HabiticaAPI: ObservableObject {
    static let shared = HabiticaAPI()
    #if DEBUG
    /// Scratch-only offline probes can replace transport before the singleton is initialized.
    static var isolatedURLProtocols: [AnyClass]?
    #endif

    @Published var monies: Double = 0
    @Published var exp: Double = 0
    @Published var hp: Double = 0
    @Published var lastError: String?
    @Published var isAuthenticated: Bool = false

    private var serverUrl: String { HabiticaConsts.serverUrl }

    func configure(serverUrlOverride: String?) -> String {
        let value = (serverUrlOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = value.isEmpty ? serverUrl : value
        guard var parts = URLComponents(string: configured), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return "" }
        parts.scheme = "https"
        parts.host = host.lowercased()
        if parts.port == 443 { parts.port = nil }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        parts.path += "/"
        return parts.string ?? ""
    }

    func cloudAccount(settings: UserSettings) -> String? {
        let root = configure(serverUrlOverride: settings.developerServerUrl)
        guard !settings.uid.isEmpty, !root.isEmpty else { return nil }
        return "\(settings.uid)|\(root)"
    }

    func endpoint(path: String, settings: UserSettings) -> URL? {
        let base = configure(serverUrlOverride: settings.developerServerUrl)
        guard !base.isEmpty, let url = URL(string: base + path), url.scheme?.lowercased() == "https", url.host != nil else {
            reportError("服务地址无效：请使用不含账号、查询参数或片段的 HTTPS API 根地址。", settings: settings)
            return nil
        }
        return url
    }

    private func matchesCurrentAccount(_ settings: UserSettings) -> Bool {
        let current = SettingsManager.shared.settings
        return current.connectHabitica == settings.connectHabitica && current.uid == settings.uid &&
            current.apiToken == settings.apiToken &&
            configure(serverUrlOverride: current.developerServerUrl) == configure(serverUrlOverride: settings.developerServerUrl)
    }
    private func matchesCurrentRequest(_ request: URLRequest) -> Bool {
        let current = SettingsManager.shared.settings
        guard !configure(serverUrlOverride: current.developerServerUrl).isEmpty else { return false }
        return current.connectHabitica && request.value(forHTTPHeaderField: "x-api-user") == current.uid && request.value(forHTTPHeaderField: "x-api-key") == current.apiToken && request.url?.absoluteString.hasPrefix(configure(serverUrlOverride: current.developerServerUrl)) == true
    }

    // A custom header carrying the API token must not follow redirects to another origin.
    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        #if DEBUG
        if let protocols = isolatedURLProtocols { configuration.protocolClasses = protocols }
        #endif
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()
    private enum RequestFailure: Error { case status(Int), rateLimited, invalidResponse, staleAccount }
    // These dictionaries are only accessed on MainActor. Budget keys never include API tokens.
    private var requestBudgets: [String: HabiticaRequestBudget] = [:]
    private struct RequestContext {
        let request: URLRequest
        let accountGeneration: UInt64
        let sequence: UInt64
        let errorRevision: UInt64
    }
    private typealias RequestResult = (data: Data, response: URLResponse, context: RequestContext)
    private var feedbackAccountGeneration: UInt64?
    private var requestSequence: UInt64 = 0
    private var errorRevision: UInt64 = 0
    private var latestErrorSequence: UInt64 = 0
    private var latestAuthenticationSequence: UInt64 = 0
    private var latestProfileSequence: UInt64 = 0
    private struct ReadKey: Hashable {
        let url: URL?
        let user: String?
        let token: String?
        let generation: UInt64
        let accountGeneration: UInt64
    }
    private var readsInFlight: [ReadKey: Task<RequestResult, Error>] = [:]
    private var readGeneration: UInt64 = 0

    @MainActor
    func rateLimitMessage(settings: UserSettings) -> String? {
        guard let account = cloudAccount(settings: settings) else { return nil }
        return rateLimitMessage(account: account)
    }

    @MainActor
    private func rateLimitMessage(account: String) -> String? {
        guard var budget = requestBudgets[account] else { return nil }
        let delay = budget.delay(at: ProcessInfo.processInfo.systemUptime)
        requestBudgets[account] = budget
        guard delay > 0 else { return nil }
        let reason = budget.received429 ? "Habitica 暂时限流（HTTP 429）" : "Habitica 请求额度暂时用完"
        // A finite server delay can still exceed Int's range. Keep its cooldown intact
        // while avoiding a trapping conversion when formatting an unusual response header.
        let retry = Int(exactly: ceil(delay)).map { "\($0) 秒后重试。" }
            ?? "稍后重试（服务器要求的等待时间过长）。"
        return "\(reason)，请 \(retry)"
    }
    @MainActor
    private func prepareFeedbackGeneration() {
        let generation = SettingsManager.shared.habiticaAccountGeneration
        guard feedbackAccountGeneration != generation else { return }
        feedbackAccountGeneration = generation
        errorRevision &+= 1
        latestErrorSequence = 0
        latestAuthenticationSequence = 0
        latestProfileSequence = 0
        lastError = nil
    }

    @MainActor
    private func isCurrent(_ context: RequestContext) -> Bool {
        context.accountGeneration == SettingsManager.shared.habiticaAccountGeneration &&
            matchesCurrentRequest(context.request)
    }

    @MainActor
    private func connectionGeneration(settings: UserSettings) -> UInt64? {
        matchesCurrentAccount(settings) ? SettingsManager.shared.habiticaAccountGeneration : nil
    }

    @MainActor
    private func publishError(_ message: String?, context: RequestContext) {
        guard isCurrent(context), context.sequence >= latestErrorSequence else { return }
        latestErrorSequence = context.sequence
        errorRevision &+= 1
        lastError = message
        // @Published emits in willSet; a subscriber can retire this connection before assignment ends.
        if !isCurrent(context), lastError == message { lastError = nil }
    }

    @MainActor
    private func publishSuccess(context: RequestContext, account: String) {
        // Only a request started after the currently displayed error may clear it.
        guard isCurrent(context), errorRevision == context.errorRevision,
              requestBudgets[account]?.received429 != true else { return }
        lastError = nil
    }

    private func reportError(_ message: String, settings: UserSettings? = nil,
                             context: RequestContext? = nil) {
        let generation = context?.accountGeneration ?? SettingsManager.shared.habiticaAccountGeneration
        DispatchQueue.main.async {
            guard generation == SettingsManager.shared.habiticaAccountGeneration else { return }
            if let context = context {
                self.publishError(message, context: context)
            } else {
                if let settings = settings, !self.matchesCurrentAccount(settings) { return }
                self.prepareFeedbackGeneration()
                self.requestSequence &+= 1
                self.latestErrorSequence = self.requestSequence
                self.errorRevision &+= 1
                self.lastError = message
            }
        }
    }
    // MainActor isolation: caller validation and mutation dispatch share a non-suspending segment.
    @MainActor
    private func perform(_ request: URLRequest, accountGeneration expectedGeneration: UInt64? = nil) async throws -> RequestResult {
        let generation = expectedGeneration ?? SettingsManager.shared.habiticaAccountGeneration
        guard generation == SettingsManager.shared.habiticaAccountGeneration,
              matchesCurrentRequest(request) else { throw RequestFailure.staleAccount }
        try Task.checkCancellation()
        // Only reads can share an in-flight request. Scores/creates/deletes are never replayed.
        if (request.httpMethod ?? "GET") == "GET" {
            let key = ReadKey(url: request.url, user: request.value(forHTTPHeaderField: "x-api-user"),
                              token: request.value(forHTTPHeaderField: "x-api-key"), generation: readGeneration,
                              accountGeneration: generation)
            let pending: Task<RequestResult, Error>
            let ownsRead: Bool
            if let existing = readsInFlight[key] {
                pending = existing
                ownsRead = false
            } else {
                pending = Task { @MainActor in try await self.performRequest(request, accountGeneration: generation) }
                readsInFlight[key] = pending
                ownsRead = true
            }
            defer { if ownsRead { readsInFlight.removeValue(forKey: key) } }
            do {
                let result = try await pending.value
                guard isCurrent(result.context) else { throw RequestFailure.staleAccount }
                return result
            } catch {
                guard generation == SettingsManager.shared.habiticaAccountGeneration,
                      matchesCurrentRequest(request) else { throw RequestFailure.staleAccount }
                throw error
            }
        }
        // Sent mutations must return their real outcome, even after a connection change.
        return try await performRequest(request, accountGeneration: generation)
    }

    @MainActor
    private func performRequest(_ request: URLRequest, accountGeneration generation: UInt64) async throws -> RequestResult {
        guard generation == SettingsManager.shared.habiticaAccountGeneration,
              matchesCurrentRequest(request) else { throw RequestFailure.staleAccount }
        try Task.checkCancellation()
        prepareFeedbackGeneration()
        // Publishing the reset can synchronously reenter settings via Combine subscribers.
        guard generation == SettingsManager.shared.habiticaAccountGeneration,
              matchesCurrentRequest(request),
              let account = cloudAccount(settings: SettingsManager.shared.settings) else { throw RequestFailure.staleAccount }
        requestSequence &+= 1
        let context = RequestContext(request: request, accountGeneration: generation,
                                     sequence: requestSequence, errorRevision: errorRevision)
        var budget = requestBudgets[account] ?? HabiticaRequestBudget()
        let delay = budget.reserve(at: ProcessInfo.processInfo.systemUptime)
        requestBudgets[account] = budget
        guard delay <= 0 else {
            publishError(rateLimitMessage(account: account), context: context)
            throw RequestFailure.rateLimited
        }
        let isMutation = (request.httpMethod ?? "GET") != "GET"
        if isMutation { readGeneration &+= 1 }
        // Verification after a write must not join a read started before its acknowledgement.
        defer { if isMutation { readGeneration &+= 1 } }
        do {
            let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data, let response = response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: RequestFailure.invalidResponse)
                    }
                }
                task.resume()
            }
            guard let http = response as? HTTPURLResponse else { throw RequestFailure.invalidResponse }
            // Server limits belong to the original UID/root, including retired connections.
            var updated = requestBudgets[account] ?? budget
            updated.observe(http, at: ProcessInfo.processInfo.systemUptime, date: Date())
            requestBudgets[account] = updated
            guard (200..<300).contains(http.statusCode) || (request.httpMethod == "DELETE" && http.statusCode == 404) else {
                publishError(http.statusCode == 429 ? rateLimitMessage(account: account)
                    : (http.statusCode == 401 ? "Habitica 认证失败，请检查 User ID / API Token" : "Habitica 请求失败（HTTP \(http.statusCode)）"), context: context)
                if http.statusCode == 401, isCurrent(context), context.sequence >= latestAuthenticationSequence {
                    latestAuthenticationSequence = context.sequence
                    isAuthenticated = false
                }
                throw RequestFailure.status(http.statusCode)
            }
            publishSuccess(context: context, account: account)
            return (data, response, context)
        } catch {
            if case RequestFailure.invalidResponse = error {
                publishError("Habitica 返回了无法识别的响应。", context: context)
            } else if !(error is RequestFailure) && !(error is CancellationError) {
                publishError("网络错误：\(error.localizedDescription)", context: context)
            }
            throw error
        }
    }

    // GET user data
    @MainActor
    func fetchUserData(settings: UserSettings, silent: Bool = false) async {
        let generation = SettingsManager.shared.habiticaAccountGeneration
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else {
            guard matchesCurrentAccount(settings) else { return }
            prepareFeedbackGeneration()
            isAuthenticated = false
            monies = 0; exp = 0; hp = 0
            if !silent {
                guard generation == SettingsManager.shared.habiticaAccountGeneration,
                      matchesCurrentAccount(settings) else { return }
                requestSequence &+= 1
                latestErrorSequence = requestSequence
                errorRevision &+= 1
                lastError = settings.connectHabitica ? "Credentials not configured" : nil
                if generation != SettingsManager.shared.habiticaAccountGeneration { lastError = nil }
            }
            return
        }
        guard let url = endpoint(path: HabiticaConsts.pathUser, settings: settings) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response, context) = try await perform(req)
            guard isCurrent(context), let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded: Any
            do { decoded = try JSONSerialization.jsonObject(with: data) }
            catch {
                publishError("Habitica 角色响应格式错误。", context: context)
                return
            }
            guard let json = decoded as? [String: Any], let userData = json["data"] as? [String: Any],
                  let stats = userData["stats"] as? [String: Any] else {
                publishError("Habitica 角色响应格式错误。", context: context)
                return
            }
            guard context.sequence >= latestAuthenticationSequence,
                  context.sequence >= latestProfileSequence else { return }
            defer {
                // Undo an outer @Published setter that finished after a subscriber changed accounts.
                if !isCurrent(context) {
                    monies = 0; exp = 0; hp = 0
                    isAuthenticated = false
                }
            }
            latestProfileSequence = context.sequence
            latestAuthenticationSequence = context.sequence
            monies = (stats["gp"] as? Double) ?? 0
            guard isCurrent(context) else { return }
            exp = (stats["exp"] as? Double) ?? 0
            guard isCurrent(context) else { return }
            hp = (stats["hp"] as? Double) ?? 0
            guard isCurrent(context) else { return }
            isAuthenticated = true
            // Transport already handled feedback ordering. Parsing must not clear it again.
        } catch { /* Preserve transport errors; only an actual current 401 invalidates credentials. */ }
    }

    // Score a habit up/down
    // MainActor: mutation dispatch chain — caller validation and task.resume() must share one
    // uninterrupted MainActor segment (see perform).
    @MainActor
    func scoreHabit(taskId: String, direction: String, settings: UserSettings) async -> [String: Double]? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: "tasks/\(taskId)/score/\(direction)", settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                return [
                    "lvl": (d["lvl"] as? Double) ?? 0,
                    "hp": (d["hp"] as? Double) ?? 0,
                    "exp": (d["exp"] as? Double) ?? 0,
                    "mp": (d["mp"] as? Double) ?? 0,
                    "gp": (d["gp"] as? Double) ?? 0
                ]
            }
        } catch { return nil }
        return nil
    }

    // Fetch or create the Pomodoro habit task
    func ensurePomodoroHabit(settings: UserSettings) async -> String? {
        if settings.customPomodoroTask {
            guard let id = settings.pomodoroTaskId, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reportError("请填写自定义 Pomodoro Habit ID", settings: settings); return nil }
            return id
        }
        // Try GET existing
        do {
            if let id = try await getTaskId(path: HabiticaConsts.pathPomodoroHabit, settings: settings) { return id }
            return nil
        } catch RequestFailure.status(404) { /* missing alias: create below */ }
        catch { return nil }
        // Create new
        return await createHabit(text: "Pomodoro", alias: "sitepassPomodoro", notes: "Habit utilized by Habitica SiteKeeper. Change the difficulty manually according to your needs.", priority: 1, settings: settings)
    }

    func ensurePomodoroSetHabit(settings: UserSettings) async -> String? {
        if settings.customSetTask {
            guard let id = settings.pomodoroSetTaskId, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reportError("请填写自定义 Combo Habit ID", settings: settings); return nil }
            return id
        }
        do {
            if let id = try await getTaskId(path: HabiticaConsts.pathPomodoroSetHabit, settings: settings) { return id }
            return nil
        } catch RequestFailure.status(404) { /* missing alias: create below */ }
        catch { return nil }
        return await createHabit(text: "Pomodoro Combo!", alias: "sitepassPomodoroSet", notes: "Habit utilized by Habitica SiteKeeper. Change the difficulty manually according to your needs.", priority: 1.5, settings: settings)
    }

    private func getTaskId(path: String, settings: UserSettings) async throws -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: path, settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response, context) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                let id = d["id"] as? String
                return await MainActor.run { self.isCurrent(context) ? id : nil }
            }
        } catch { throw error }
        return nil
    }

    private func createHabit(text: String, alias: String, notes: String, priority: Double, settings: UserSettings) async -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: HabiticaConsts.pathUserTasks, settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "type": "habit", "alias": alias, "notes": notes, "priority": priority]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                return d["id"] as? String
            }
        } catch { return nil }
        return nil
    }

    // Send private message (used for mobile notifications)
    func sendPrivateMessage(_ message: String, settings: UserSettings) async {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return }
        guard let url = endpoint(path: "members/send-private-message", settings: settings) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["message": message, "toUserId": settings.uid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await perform(req)
    }

    // MARK: - Tags (用于任务分类 Work/MyOwn/Chores)

    // 获取所有 tag: [tagId: tagName]
    func fetchTags(settings: UserSettings) async -> [String: String]? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: "tags", settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response, context) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = json["data"] as? [[String: Any]] {
                var result: [String: String] = [:]
                for tag in tags {
                    if let id = tag["id"] as? String, let name = tag["name"] as? String {
                        result[id] = name
                    }
                }
                let tags = result
                return await MainActor.run { self.isCurrent(context) ? tags : nil }
            }
        } catch { return nil }
        return nil
    }

    // 创建 tag，返回 tag id
    func createTag(name: String, settings: UserSettings) async -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: "tags", settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                return d["id"] as? String
            }
        } catch { return nil }
        return nil
    }

    // 确保 tag 存在（按名称查找，不存在则创建），返回 tag id
    func ensureTag(name: String, settings: UserSettings) async -> String? {
        guard let tags = await fetchTags(settings: settings) else { return nil }
        if let existing = tags.first(where: { $0.value == name }) {
            return existing.key
        }
        return await createTag(name: name, settings: settings)
    }

    // 重命名 tag
    @discardableResult
    func renameTag(tagId: String, name: String, settings: UserSettings) async -> Bool {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return false }
        guard let url = endpoint(path: "tags/\(tagId)", settings: settings) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch { return false }
    }

    // MARK: - Todos (Top3 任务同步为 Habitica todo)

    enum TodoCreationResult {
        case created(String)
        /// The request never dispatched or was explicitly rejected before creation.
        case notCreated
        /// The server may have created the task; reconcile before any new POST.
        case uncertain
    }

    // 创建 todo，保留“确定未创建”与“结果不明”的区别。
    // MainActor: POST dispatch is part of the atomic validation→dispatch segment.
    @MainActor
    func createTodo(text: String, notes: String, tagIds: [String], settings: UserSettings) async -> TodoCreationResult {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return .notCreated }
        guard let url = endpoint(path: HabiticaConsts.pathUserTasks, settings: settings) else { return .notCreated }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "type": "todo", "notes": notes, "tags": tagIds]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 200 else { return .uncertain }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any],
               let id = d["id"] as? String, !id.isEmpty {
                return .created(id)
            }
        } catch RequestFailure.rateLimited {
            return .notCreated
        } catch RequestFailure.staleAccount {
            return .notCreated
        } catch is CancellationError {
            // performRequest checks cancellation before task.resume(); it never cancels a sent POST.
            return .notCreated
        } catch RequestFailure.status(let code) where code == 401 || code == 429 {
            return .notCreated
        } catch {
            return .uncertain
        }
        return .uncertain
    }

    // 更新 todo（标题 / tags）
    // MainActor: PUT dispatch is part of the atomic validation→dispatch segment.
    @MainActor
    func updateTodo(taskId: String, text: String?, tagIds: [String]?, notes: String? = nil, settings: UserSettings) async -> Bool {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return false }
        guard let url = endpoint(path: "tasks/\(taskId)", settings: settings) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let text = text { body["text"] = text }
        if let tagIds = tagIds { body["tags"] = tagIds }
        if let notes = notes { body["notes"] = notes }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch { return false }
    }

    // 完成 / 取消完成 todo
    // MainActor: score dispatch is part of the atomic validation→dispatch segment.
    @MainActor
    func scoreTodo(taskId: String, completed: Bool, settings: UserSettings) async -> Bool {
        let direction = completed ? "up" : "down"
        let result = await scoreHabit(taskId: taskId, direction: direction, settings: settings)
        return result != nil
    }

    // 删除 todo
    // MainActor: DELETE dispatch is part of the atomic validation→dispatch segment.
    @MainActor
    func deleteTodo(taskId: String, settings: UserSettings) async -> Bool {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return false }
        guard let url = endpoint(path: "tasks/\(taskId)", settings: settings) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (_, response, _) = try await perform(req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200 || http.statusCode == 404
        } catch { return false }
    }

    struct CloudTodo {
        var id: String
        var title: String
        var notes: String
        var completed: Bool
        var tags: [String]
    }

    func fetchTopThreeTodos(settings: UserSettings) async -> [CloudTodo]? {
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let generation = await connectionGeneration(settings: settings) else { return nil }
        var result: [CloudTodo] = []
        for kind in ["todos", "completedTodos"] {
            guard let url = endpoint(path: "tasks/user?type=\(kind)", settings: settings) else { return nil }
            var request = URLRequest(url: url)
            request.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
            request.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
            request.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
            do {
                let (data, _, context) = try await perform(request, accountGeneration: generation)
                let decoded: Any
                do { decoded = try JSONSerialization.jsonObject(with: data) }
                catch {
                    reportError("Habitica todo 响应格式错误", settings: settings, context: context)
                    return nil
                }
                guard let json = decoded as? [String: Any],
                      let entries = json["data"] as? [[String: Any]] else { reportError("Habitica todo 响应格式错误", settings: settings, context: context); return nil }
                result += entries.compactMap { item in
                    guard let id = item["id"] as? String, let title = item["text"] as? String else { return nil }
                    return CloudTodo(id: id, title: title, notes: item["notes"] as? String ?? "",
                                     completed: item["completed"] as? Bool ?? false, tags: item["tags"] as? [String] ?? [])
                }
            } catch { return nil }
        }
        let todos = result
        return await MainActor.run {
            generation == SettingsManager.shared.habiticaAccountGeneration && self.matchesCurrentAccount(settings) ? todos : nil
        }
    }

    // MARK: - Task Lists (habits / dailies)

    // 获取指定类型的任务列表
    func fetchTasks(type: String, settings: UserSettings) async -> [HabiticaTaskItem] {
        await fetchTaskList(type: type, settings: settings) ?? []
    }

    /// A failed request is distinct from a valid empty list, so views can retain their last data.
    func fetchTaskList(type: String, settings: UserSettings) async -> [HabiticaTaskItem]? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: "tasks/user?type=\(type)", settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response, context) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded: Any
            do { decoded = try JSONSerialization.jsonObject(with: data) }
            catch {
                reportError("Habitica 任务列表响应格式错误，已保留上次加载的数据。", settings: settings, context: context)
                return nil
            }
            guard let json = decoded as? [String: Any], let arr = json["data"] as? [[String: Any]] else {
                reportError("Habitica 任务列表响应格式错误，已保留上次加载的数据。", settings: settings, context: context)
                return nil
            }
            var items: [HabiticaTaskItem] = []
            var ids = Set<String>()
            for t in arr {
                guard let id = t["id"] as? String, !id.isEmpty, ids.insert(id).inserted,
                      let text = t["text"] as? String else {
                    reportError("Habitica 任务列表响应格式错误，已保留上次加载的数据。", settings: settings, context: context)
                    return nil
                }
                let notes = t["notes"] as? String ?? ""
                let value = t["value"] as? Double ?? 0
                var completed = false
                var isDue = true
                if type == "dailys" {
                    completed = t["completed"] as? Bool ?? false
                    isDue = t["isDue"] as? Bool ?? true
                }
                var canUp = true, canDown = true
                if let up = t["up"] as? Bool { canUp = up }
                if let down = t["down"] as? Bool { canDown = down }
                items.append(HabiticaTaskItem(id: id, text: text, notes: notes, value: value,
                                             completed: completed, canUp: canUp, canDown: canDown, isDue: isDue))
            }
            let parsed = items
            return await MainActor.run { self.isCurrent(context) ? parsed : nil }
        } catch {
            return nil
        }
    }

    // 打分（up/down），返回最新 stats
    func scoreTask(taskId: String, direction: String, settings: UserSettings) async -> [String: Double]? {
        return await scoreHabit(taskId: taskId, direction: direction, settings: settings)
    }

    // MARK: - User Profile (账号信息)

    // 获取完整账号信息
    func fetchProfile(settings: UserSettings) async -> HabiticaProfile? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        guard let url = endpoint(path: HabiticaConsts.pathUser + "?userFields=auth,stats,achievements", settings: settings) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response, context) = try await perform(req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = json["data"] as? [String: Any] else { return nil }
            let parsed = parseProfile(d)
            return await MainActor.run { self.isCurrent(context) ? parsed : nil }
        } catch { return nil }
    }

    private func parseProfile(_ d: [String: Any]) -> HabiticaProfile {
        var p = HabiticaProfile()
        if let auth = d["auth"] as? [String: Any] {
            if let local = auth["local"] as? [String: Any] {
                p.username = (local["username"] as? String) ?? ""
            }
            // timestamps 在 auth 层级，ISO8601 字符串格式
            if let timestamps = auth["timestamps"] as? [String: Any] {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let f2 = ISO8601DateFormatter()
                if let created = timestamps["created"] as? String {
                    p.joinedAt = f.date(from: created) ?? f2.date(from: created)
                }
                if let login = timestamps["loggedin"] as? String {
                    p.lastLoginAt = f.date(from: login) ?? f2.date(from: login)
                }
            }
        }
        if let stats = d["stats"] as? [String: Any] {
            p.className = (stats["class"] as? String) ?? ""
            p.level = Int(stats["lvl"] as? Double ?? 0)
            p.exp = stats["exp"] as? Double ?? 0
            p.hp = stats["hp"] as? Double ?? 0
            p.mp = stats["mp"] as? Double ?? 0
            p.gp = stats["gp"] as? Double ?? 0
            p.str = Int(stats["str"] as? Double ?? 0)
            p.con = Int(stats["con"] as? Double ?? 0)
            p.int = Int(stats["int"] as? Double ?? 0)
            p.per = Int(stats["per"] as? Double ?? 0)
            p.toNextLevel = stats["toNextLevel"] as? Double ?? 0
            p.maxHealth = 50 // Habitica HP 上限固定 50
            // MP 上限公式: 30 + 3*(lvl-1) + int/2
            let lvl = Double(p.level)
            p.maxMP = 30 + 3 * max(0, lvl - 1) + Double(p.int) / 2
        }
        if let achievements = d["achievements"] as? [String: Any] {
            p.streak = Int(achievements["streak"] as? Double ?? 0)
            p.perfectDays = Int(achievements["perfectCount"] as? Double ?? 0)
            p.questsTotal = 0
            if let quests = achievements["quests"] as? [String: Any] {
                p.questsTotal = quests.values.reduce(0) { $0 + Int($1 as? Double ?? 0) }
            }
        }
        return p
    }
}

// MARK: - Habitica Profile (账号信息)
struct HabiticaProfile {
    var username: String = ""
    var authId: String = ""
    var className: String = ""
    var level: Int = 0
    var exp: Double = 0
    var toNextLevel: Double = 0
    var hp: Double = 0
    var maxHealth: Double = 50
    var mp: Double = 0
    var maxMP: Double = 0
    var gp: Double = 0
    var str: Int = 0
    var con: Int = 0
    var int: Int = 0
    var per: Int = 0
    var streak: Int = 0
    var perfectDays: Int = 0
    var questsTotal: Int = 0
    var joinedAt: Date? = nil
    var lastLoginAt: Date? = nil
}

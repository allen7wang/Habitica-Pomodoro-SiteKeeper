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

    // 获取当前时间点对应的块索引
    static func getCurrentBlockIndex(timeRanges: [BlockTimeRange]) -> Int? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())

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
    var movedToToday: Bool = false    // 昨天任务已移动到今日

    enum CodingKeys: String, CodingKey { case id, title, isCompleted, habiticaTaskId, movedToToday }

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, habiticaTaskId: String? = nil, movedToToday: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.habiticaTaskId = habiticaTaskId
        self.movedToToday = movedToToday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        habiticaTaskId = try c.decodeIfPresent(String.self, forKey: .habiticaTaskId)
        movedToToday = try c.decodeIfPresent(Bool.self, forKey: .movedToToday) ?? false
    }
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

    enum CodingKeys: String, CodingKey { case categoryNames, categoryTagIds, history }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryNames = try c.decodeIfPresent([String].self, forKey: .categoryNames) ?? ["Work", "MyOwn", "Chores"]
        categoryTagIds = try c.decodeIfPresent([String: String].self, forKey: .categoryTagIds) ?? [:]
        history = try c.decodeIfPresent([String: TopThreeDay].self, forKey: .history) ?? [:]
    }
}

typealias TopThreeHistory = [String: TopThreeDay] // logical date -> day record

// MARK: - Histogram (daily pomodoro counts)
struct DayHistogram: Codable {
    var pomodoros: Int
    var minutes: Int
    var weekday: String
}

typealias Histogram = [String: DayHistogram]

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

// MARK: - Habitica API Client
class HabiticaAPI: ObservableObject {
    static let shared = HabiticaAPI()

    @Published var monies: Double = 0
    @Published var exp: Double = 0
    @Published var hp: Double = 0
    @Published var lastError: String?
    @Published var isAuthenticated: Bool = false

    private var serverUrl: String { HabiticaConsts.serverUrl }

    func configure(serverUrlOverride: String?) -> String {
        if let url = serverUrlOverride, !url.isEmpty { return url }
        return serverUrl
    }

    // GET user data
    func fetchUserData(settings: UserSettings, silent: Bool = false) async {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else {
            if !silent { await MainActor.run { self.lastError = "Credentials not configured" } }
            return
        }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + HabiticaConsts.pathUser)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                await MainActor.run { self.lastError = "Invalid credentials"; self.isAuthenticated = false }
                return
            }
            guard http.statusCode == 200 else {
                await MainActor.run { self.lastError = "Server error: \(http.statusCode)" }
                return
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userData = json["data"] as? [String: Any],
               let stats = userData["stats"] as? [String: Any] {
                await MainActor.run {
                    self.monies = (stats["gp"] as? Double) ?? 0
                    self.exp = (stats["exp"] as? Double) ?? 0
                    self.hp = (stats["hp"] as? Double) ?? 0
                    self.isAuthenticated = true
                    self.lastError = nil
                }
            }
        } catch {
            await MainActor.run { self.lastError = "Network error: \(error.localizedDescription)" }
        }
    }

    // Score a habit up/down
    func scoreHabit(taskId: String, direction: String, settings: UserSettings) async -> [String: Double]? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        let urlStr = configure(serverUrlOverride: settings.developerServerUrl) + "tasks/\(taskId)/score/\(direction)"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
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
        if settings.customPomodoroTask, let id = settings.pomodoroTaskId { return id }
        // Try GET existing
        if let id = await getTaskId(path: HabiticaConsts.pathPomodoroHabit, settings: settings) {
            return id
        }
        // Create new
        return await createHabit(text: "Pomodoro", alias: "sitepassPomodoro", notes: "Habit utilized by Habitica SiteKeeper. Change the difficulty manually according to your needs.", priority: 1, settings: settings)
    }

    func ensurePomodoroSetHabit(settings: UserSettings) async -> String? {
        if settings.customSetTask, let id = settings.pomodoroSetTaskId { return id }
        if let id = await getTaskId(path: HabiticaConsts.pathPomodoroSetHabit, settings: settings) {
            return id
        }
        return await createHabit(text: "Pomodoro Combo!", alias: "sitepassPomodoroSet", notes: "Habit utilized by Habitica SiteKeeper. Change the difficulty manually according to your needs.", priority: 1.5, settings: settings)
    }

    private func getTaskId(path: String, settings: UserSettings) async -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                return d["id"] as? String
            }
        } catch { return nil }
        return nil
    }

    private func createHabit(text: String, alias: String, notes: String, priority: Double, settings: UserSettings) async -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + HabiticaConsts.pathUserTasks)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "type": "habit", "alias": alias, "notes": notes, "priority": priority]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
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
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "members/send-private-message")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["message": message, "toUserId": settings.uid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Tags (用于任务分类 Work/MyOwn/Chores)

    // 获取所有 tag: [tagId: tagName]
    func fetchTags(settings: UserSettings) async -> [String: String] {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return [:] }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "tags")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = json["data"] as? [[String: Any]] {
                var result: [String: String] = [:]
                for tag in tags {
                    if let id = tag["id"] as? String, let name = tag["name"] as? String {
                        result[id] = name
                    }
                }
                return result
            }
        } catch { return [:] }
        return [:]
    }

    // 创建 tag，返回 tag id
    func createTag(name: String, settings: UserSettings) async -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "tags")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
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
        let tags = await fetchTags(settings: settings)
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
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "tags/\(tagId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch { return false }
    }

    // MARK: - Todos (Top3 任务同步为 Habitica todo)

    // 创建 todo，返回 task id
    func createTodo(text: String, notes: String, tagIds: [String], settings: UserSettings) async -> String? {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + HabiticaConsts.pathUserTasks)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "type": "todo", "notes": notes, "tags": tagIds]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = json["data"] as? [String: Any] {
                return d["id"] as? String
            }
        } catch { return nil }
        return nil
    }

    // 更新 todo（标题 / tags）
    func updateTodo(taskId: String, text: String?, tagIds: [String]?, settings: UserSettings) async -> Bool {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return false }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "tasks/\(taskId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let text = text { body["text"] = text }
        if let tagIds = tagIds { body["tags"] = tagIds }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch { return false }
    }

    // 完成 / 取消完成 todo
    func scoreTodo(taskId: String, completed: Bool, settings: UserSettings) async -> Bool {
        let direction = completed ? "up" : "down"
        let result = await scoreHabit(taskId: taskId, direction: direction, settings: settings)
        return result != nil
    }

    // 删除 todo
    func deleteTodo(taskId: String, settings: UserSettings) async -> Bool {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return false }
        let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "tasks/\(taskId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch { return false }
    }

    // MARK: - Task Lists (habits / dailies)

    // 获取指定类型的任务列表
    func fetchTasks(type: String, settings: UserSettings) async -> [HabiticaTaskItem] {
        guard settings.connectHabitica,
              !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return [] }
        guard let url = URL(string: configure(serverUrlOverride: settings.developerServerUrl) + "tasks/user?type=\(type)") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]] else { return [] }
            return arr.compactMap { t in
                guard let id = t["id"] as? String,
                      let text = t["text"] as? String else { return nil }
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
                return HabiticaTaskItem(id: id, text: text, notes: notes, value: value,
                                        completed: completed, canUp: canUp, canDown: canDown, isDue: isDue)
            }
        } catch { return [] }
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
        let urlStr = configure(serverUrlOverride: settings.developerServerUrl) + HabiticaConsts.pathUser + "?userFields=auth,stats,achievements"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HabiticaConsts.xClientHeader, forHTTPHeaderField: "x-client")
        req.setValue(settings.uid, forHTTPHeaderField: "x-api-user")
        req.setValue(settings.apiToken, forHTTPHeaderField: "x-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = json["data"] as? [String: Any] else { return nil }
            return parseProfile(d)
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

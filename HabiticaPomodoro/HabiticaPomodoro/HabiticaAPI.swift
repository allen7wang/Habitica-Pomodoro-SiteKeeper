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
}

// MARK: - Block Progress (当前块进度)
struct BlockProgress: Codable {
    var currentBlockIndex: Int = 0 // 当前块索引 (0-based)
    var blockPomoCounter: Int = 0 // 当前块内完成 pomo 数
    var blockStartTime: Date? = nil // 块开始时间

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

// MARK: - Block History (历史块记录)
struct BlockHistoryEntry: Codable {
    var date: String // yyyy-MM-dd
    var blockIndex: Int
    var pomodoros: Int
    var isComplete: Bool
    var completedAt: Date?
}

typealias BlockHistory = [String: [BlockHistoryEntry]] // date -> entries

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
}

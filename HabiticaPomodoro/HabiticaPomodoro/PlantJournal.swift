import Foundation
import Combine

// 独立于共享时间块 JSON：旧版 iOS 写入进度时不会抹掉 Mac 的植物记录。
enum PlantOutcome: String, Codable {
    case shrub, wilted
}

struct PlantDay: Codable {
    var attempts: [[PlantOutcome]] = []
    var trees: [Int] = []

    init(attempts: [[PlantOutcome]] = [], trees: [Int] = []) { self.attempts = attempts; self.trees = trees }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attempts = try c.decodeIfPresent([[PlantOutcome]].self, forKey: .attempts) ?? []
        trees = try c.decodeIfPresent([Int].self, forKey: .trees) ?? []
    }
}

final class PlantJournal: ObservableObject {
    static let shared = PlantJournal()

    @Published private(set) var days: [String: PlantDay] = [:]
    private let fileName = "habitica_pomodoro_plants.json"
    private let backupKey = "habitica_pomodoro_plants_backup"
    private var fileURL: URL { PomodoroDataDir.fileURL(fileName) }

    private init() {
        reload()
    }

    // Folder-grant and cloud changes must replace the in-memory journal without writing it back.
    func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: PlantDay].self, from: data) {
            days = saved
            PomodoroFileChanges.shared.consume(fileURL, data: data)
        } else if let data = UserDefaults.standard.data(forKey: backupKey),
                  let saved = try? JSONDecoder().decode([String: PlantDay].self, from: data) {
            days = saved
        } else {
            days = [:]
        }
    }

    private func todayKey(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // 为旧数据或从 iPhone 同步过来的完成数补画灌木；原有放弃记录不动。
    private func aligned(_ attempts: [PlantOutcome], completed: Int) -> [PlantOutcome] {
        let missing = max(0, completed - attempts.filter { $0 == .shrub }.count)
        return Array(repeating: .shrub, count: missing) + attempts
    }

    func plants(blockIndex: Int, completed: Int) -> [PlantOutcome] {
        guard blockIndex >= 0 else { return [] }
        let day = days[todayKey()]
        let attempts: [PlantOutcome]
        if let day = day, day.attempts.indices.contains(blockIndex) {
            attempts = day.attempts[blockIndex]
        } else {
            attempts = []
        }
        return aligned(attempts, completed: completed)
    }

    func treeCount(blockIndex: Int) -> Int {
        guard blockIndex >= 0, let day = days[todayKey()],
              day.trees.indices.contains(blockIndex) else { return 0 }
        return day.trees[blockIndex]
    }

    func recordCompletion(blockIndex: Int, completed: Int, comboCompleted: Bool, date: Date = Date()) {
        guard blockIndex >= 0 else { return }
        let key = todayKey(date: date)
        var day = days[key] ?? PlantDay()
        while day.attempts.count <= blockIndex { day.attempts.append([]) }
        while day.trees.count <= blockIndex { day.trees.append(0) }
        day.attempts[blockIndex] = aligned(day.attempts[blockIndex], completed: completed - 1)
        day.attempts[blockIndex].append(.shrub)
        if comboCompleted { day.trees[blockIndex] += 1 }
        days[key] = day
        save()
    }

    func recordAbandonment(blockIndex: Int, completed: Int) {
        guard blockIndex >= 0 else { return }
        let key = todayKey()
        var day = days[key] ?? PlantDay()
        while day.attempts.count <= blockIndex { day.attempts.append([]) }
        day.attempts[blockIndex] = aligned(day.attempts[blockIndex], completed: completed)
        day.attempts[blockIndex].append(.wilted)
        days[key] = day
        save()
    }

    func clear() {
        days = [:]
        save()
    }

    @discardableResult
    func save() -> Bool {
        do {
            let data = try JSONEncoder().encode(days)
            UserDefaults.standard.set(data, forKey: backupKey)
            try data.write(to: fileURL, options: .atomic)
            PomodoroDataDir.noteLocalWrite(fileName, data: data)
            return true
        } catch {
            print("Error saving plant journal: \(error)")
            return false
        }
    }
}

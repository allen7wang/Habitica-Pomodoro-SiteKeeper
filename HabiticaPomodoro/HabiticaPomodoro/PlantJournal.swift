import Foundation
import Combine

// 独立于共享时间块 JSON：旧版 iOS 写入进度时不会抹掉 Mac 的植物记录。
enum PlantOutcome: String, Codable {
    case shrub, wilted
}

private struct PlantDay: Codable {
    var attempts: [[PlantOutcome]] = []
    var trees: [Int] = []
}

final class PlantJournal: ObservableObject {
    static let shared = PlantJournal()

    @Published private var days: [String: PlantDay] = [:]
    private let fileName = "habitica_pomodoro_plants.json"
    private let backupKey = "habitica_pomodoro_plants_backup"
    private var fileURL: URL { PomodoroDataDir.fileURL(fileName) }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: PlantDay].self, from: data) {
            days = saved
        } else if let data = UserDefaults.standard.data(forKey: backupKey),
                  let saved = try? JSONDecoder().decode([String: PlantDay].self, from: data) {
            days = saved
        }
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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

    func recordCompletion(blockIndex: Int, completed: Int, comboCompleted: Bool) {
        guard blockIndex >= 0 else { return }
        let key = todayKey()
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

    private func save() {
        do {
            let data = try JSONEncoder().encode(days)
            try data.write(to: fileURL, options: .atomic)
            PomodoroDataDir.noteLocalWrite()
            UserDefaults.standard.set(data, forKey: backupKey)
        } catch {
            print("Error saving plant journal: \(error)")
        }
    }
}

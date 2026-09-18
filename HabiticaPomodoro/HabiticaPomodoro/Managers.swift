import Foundation
import AVFoundation
import Combine

// MARK: - Settings Manager (persisted via UserDefaults + JSON)
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var settings: UserSettings {
        didSet { save() }
    }

    private let key = "habitica_pomodoro_settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            settings = decoded
        } else {
            settings = UserSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Block Progress Manager (块进度管理)
class BlockProgressManager: ObservableObject {
    static let shared = BlockProgressManager()

    @Published var blockProgress: BlockProgress
    @Published var blockHistory: BlockHistory
    @Published var dailyBlocksHistory: DailyBlocksHistory

    private let progressKey = "habitica_pomodoro_block_progress"
    private let historyKey = "habitica_pomodoro_block_history"
    private let dailyBlocksKey = "habitica_pomodoro_daily_blocks"

    init() {
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let decoded = try? JSONDecoder().decode(BlockProgress.self, from: data) {
            blockProgress = decoded
        } else {
            blockProgress = BlockProgress()
        }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode(BlockHistory.self, from: data) {
            blockHistory = decoded
        } else {
            blockHistory = [:]
        }

        if let data = UserDefaults.standard.data(forKey: dailyBlocksKey),
           let decoded = try? JSONDecoder().decode(DailyBlocksHistory.self, from: data) {
            dailyBlocksHistory = decoded
        } else {
            dailyBlocksHistory = [:]
        }

        // 检查是否需要重置新一天的块
        resetIfNeeded()
    }

    func saveProgress() {
        if let data = try? JSONEncoder().encode(blockProgress) {
            UserDefaults.standard.set(data, forKey: progressKey)
        }
    }

    func saveHistory() {
        if let data = try? JSONEncoder().encode(blockHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func saveDailyBlocks() {
        if let data = try? JSONEncoder().encode(dailyBlocksHistory) {
            UserDefaults.standard.set(data, forKey: dailyBlocksKey)
        }
    }

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // 检查是否需要重置新一天的块
    private func resetIfNeeded() {
        let today = todayKey()
        if let lastEntry = getLatestBlockEntry(),
           lastEntry.date != today {
            // 新的一天，重置块进度
            blockProgress.resetBlock()
            saveProgress()
        }
    }

    private func getLatestBlockEntry() -> BlockHistoryEntry? {
        guard !blockHistory.isEmpty else { return nil }
        let sortedDates = blockHistory.keys.sorted()
        if let lastDate = sortedDates.last,
           let entries = blockHistory[lastDate],
           let lastEntry = entries.last {
            return lastEntry
        }
        return nil
    }

    // 根据当前时间自动更新块索引
    func updateBlockIndexFromTime(settings: UserSettings) {
        if let newIndex = BlockProgress.getCurrentBlockIndex(timeRanges: settings.blockTimeRanges) {
            if newIndex != blockProgress.currentBlockIndex {
                blockProgress.currentBlockIndex = newIndex
                blockProgress.blockPomoCounter = 0 // 切换块时重置 pomo 计数
                saveProgress()
            }
        }
    }

    // 记录 pomo 完成到当前块
    func recordPomoInCurrentBlock(settings: UserSettings) {
        // 先更新当前块索引（基于时间）
        updateBlockIndexFromTime(settings: settings)

        // 记录到每日进度
        let today = todayKey()
        if var daily = dailyBlocksHistory[today] {
            // 确保数组长度足够
            while daily.blockProgress.count <= blockProgress.currentBlockIndex {
                daily.blockProgress.append(0)
            }
            daily.blockProgress[blockProgress.currentBlockIndex] = blockProgress.blockPomoCounter + 1
            dailyBlocksHistory[today] = daily
        } else {
            var progress = Array(repeating: 0, count: settings.blockCount)
            if blockProgress.currentBlockIndex < progress.count {
                progress[blockProgress.currentBlockIndex] = 1
            }
            dailyBlocksHistory[today] = DailyBlockProgress(
                date: today,
                blockProgress: progress,
                blockGoals: settings.blockGoals
            )
        }
        saveDailyBlocks()
    }

    // 记录块完成
    func recordBlockComplete(settings: UserSettings) {
        let entry = BlockHistoryEntry(
            date: todayKey(),
            blockIndex: blockProgress.currentBlockIndex,
            pomodoros: blockProgress.blockPomoCounter,
            isComplete: true,
            completedAt: Date()
        )

        let today = todayKey()
        if var entries = blockHistory[today] {
            entries.append(entry)
            blockHistory[today] = entries
        } else {
            blockHistory[today] = [entry]
        }
        saveHistory()
    }

    // 获取今天的所有块进度
    func getTodayBlockProgress(settings: UserSettings) -> [Int] {
        let today = todayKey()
        if let daily = dailyBlocksHistory[today] {
            var progress = daily.blockProgress
            // 确保长度匹配
            while progress.count < settings.blockCount {
                progress.append(0)
            }
            return Array(progress.prefix(settings.blockCount))
        }
        return Array(repeating: 0, count: settings.blockCount)
    }

    // 获取当前块完成进度（基于时间）
    func getCurrentBlockCompletion(settings: UserSettings) -> (completed: Int, total: Int) {
        updateBlockIndexFromTime(settings: settings)
        let progress = getTodayBlockProgress(settings: settings)
        if blockProgress.currentBlockIndex < progress.count {
            return (progress[blockProgress.currentBlockIndex], settings.blockPomoCount)
        }
        return (0, settings.blockPomoCount)
    }

    // 清空历史
    func clearHistory() {
        blockHistory = [:]
        dailyBlocksHistory = [:]
        saveHistory()
        saveDailyBlocks()
    }

    // 获取今天的块历史
    func getTodayBlocks() -> [BlockHistoryEntry] {
        return blockHistory[todayKey()] ?? []
    }
}

// MARK: - Histogram Manager
class HistogramManager: ObservableObject {
    static let shared = HistogramManager()

    @Published var histogram: Histogram

    private let key = "habitica_pomodoro_histogram"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Histogram.self, from: data) {
            histogram = decoded
        } else {
            histogram = [:]
        }
    }

    func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func weekday() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    func getToday() -> DayHistogram? {
        return histogram[todayKey()]
    }

    func incrementToday(pomodoros: Int, minutes: Int) {
        let key = todayKey()
        let wd = weekday()
        if var existing = histogram[key] {
            existing.pomodoros += pomodoros
            existing.minutes += minutes
            histogram[key] = existing
        } else {
            histogram[key] = DayHistogram(pomodoros: pomodoros, minutes: minutes, weekday: wd)
        }
        save()
    }

    func clear() {
        histogram = [:]
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(histogram) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // Statistics
    var totalPomodoros: Int { histogram.values.reduce(0) { $0 + $1.pomodoros } }
    var totalHours: Double { Double(histogram.values.reduce(0) { $0 + $1.minutes }) / 60.0 }
    var avgPomodoros: Double { histogram.isEmpty ? 0 : Double(totalPomodoros) / Double(histogram.count) }
    var avgHours: Double { histogram.isEmpty ? 0 : totalHours / Double(histogram.count) }

    // Sorted entries for chart
    var sortedEntries: [(date: String, day: DayHistogram)] {
        histogram.sorted { $0.key < $1.key }.map { (date: $0.key, day: $0.value) }
    }
}

// MARK: - Audio Manager
class AudioManager: ObservableObject {
    static let shared = AudioManager()

    private var ambientPlayer: AVAudioPlayer?
    private var soundPlayer: AVAudioPlayer?

    // Sound file lists (mirror the extension)
    static let sounds = ["Sound1", "Sound2", "Sound3", "Sound4", "Sound5", "Sound6", "Sound7", "Sound8", "Sound9"]
    static let ambientSounds = ["Ambient Clock", "Ambient Rain", "Ambient Crickets", "Ambient Birds"]
    static let allSoundOptions: [String] = ["None"] + sounds.map { "\($0).mp3" }
    static let allAmbientOptions: [String] = ["None"] + ambientSounds.map { "\($0).mp3" }

    // Audio bundle: look in the app bundle's "audio" subfolder
    private func audioURL(_ filename: String) -> URL? {
        // Try bundle Resources/audio folder (works in .app bundle)
        if let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "audio") {
            return url
        }
        // Try bundle Resources directly (if audio files are flat)
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            return url
        }
        // Try adjacent audio folder (dev mode - running from binary)
        let execURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let audioDir = execURL.appendingPathComponent("audio")
        let candidate = audioDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        // Try relative to source directory (dev mode)
        let relDir = URL(fileURLWithPath: "audio")
        let relCandidate = relDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: relCandidate.path) {
            return relCandidate
        }
        return nil
    }

    func playSound(_ filename: String, volume: Double) {
        guard filename != "None" else { return }
        guard let url = audioURL(filename) else { return }
        do {
            soundPlayer = try AVAudioPlayer(contentsOf: url)
            soundPlayer?.volume = Float(volume)
            soundPlayer?.play()
        } catch { print("Audio error: \(error)") }
    }

    func playAmbient(sound: String, volume: Double) {
        guard sound != "None" else { return }
        if ambientPlayer?.isPlaying == true { return } // don't restart if already playing
        guard let url = audioURL(sound) else { return }
        do {
            ambientPlayer = try AVAudioPlayer(contentsOf: url)
            ambientPlayer?.numberOfLoops = -1
            ambientPlayer?.volume = Float(volume)
            ambientPlayer?.play()
        } catch { print("Ambient audio error: \(error)") }
    }

    func stopAmbient() {
        ambientPlayer?.stop()
        ambientPlayer = nil
    }
}

import Foundation
import AVFoundation
import Combine

// MARK: - Data Directory (配置文件统一存放在 Documents 下的隐藏文件夹)
// ~/Documents 由 iCloud Drive（桌面与文稿同步）自动同步，
// 因此 .habitica-pomodoro 文件夹及其中的 JSON 文件会随 iCloud 同步到其他设备。
enum PomodoroDataDir {
    static let folderName = ".habitica-pomodoro"

    static var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(folderName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(_ fileName: String) -> URL {
        url.appendingPathComponent(fileName)
    }

    // 一次性迁移：把旧的散落在 Documents 根目录的文件移入隐藏文件夹
    static func migrateOldFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldNames = [
            "habitica_pomodoro_settings.json",
            "habitica_pomodoro_block_progress.json",
            "habitica_pomodoro_block_history.json",
            "habitica_pomodoro_daily_blocks.json",
            "habitica_pomodoro_top_three.json",
        ]
        for name in oldNames {
            let oldURL = docs.appendingPathComponent(name)
            let newURL = fileURL(name)
            if FileManager.default.fileExists(atPath: oldURL.path),
               !FileManager.default.fileExists(atPath: newURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }
    }
}

// MARK: - Settings Manager (persisted via iCloud)
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var settings: UserSettings {
        didSet { save() }
    }

    private let fileName = "habitica_pomodoro_settings.json"
    private var fileURL: URL {
        PomodoroDataDir.fileURL(fileName)
    }
    
    private let localBackupKey = "habitica_pomodoro_settings_backup"

    init() {
        // 迁移旧文件到隐藏文件夹
        PomodoroDataDir.migrateOldFiles()

        // Initialize settings first
        self.settings = UserSettings()
        
        // Load from iCloud or local fallback
        if let loadedSettings = Self.loadFile(UserSettings.self, from: fileURL) {
            self.settings = loadedSettings
        } else if let data = UserDefaults.standard.data(forKey: localBackupKey),
                  let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            self.settings = decoded
        }
    }
    
    private static func getDocumentsDirectory() -> URL {
        PomodoroDataDir.url
    }
    
    private static func loadFile<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        do {
            let jsonData = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: jsonData)
        } catch {
            return nil
        }
    }
    
    private static func saveFile(_ data: Data, to url: URL) -> Bool {
        do {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try data.write(to: url)
            print("Saved to: \(url.path)")
            return true
        } catch {
            print("Error saving to \(url.path): \(error)")
            return false
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            // Save to file
            if Self.saveFile(data, to: fileURL) {
                print("Settings saved to: \(fileURL.path)")
            }
            
            // Also save to UserDefaults as backup
            UserDefaults.standard.set(data, forKey: localBackupKey)
        }
    }
}

// MARK: - Block Progress Manager (块进度管理)
class BlockProgressManager: ObservableObject {
    static let shared = BlockProgressManager()

    @Published var blockProgress: BlockProgress
    @Published var blockHistory: BlockHistory
    @Published var dailyBlocksHistory: DailyBlocksHistory

    private let progressFileName = "habitica_pomodoro_block_progress.json"
    private let historyFileName = "habitica_pomodoro_block_history.json"
    private let dailyBlocksFileName = "habitica_pomodoro_daily_blocks.json"
    
    private static func getDocumentsDirectory() -> URL {
        PomodoroDataDir.url
    }

    private var progressFileURL: URL { Self.getDocumentsDirectory().appendingPathComponent(progressFileName) }
    private var historyFileURL: URL { Self.getDocumentsDirectory().appendingPathComponent(historyFileName) }
    private var dailyBlocksFileURL: URL { Self.getDocumentsDirectory().appendingPathComponent(dailyBlocksFileName) }
    
    private let localBackupProgressKey = "habitica_pomodoro_block_progress_backup"
    private let localBackupHistoryKey = "habitica_pomodoro_block_history_backup"
    private let localBackupDailyBlocksKey = "habitica_pomodoro_daily_blocks_backup"

    init() {
        let docsDir = Self.getDocumentsDirectory()
        
        // Load block progress
        if let loadedProgress = Self.loadFile(BlockProgress.self, from: docsDir.appendingPathComponent(progressFileName)) {
            blockProgress = loadedProgress
        } else if let data = UserDefaults.standard.data(forKey: localBackupProgressKey),
                  let decoded = try? JSONDecoder().decode(BlockProgress.self, from: data) {
            blockProgress = decoded
        } else {
            blockProgress = BlockProgress()
        }

        // Load block history
        if let loadedHistory = Self.loadFile([String: [BlockHistoryEntry]].self, from: docsDir.appendingPathComponent(historyFileName)) {
            blockHistory = loadedHistory
        } else if let data = UserDefaults.standard.data(forKey: localBackupHistoryKey),
                  let decoded = try? JSONDecoder().decode([String: [BlockHistoryEntry]].self, from: data) {
            blockHistory = decoded
        } else {
            blockHistory = [:]
        }

        // Load daily blocks history
        if let loadedDaily = Self.loadFile(DailyBlocksHistory.self, from: docsDir.appendingPathComponent(dailyBlocksFileName)) {
            dailyBlocksHistory = loadedDaily
        } else if let data = UserDefaults.standard.data(forKey: localBackupDailyBlocksKey),
                  let decoded = try? JSONDecoder().decode(DailyBlocksHistory.self, from: data) {
            dailyBlocksHistory = decoded
        } else {
            dailyBlocksHistory = [:]
        }

        // 检查是否需要重置新一天的块
        resetIfNeeded()
    }
    
    private static func loadFile<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        do {
            let jsonData = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: jsonData)
        } catch {
            return nil
        }
    }
    
    private static func saveFile<T: Codable>(_ data: T, to url: URL) -> Bool {
        do {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let jsonData: Data
            if let dataAsData = data as? Data {
                jsonData = dataAsData
            } else {
                jsonData = try JSONEncoder().encode(data)
            }
            try jsonData.write(to: url)
            print("Saved to: \(url.path)")
            return true
        } catch {
            print("Error saving to \(url.path): \(error)")
            return false
        }
    }

    func saveProgress() {
        Self.saveFile(blockProgress, to: progressFileURL)
        
        if let data = try? JSONEncoder().encode(blockProgress) {
            UserDefaults.standard.set(data, forKey: localBackupProgressKey)
        }
    }

    func saveHistory() {
        Self.saveFile(blockHistory, to: historyFileURL)
        
        if let data = try? JSONEncoder().encode(blockHistory) {
            UserDefaults.standard.set(data, forKey: localBackupHistoryKey)
        }
    }

    func saveDailyBlocks() {
        Self.saveFile(dailyBlocksHistory, to: dailyBlocksFileURL)
        
        if let data = try? JSONEncoder().encode(dailyBlocksHistory) {
            UserDefaults.standard.set(data, forKey: localBackupDailyBlocksKey)
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

        // 增加当前块的 pomo 计数
        blockProgress.incrementBlockPomo()

        // 记录到每日进度
        let today = todayKey()
        if var daily = dailyBlocksHistory[today] {
            // 确保数组长度足够
            while daily.blockProgress.count <= blockProgress.currentBlockIndex {
                daily.blockProgress.append(0)
            }
            daily.blockProgress[blockProgress.currentBlockIndex] = blockProgress.blockPomoCounter
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

// MARK: - Top Three Manager (当天最重要的三件事，Work / MyOwn 两类)
class TopThreeManager: ObservableObject {
    static let shared = TopThreeManager()

    @Published var store: TopThreeStore

    private let fileName = "habitica_pomodoro_top_three.json"
    private var fileURL: URL { PomodoroDataDir.fileURL(fileName) }
    private let localBackupKey = "habitica_pomodoro_top_three_backup"

    init() {
        if let loaded = Self.loadFile(TopThreeStore.self, from: PomodoroDataDir.fileURL(fileName)) {
            store = loaded
        } else if let data = UserDefaults.standard.data(forKey: "habitica_pomodoro_top_three_backup"),
                  let decoded = try? JSONDecoder().decode(TopThreeStore.self, from: data) {
            store = decoded
        } else {
            store = TopThreeStore()
        }
    }

    private static func loadFile<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        do {
            let jsonData = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: jsonData)
        } catch {
            return nil
        }
    }

    func save() {
        do {
            let url = fileURL
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let jsonData = try JSONEncoder().encode(store)
            try jsonData.write(to: url)
            UserDefaults.standard.set(jsonData, forKey: localBackupKey)
            print("TopThree saved to: \(url.path)")
        } catch {
            print("Error saving TopThree: \(error)")
        }
    }

    // MARK: 逻辑日：一天的开始 = 第一个 time block 的启动时间
    func logicalDateKey(settings: UserSettings, date: Date = Date()) -> String {
        // 第一个块的开始时间（分钟）
        let boundaryMinutes = settings.blockTimeRanges.first?.startMinutes ?? 0

        let cal = Calendar.current
        let minuteOfDay = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)

        // 如果当前时间在第一个块开始时间之前，逻辑上还是"昨天"
        var logical = date
        if minuteOfDay < boundaryMinutes {
            logical = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: logical)
    }

    func todayKey(settings: UserSettings) -> String {
        return logicalDateKey(settings: settings)
    }

    func yesterdayKey(settings: UserSettings) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = todayKey(settings: settings)
        if let d = f.date(from: today),
           let prev = Calendar.current.date(byAdding: .day, value: -1, to: d) {
            return f.string(from: prev)
        }
        return today
    }

    // 只有"今天"（逻辑日）的任务可以修改
    func isEditable(key: String, settings: UserSettings) -> Bool {
        return key == todayKey(settings: settings)
    }

    // MARK: 分类名（可自定义）
    var categoryCount: Int { store.categoryNames.count }

    func categoryName(index: Int) -> String {
        guard index < store.categoryNames.count else { return "Category \(index + 1)" }
        return store.categoryNames[index]
    }

    func setCategoryName(index: Int, name: String) {
        guard index < store.categoryNames.count else { return }
        store.categoryNames[index] = name
        save()
    }

    // MARK: 任务读写（按分类）
    private func ensureDay(key: String) {
        if store.history[key] == nil {
            store.history[key] = TopThreeDay(date: key)
        }
        var day = store.history[key]!
        while day.taskGroups.count < categoryCount {
            day.taskGroups.append([])
        }
        // 每组补齐 3 个槽位
        for i in 0..<day.taskGroups.count {
            while day.taskGroups[i].count < 3 {
                day.taskGroups[i].append(TopThreeTask(title: ""))
            }
        }
        store.history[key] = day
    }

    func setTaskTitle(key: String, category: Int, index: Int, title: String, settings: UserSettings) {
        guard isEditable(key: key, settings: settings) else { return }
        ensureDay(key: key)
        guard var day = store.history[key],
              category < day.taskGroups.count,
              index < day.taskGroups[category].count else { return }
        day.taskGroups[category][index].title = title
        store.history[key] = day
        save()
    }

    func toggleTask(key: String, category: Int, index: Int, settings: UserSettings) {
        guard isEditable(key: key, settings: settings) else { return }
        ensureDay(key: key)
        guard var day = store.history[key],
              category < day.taskGroups.count,
              index < day.taskGroups[category].count else { return }
        day.taskGroups[category][index].isCompleted.toggle()
        store.history[key] = day
        save()
    }

    func getTasks(key: String, category: Int) -> [TopThreeTask] {
        if let day = store.history[key],
           category < day.taskGroups.count {
            var tasks = day.taskGroups[category]
            while tasks.count < 3 {
                tasks.append(TopThreeTask(title: ""))
            }
            return tasks
        }
        return Array(repeating: TopThreeTask(title: ""), count: 3)
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

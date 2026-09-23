import Foundation
import AVFoundation
import Combine

// MARK: - Data Directory (配置文件统一存放在 Documents 下的隐藏文件夹)
// ~/Documents 由 iCloud Drive（桌面与文稿同步）自动同步，
// 因此 .habitica-pomodoro 文件夹及其中的 JSON 文件会随 iCloud 同步到其他设备。
enum PomodoroDataDir {
    static let folderName = ".habitica-pomodoro"

    static var url: URL {
        #if os(iOS)
        // iOS：用户通过文件选择器授权 iCloud Drive 目录后，数据落在
        // <授权目录>/.habitica-pomodoro（与 macOS 端 ~/Documents/.habitica-pomodoro 同一批文件）。
        // 未授权时回退 App 沙箱本地目录，保证 App 始终可用。
        if let iCloudDir = ICloudFolderGrant.shared.dataFolderURL {
            return iCloudDir
        }
        #endif
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

    /// 数据目录变化后（如 iOS 授权 iCloud 文件夹）重新加载
    func reload() {
        if let loaded = Self.loadFile(UserSettings.self, from: fileURL) {
            settings = loaded
        } else if let data = UserDefaults.standard.data(forKey: localBackupKey),
                  let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            settings = decoded
        }
        print("Settings reloaded from: \(fileURL.path)")
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

    /// 数据目录变化后（如 iOS 授权 iCloud 文件夹）重新加载全部三类数据
    func reload() {
        if let loaded = Self.loadFile(BlockProgress.self, from: progressFileURL) {
            blockProgress = loaded
        } else if let data = UserDefaults.standard.data(forKey: localBackupProgressKey),
                  let decoded = try? JSONDecoder().decode(BlockProgress.self, from: data) {
            blockProgress = decoded
        } else {
            blockProgress = BlockProgress()
        }

        if let loaded = Self.loadFile([String: [BlockHistoryEntry]].self, from: historyFileURL) {
            blockHistory = loaded
        } else if let data = UserDefaults.standard.data(forKey: localBackupHistoryKey),
                  let decoded = try? JSONDecoder().decode([String: [BlockHistoryEntry]].self, from: data) {
            blockHistory = decoded
        } else {
            blockHistory = [:]
        }

        if let loaded = Self.loadFile(DailyBlocksHistory.self, from: dailyBlocksFileURL) {
            dailyBlocksHistory = loaded
        } else if let data = UserDefaults.standard.data(forKey: localBackupDailyBlocksKey),
                  let decoded = try? JSONDecoder().decode(DailyBlocksHistory.self, from: data) {
            dailyBlocksHistory = decoded
        } else {
            dailyBlocksHistory = [:]
        }

        resetIfNeeded()
        print("BlockProgress reloaded from: \(progressFileURL.path)")
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

// MARK: - Top Three Manager (当天最重要的三件事 + 琐事，同步 Habitica)
class TopThreeManager: ObservableObject {
    static let shared = TopThreeManager()

    @Published var store: TopThreeStore

    // 前 2 个分类（Work/MyOwn）固定 3 槽位；第 3 个及以后（琐事）为自由列表
    static let fixedSlotCategories = 2

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
        // 旧数据升级：补齐琐事分类
        if store.categoryNames.count < 3 {
            store.categoryNames.append("Chores")
            save()
        }
        // 旧数据升级：清除固定槽位模式遗留的空标题占位任务
        var migrated = false
        for (key, var day) in store.history {
            for g in 0..<day.taskGroups.count {
                let before = day.taskGroups[g].count
                day.taskGroups[g].removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                if day.taskGroups[g].count != before { migrated = true }
            }
            if migrated { store.history[key] = day }
        }
        if migrated { save() }
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

    /// 数据目录变化后（如 iOS 授权 iCloud 文件夹）重新加载
    func reload() {
        if let loaded = Self.loadFile(TopThreeStore.self, from: fileURL) {
            store = loaded
        } else if let data = UserDefaults.standard.data(forKey: localBackupKey),
                  let decoded = try? JSONDecoder().decode(TopThreeStore.self, from: data) {
            store = decoded
        } else {
            store = TopThreeStore()
        }
        // 与 init 相同的旧数据升级
        if store.categoryNames.count < 3 {
            store.categoryNames.append("Chores")
            save()
        }
        var migrated = false
        for (key, var day) in store.history {
            for g in 0..<day.taskGroups.count {
                let before = day.taskGroups[g].count
                day.taskGroups[g].removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                if day.taskGroups[g].count != before { migrated = true }
            }
            if migrated { store.history[key] = day }
        }
        if migrated { save() }
        print("TopThree reloaded from: \(fileURL.path)")
    }

    // MARK: 逻辑日：一天的开始 = 第一个 time block 的启动时间
    func logicalDateKey(settings: UserSettings, date: Date = Date()) -> String {
        let boundaryMinutes = settings.blockTimeRanges.first?.startMinutes ?? 0
        let cal = Calendar.current
        let minuteOfDay = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
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

    func isFreeList(category: Int) -> Bool {
        return category >= Self.fixedSlotCategories
    }

    func setCategoryName(index: Int, name: String, settings: UserSettings) {
        guard index < store.categoryNames.count else { return }
        let oldName = store.categoryNames[index]
        store.categoryNames[index] = name
        // tag 映射跟随改名
        if let tagId = store.categoryTagIds.removeValue(forKey: oldName) {
            store.categoryTagIds[name] = tagId
        }
        save()
        // 异步同步 Habitica tag 名称（复用已有 tag id 时更新名称）
        Task {
            if let tagId = store.categoryTagIds[name] {
                await HabiticaAPI.shared.renameTag(tagId: tagId, name: name, settings: settings)
            }
        }
    }

    // MARK: 任务读写（按分类，统一为自由列表式交互；Work/MyOwn 上限 3 条）
    private func ensureDay(key: String) {
        if store.history[key] == nil {
            store.history[key] = TopThreeDay(date: key)
        }
        var day = store.history[key]!
        while day.taskGroups.count < categoryCount {
            day.taskGroups.append([])
        }
        store.history[key] = day
    }

    // 任务上限：固定分类（Work/MyOwn）最多 3 条，琐事不限
    func taskLimit(category: Int) -> Int? {
        return isFreeList(category: category) ? nil : 3
    }

    func canAddTask(key: String, category: Int, settings: UserSettings) -> Bool {
        guard isEditable(key: key, settings: settings) else { return false }
        if let limit = taskLimit(category: category) {
            return getTasks(key: key, category: category).count < limit
        }
        return true
    }

    // 统一添加任务（所有分类相同交互）
    func addTask(key: String, category: Int, title: String, settings: UserSettings) {
        guard canAddTask(key: key, category: category, settings: settings) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ensureDay(key: key)
        var day = store.history[key]!
        let task = TopThreeTask(title: trimmed)
        day.taskGroups[category].append(task)
        store.history[key] = day
        save()
        syncTaskToHabitica(task: task, category: category, key: key, settings: settings)
    }

    func setTaskTitle(key: String, category: Int, index: Int, title: String, settings: UserSettings) {
        guard isEditable(key: key, settings: settings) else { return }
        ensureDay(key: key)
        guard var day = store.history[key],
              category < day.taskGroups.count,
              index < day.taskGroups[category].count else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        day.taskGroups[category][index].title = trimmed
        store.history[key] = day
        save()
        let task = day.taskGroups[category][index]
        if !trimmed.isEmpty {
            syncTaskToHabitica(task: task, category: category, key: key, settings: settings)
        }
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
        let task = day.taskGroups[category][index]
        syncCompletionToHabitica(task: task, settings: settings)
    }

    func getTasks(key: String, category: Int) -> [TopThreeTask] {
        if let day = store.history[key],
           category < day.taskGroups.count {
            return day.taskGroups[category]
        }
        return []
    }

    // 统一删除任务（所有分类相同交互）
    func removeTask(key: String, category: Int, index: Int, settings: UserSettings) {
        guard isEditable(key: key, settings: settings) else { return }
        ensureDay(key: key)
        guard var day = store.history[key],
              category < day.taskGroups.count,
              index < day.taskGroups[category].count else { return }
        let task = day.taskGroups[category].remove(at: index)
        store.history[key] = day
        save()
        // 删除 Habitica todo
        if let todoId = task.habiticaTaskId {
            Task {
                _ = await HabiticaAPI.shared.deleteTodo(taskId: todoId, settings: settings)
            }
        }
    }

    // MARK: 昨天未完成任务移动到今日

    func canMoveToToday(key: String, settings: UserSettings) -> Bool {
        return key == yesterdayKey(settings: settings)
    }

    @discardableResult
    func moveTaskToToday(fromKey: String, category: Int, index: Int, settings: UserSettings) -> Bool {
        guard canMoveToToday(key: fromKey, settings: settings) else { return false }
        ensureDay(key: fromKey)
        let todayK = todayKey(settings: settings)
        ensureDay(key: todayK)

        guard var srcDay = store.history[fromKey],
              category < srcDay.taskGroups.count,
              index < srcDay.taskGroups[category].count else { return false }
        let task = srcDay.taskGroups[category][index]
        guard !task.isCompleted, !task.movedToToday, !task.title.isEmpty else { return false }

        var dstDay = store.history[todayK]!
        // 统一为自由列表：直接追加（固定分类受 3 条上限约束）
        if let limit = taskLimit(category: category),
           dstDay.taskGroups[category].count >= limit {
            return false // 今日该分类已满
        }
        var moved = task
        moved.movedToToday = false
        dstDay.taskGroups[category].append(moved)

        // 标记昨天任务已移动
        srcDay.taskGroups[category][index].movedToToday = true
        store.history[fromKey] = srcDay
        store.history[todayK] = dstDay
        save()
        return true
    }

    // MARK: - Habitica 同步

    // 确保分类对应的 Habitica tag 存在，返回 tag id
    func ensureTagId(category: Int, settings: UserSettings) async -> String? {
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return nil }
        let name = categoryName(index: category)
        if let cached = store.categoryTagIds[name], !cached.isEmpty {
            return cached
        }
        if let tagId = await HabiticaAPI.shared.ensureTag(name: name, settings: settings) {
            await MainActor.run {
                store.categoryTagIds[name] = tagId
                save()
            }
            return tagId
        }
        return nil
    }

    // 创建/更新任务的 Habitica todo
    private func syncTaskToHabitica(task: TopThreeTask, category: Int, key: String, settings: UserSettings) {
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return }
        let catName = categoryName(index: category)
        Task {
            let tagIds: [String]
            if let tagId = await ensureTagId(category: category, settings: settings) {
                tagIds = [tagId]
            } else {
                tagIds = []
            }
            if let todoId = task.habiticaTaskId {
                // 更新标题和 tags
                let ok = await HabiticaAPI.shared.updateTodo(taskId: todoId, text: task.title, tagIds: tagIds, settings: settings)
                print("Habitica update todo \(todoId): \(ok)")
            } else {
                // 创建 todo
                let notes = "From HabiticaPomodoro Top3 · \(catName) · \(key)"
                if let todoId = await HabiticaAPI.shared.createTodo(text: task.title, notes: notes, tagIds: tagIds, settings: settings) {
                    await MainActor.run {
                        // 按任务 UUID 回写 habiticaTaskId
                        for (dateKey, var day) in store.history {
                            var changed = false
                            for g in 0..<day.taskGroups.count {
                                for t in 0..<day.taskGroups[g].count where day.taskGroups[g][t].id == task.id {
                                    day.taskGroups[g][t].habiticaTaskId = todoId
                                    changed = true
                                }
                            }
                            if changed { store.history[dateKey] = day }
                        }
                        save()
                    }
                    print("Habitica todo created: \(todoId) for \(task.title)")
                }
            }
        }
    }

    // 同步完成状态到 Habitica
    private func syncCompletionToHabitica(task: TopThreeTask, settings: UserSettings) {
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return }
        guard let todoId = task.habiticaTaskId else { return }
        let completed = task.isCompleted
        Task {
            let ok = await HabiticaAPI.shared.scoreTodo(taskId: todoId, completed: completed, settings: settings)
            print("Habitica score todo \(todoId) completed=\(completed): \(ok)")
        }
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

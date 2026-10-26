import Foundation
import AVFoundation
import Combine
#if os(macOS)
import WidgetKit
#endif

// MARK: - Data Directory (配置文件统一存放在 Documents 下的隐藏文件夹)
// ~/Documents 由 iCloud Drive（桌面与文稿同步）自动同步，
// 因此 .habitica-pomodoro 文件夹及其中的 JSON 文件会随 iCloud 同步到其他设备。
enum PomodoroDataDir {
    static let folderName = ".habitica-pomodoro"
    static let dataFileNames = [
        "habitica_pomodoro_settings.json", "habitica_pomodoro_block_progress.json",
        "habitica_pomodoro_block_history.json", "habitica_pomodoro_daily_blocks.json",
        "habitica_pomodoro_top_three.json", "habitica_pomodoro_plants.json",
        "habitica_pomodoro_histogram.json"
    ]
    #if DEBUG
    static var isolatedDirectory: URL? {
        didSet {
            if oldValue?.standardizedFileURL != isolatedDirectory?.standardizedFileURL {
                PomodoroFileChanges.shared.noteDirectoryChange()
            }
        }
    }
    #endif

    /// Select the data location separately from Mac directory creation during polling.
    static var resolvedURL: URL {
        #if DEBUG
        // UI verification only: never used by release builds.
        if let override = ProcessInfo.processInfo.environment["POMODORO_ISOLATED_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let isolated = isolatedDirectory { return isolated }
        #endif
        #if os(iOS)
        // iOS：用户通过文件选择器授权 iCloud Drive 目录后，数据落在
        // <授权目录>/.habitica-pomodoro（与 macOS 端 ~/Documents/.habitica-pomodoro 同一批文件）。
        // 未授权时回退 App 沙箱本地目录，保证 App 始终可用。
        if let iCloudDir = ICloudFolderGrant.shared.dataFolderURL { return iCloudDir }
        #endif
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(folderName)
    }

    static var url: URL {
        // Reloads must use the captured directory without a second FileProvider access.
        if let directory = PomodoroFileChanges.shared.prefetchedDirectory { return directory }
        let dir = resolvedURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func resolveDataFolder(under root: URL, fm: FileManager) -> URL {
        let folder = folderName
        let inRoot = root.appendingPathComponent(folder)
        let inDocuments = root.appendingPathComponent("Documents").appendingPathComponent(folder)

        func hasData(_ url: URL) -> Bool {
            dataFileNames.contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        }
        // 1. 已有数据者优先
        if hasData(inRoot) { return inRoot }
        if hasData(inDocuments) { return inDocuments }
        // 2. 父级本身就是 Documents
        if root.lastPathComponent == "Documents" { return inRoot }
        // 3. 父级是 iCloud Drive 根且含 Documents 子目录 → 对齐 macOS 路径
        var isDir: ObjCBool = false
        let docsDir = root.appendingPathComponent("Documents")
        if fm.fileExists(atPath: docsDir.path, isDirectory: &isDir), isDir.boolValue {
            return inDocuments
        }
        // 4. 兜底
        return inRoot
    }

    static func fileURL(_ fileName: String) -> URL {
        url.appendingPathComponent(fileName)
    }

    static var onLocalWrite: ((String) -> Void)?

    /// Consume only the bytes actually written, never snapshot unrelated/unloaded cloud files.
    static func noteLocalWrite(_ fileName: String, data: Data) {
        PomodoroFileChanges.shared.noteLocalWrite(fileURL(fileName), data: data)
        onLocalWrite?(fileName)
    }

    // 一次性迁移：把旧的散落在 Documents 根目录的文件移入隐藏文件夹
    static func migrateOldFiles() {
        if PomodoroFileChanges.shared.prefetchedDirectory != nil { return }
        #if DEBUG
        if isolatedDirectory != nil { return }
        #endif
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldNames = dataFileNames
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

/// The same seven-file inventory on both platforms. Baselines mean consumed bytes, not observed
/// mtimes: a failed decode stays detectable, including same-size updates within the same second.
final class PomodoroFileChanges {
    static let shared = PomodoroFileChanges()
    // Mutable monitor state and manager publication stay on the main thread. Only immutable
    // URLs/results cross to the reader queue; a cloud download must never stall the UI run loop.
    private var consumed: [String: Data] = [:]
    private var revision = 0
    private var localMutationRevision = 0
    private var dirtyPaths: [String: Int] = [:]
    private var pollTimer: Timer?
    private let readerQueue = DispatchQueue(label: "com.hermes.habitica-pomodoro.file-reader", qos: .utility)
    private var reading = false
    private var completions: [() -> Void] = []
    private var observedDirectory: String?
    private var directoryGeneration = 0
    private var prefetched: [String: Result<Data, Error>]?
    private(set) var prefetchedDirectory: URL?

    struct DirectoryIdentity: Equatable {
        let url: URL
        let generation: Int
    }

    /// Selection events invalidate A-B-A recovery too, even without an intervening scan.
    func noteDirectoryChange() { directoryGeneration += 1 }

    func directoryIdentity() -> DirectoryIdentity {
        let directory = PomodoroDataDir.resolvedURL.standardizedFileURL
        if observedDirectory != directory.path {
            observedDirectory = directory.path
            directoryGeneration += 1
        }
        return DirectoryIdentity(url: directory, generation: directoryGeneration)
    }

    func consume(_ url: URL, data: Data) {
        consumed[url.standardizedFileURL.path] = data
        revision += 1
    }

    /// Mark before attempting disk I/O. A failed save must keep newer in-memory state dirty.
    func noteLocalMutation(_ url: URL) {
        localMutationRevision += 1
        dirtyPaths[url.standardizedFileURL.path] = localMutationRevision
        revision += 1
    }

    func noteLocalWrite(_ url: URL, data: Data) {
        dirtyPaths.removeValue(forKey: url.standardizedFileURL.path)
        localMutationRevision += 1
        consume(url, data: data)
    }

    /// Only a successful explicit replacement may discard the failed edit it replaced.
    /// Capture before reading/publication; a synchronous subscriber can create a newer
    /// failed save before acknowledgement. Scans/consume never clear dirty ownership.
    func explicitReloadAcknowledgement(for url: URL) -> () -> Void {
        let path = url.standardizedFileURL.path
        let dirtyRevision = dirtyPaths[path]
        let explicit = prefetched == nil
        return {
            guard explicit, self.dirtyPaths[path] == dirtyRevision,
                  PomodoroDataDir.resolvedURL.standardizedFileURL == url.deletingLastPathComponent().standardizedFileURL else { return }
            self.dirtyPaths.removeValue(forKey: path)
        }
    }

    /// A reload consumes the exact background-read bytes, not a second synchronous cloud read.
    /// Failed/absent entries stay failed: never fall through to disk while applying a snapshot.
    func readData(from url: URL) throws -> Data {
        if let prefetched = prefetched {
            guard let result = prefetched[url.standardizedFileURL.path] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return try result.get()
        }
        return try Data(contentsOf: url)
    }

    func fileExists(at url: URL) -> Bool {
        if let result = prefetched?[url.standardizedFileURL.path] {
            switch result {
            case .success: return true
            case .failure(let error):
                let nsError = error as NSError
                return !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError)
            }
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Single-flight asynchronous polling, also used at launch and foreground activation.
    /// Explicit save-all callers wait for completion before writing their in-memory state.
    func syncFromDiskIfNeeded(completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.syncFromDiskIfNeeded(completion: completion) }
            return
        }
        let directory = directoryIdentity().url
        if let completion = completion { completions.append(completion) }
        guard !reading else { return } // A slow download cannot queue an unbounded backlog.
        reading = true
        let requestedRevision = revision
        let requestedDirectoryGeneration = directoryGeneration
        readerQueue.async {
            let snapshot = Dictionary(uniqueKeysWithValues: PomodoroDataDir.dataFileNames.map { name in
                let url = directory.appendingPathComponent(name)
                return (url.path, Result { try Data(contentsOf: url) })
            })
            DispatchQueue.main.async {
                // Keep the request in flight through publication, including synchronous subscribers.
                // A write/reload or a folder switch while reading invalidates the entire batch,
                // including grouped block files. An A→B→A switch is not the original generation.
                guard self.revision == requestedRevision,
                      self.directoryGeneration == requestedDirectoryGeneration,
                      PomodoroDataDir.resolvedURL.standardizedFileURL == directory else {
                    self.reading = false
                    self.syncFromDiskIfNeeded()
                    return
                }
                let changed = Set(PomodoroDataDir.dataFileNames.filter { name in
                    let path = directory.appendingPathComponent(name).path
                    guard self.dirtyPaths[path] == nil, case .success(let data) = snapshot[path] else { return false }
                    return self.consumed[path] != data
                })
                self.prefetched = snapshot
                self.prefetchedDirectory = directory
                let applyingMutationRevision = self.localMutationRevision
                let isCurrent = {
                    self.localMutationRevision == applyingMutationRevision &&
                        self.directoryGeneration == requestedDirectoryGeneration &&
                        PomodoroDataDir.resolvedURL.standardizedFileURL == directory
                }
                self.reload(changed: changed, isCurrent: isCurrent)
                let invalidatedDuringPublication = !isCurrent()
                self.prefetched = nil
                self.prefetchedDirectory = nil
                self.reading = false
                if invalidatedDuringPublication {
                    self.syncFromDiskIfNeeded()
                    return
                }
                let callbacks = self.completions
                self.completions.removeAll()
                callbacks.forEach { $0() }
            }
        }
    }

    private func reload(changed: Set<String>, isCurrent: () -> Bool) {
        if isCurrent(), changed.contains("habitica_pomodoro_settings.json") { SettingsManager.shared.reload() }
        if isCurrent(),
           !changed.isDisjoint(with: ["habitica_pomodoro_block_progress.json", "habitica_pomodoro_block_history.json", "habitica_pomodoro_daily_blocks.json"]),
           canReloadBlocks() {
            BlockProgressManager.shared.reload()
        }
        if isCurrent(), changed.contains("habitica_pomodoro_top_three.json") { TopThreeManager.shared.reload() }
        if isCurrent(), changed.contains("habitica_pomodoro_plants.json") { PlantJournal.shared.reload() }
        if isCurrent(), changed.contains("habitica_pomodoro_histogram.json") { HistogramManager.shared.reload() }
        // Only successful manager decodes consume bytes; corrupt revisions remain retryable.
    }

    /// Block reload has migration/write side effects. A failed/corrupt or dirty companion must
    /// not trigger its backup fallback and overwrite another member of the three-file group.
    private func canReloadBlocks() -> Bool {
        guard let directory = prefetchedDirectory, let prefetched = prefetched else { return false }
        for name in ["habitica_pomodoro_block_progress.json", "habitica_pomodoro_block_history.json", "habitica_pomodoro_daily_blocks.json"] {
            let path = directory.appendingPathComponent(name).path
            guard dirtyPaths[path] == nil, let result = prefetched[path] else { return false }
            switch result {
            case .failure(let error):
                let nsError = error as NSError
                guard nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError else { return false }
            case .success(let data):
                let decoder = JSONDecoder()
                switch name {
                case "habitica_pomodoro_block_progress.json":
                    if (try? decoder.decode(BlockProgress.self, from: data)) == nil { return false }
                case "habitica_pomodoro_block_history.json":
                    if (try? decoder.decode(BlockHistory.self, from: data)) == nil { return false }
                default:
                    if (try? decoder.decode(DailyBlocksHistory.self, from: data)) == nil { return false }
                }
            }
        }
        return true
    }

    func startMonitoring() {
        guard pollTimer == nil else { return }
        syncFromDiskIfNeeded()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.syncFromDiskIfNeeded() }
        pollTimer?.tolerance = 3
    }
}

// MARK: - Settings Manager (persisted via iCloud)
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var settings: UserSettings {
        didSet {
            guard !isNormalizing else { return }
            isNormalizing = true
            var normalized = settings
            normalized.normalize()
            settings = normalized
            isNormalizing = false
            if !isReloading { save() }
        }
    }

    private var isNormalizing = false
    private var isReloading = false
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
            let jsonData = try PomodoroFileChanges.shared.readData(from: url)
            let decoded = try JSONDecoder().decode(type, from: jsonData)
            PomodoroFileChanges.shared.consume(url, data: jsonData)
            return decoded
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
            try data.write(to: url, options: .atomic)
            PomodoroDataDir.noteLocalWrite(url.lastPathComponent, data: data)
            print("Saved to: \(url.path)")
            return true
        } catch {
            print("Error saving to \(url.path): \(error)")
            return false
        }
    }

    @discardableResult
    func save() -> Bool {
        PomodoroFileChanges.shared.noteLocalMutation(fileURL)
        var saved = false
        if let data = try? JSONEncoder().encode(settings) {
            // Save to file
            saved = Self.saveFile(data, to: fileURL)
            if saved {
                print("Settings saved to: \(fileURL.path)")
            }
            
            // Also save to UserDefaults as backup
            UserDefaults.standard.set(data, forKey: localBackupKey)
        }
        #if os(iOS)
        BlockNotificationManager.shared.refreshScheduledReminders(settings: settings)
        #endif
        return saved
    }

    /// 数据目录变化后（如 iOS 授权 iCloud 文件夹）重新加载
    func reload() {
        isReloading = true
        defer { isReloading = false }
        let acknowledge = PomodoroFileChanges.shared.explicitReloadAcknowledgement(for: fileURL)
        if let loaded = Self.loadFile(UserSettings.self, from: fileURL) {
            settings = loaded
            acknowledge()
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
            let jsonData = try PomodoroFileChanges.shared.readData(from: url)
            let decoded = try JSONDecoder().decode(type, from: jsonData)
            PomodoroFileChanges.shared.consume(url, data: jsonData)
            return decoded
        } catch {
            return nil
        }
    }
    
    private static func saveFile<T: Codable>(_ data: T, to url: URL) -> Bool {
        PomodoroFileChanges.shared.noteLocalMutation(url)
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
            try jsonData.write(to: url, options: .atomic)
            PomodoroDataDir.noteLocalWrite(url.lastPathComponent, data: jsonData)
            print("Saved to: \(url.path)")
            return true
        } catch {
            print("Error saving to \(url.path): \(error)")
            return false
        }
    }

    @discardableResult
    func saveProgress() -> Bool {
        let saved = Self.saveFile(blockProgress, to: progressFileURL)
        
        if let data = try? JSONEncoder().encode(blockProgress) {
            UserDefaults.standard.set(data, forKey: localBackupProgressKey)
        }
        return saved
    }

    @discardableResult
    func saveHistory() -> Bool {
        let saved = Self.saveFile(blockHistory, to: historyFileURL)
        
        if let data = try? JSONEncoder().encode(blockHistory) {
            UserDefaults.standard.set(data, forKey: localBackupHistoryKey)
        }
        return saved
    }

    @discardableResult
    func saveDailyBlocks() -> Bool {
        let saved = Self.saveFile(dailyBlocksHistory, to: dailyBlocksFileURL)
        
        if let data = try? JSONEncoder().encode(dailyBlocksHistory) {
            UserDefaults.standard.set(data, forKey: localBackupDailyBlocksKey)
        }
        return saved
    }

    /// 数据目录变化后（如 iOS 授权 iCloud 文件夹）重新加载全部三类数据
    func reload() {
        let acknowledgeProgress = PomodoroFileChanges.shared.explicitReloadAcknowledgement(for: progressFileURL)
        let acknowledgeHistory = PomodoroFileChanges.shared.explicitReloadAcknowledgement(for: historyFileURL)
        let acknowledgeDaily = PomodoroFileChanges.shared.explicitReloadAcknowledgement(for: dailyBlocksFileURL)
        if let loaded = Self.loadFile(BlockProgress.self, from: progressFileURL) {
            blockProgress = loaded
            acknowledgeProgress()
        } else if let data = UserDefaults.standard.data(forKey: localBackupProgressKey),
                  let decoded = try? JSONDecoder().decode(BlockProgress.self, from: data) {
            blockProgress = decoded
        } else {
            blockProgress = BlockProgress()
        }

        if let loaded = Self.loadFile([String: [BlockHistoryEntry]].self, from: historyFileURL) {
            blockHistory = loaded
            acknowledgeHistory()
        } else if let data = UserDefaults.standard.data(forKey: localBackupHistoryKey),
                  let decoded = try? JSONDecoder().decode([String: [BlockHistoryEntry]].self, from: data) {
            blockHistory = decoded
        } else {
            blockHistory = [:]
        }

        if let loaded = Self.loadFile(DailyBlocksHistory.self, from: dailyBlocksFileURL) {
            dailyBlocksHistory = loaded
            acknowledgeDaily()
        } else if let data = UserDefaults.standard.data(forKey: localBackupDailyBlocksKey),
                  let decoded = try? JSONDecoder().decode(DailyBlocksHistory.self, from: data) {
            dailyBlocksHistory = decoded
        } else {
            dailyBlocksHistory = [:]
        }

        resetIfNeeded()
        print("BlockProgress reloaded from: \(progressFileURL.path)")
    }

    private func todayKey(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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

    // Cached count is always derived from the owning calendar day's durable daily store.
    func updateBlockIndexFromTime(settings: UserSettings, date: Date = Date()) {
        let ranges = Array(settings.blockTimeRanges.prefix(settings.blockCount))
        let index = BlockProgress.getCurrentBlockIndex(timeRanges: ranges, date: date)
            ?? min(max(0, blockProgress.currentBlockIndex), settings.blockCount - 1)
        let key = todayKey(date: date)
        let saved = dailyBlocksHistory[key]?.blockProgress ?? []
        let count = saved.indices.contains(index) ? saved[index] : 0
        if blockProgress.currentBlockIndex != index || blockProgress.progressDate != key || blockProgress.blockPomoCounter != count {
            blockProgress.currentBlockIndex = index
            blockProgress.progressDate = key
            blockProgress.blockPomoCounter = count
            saveProgress()
        }
    }

    func recordPomoInCurrentBlock(settings: UserSettings, comboCompleted: Bool = false, date: Date = Date()) {
        updateBlockIndexFromTime(settings: settings, date: date)
        let key = todayKey(date: date)
        let index = blockProgress.currentBlockIndex
        var daily = dailyBlocksHistory[key] ?? DailyBlockProgress(
            date: key, blockProgress: Array(repeating: 0, count: settings.blockCount), blockGoals: settings.blockGoals
        )
        while daily.blockProgress.count <= index { daily.blockProgress.append(0) }
        daily.blockProgress[index] += 1
        daily.blockGoals = settings.blockGoals
        blockProgress.blockPomoCounter = daily.blockProgress[index]
        dailyBlocksHistory[key] = daily
        saveProgress()
        saveDailyBlocks()
        PlantJournal.shared.recordCompletion(blockIndex: index, completed: daily.blockProgress[index], comboCompleted: comboCompleted, date: date)
    }

    /// Reset the active block in both stores so the next completion cannot restore its old count.
    func resetCurrentBlockProgress(settings: UserSettings) {
        updateBlockIndexFromTime(settings: settings)
        let index = blockProgress.currentBlockIndex
        blockProgress.blockPomoCounter = 0
        saveProgress()
        let today = todayKey()
        if var daily = dailyBlocksHistory[today], daily.blockProgress.indices.contains(index) {
            daily.blockProgress[index] = 0
            dailyBlocksHistory[today] = daily
            saveDailyBlocks()
        }
    }

    // 放弃进行中的 pomo：只记枯萎，不增加完成数。
    func recordAbandonedPomo(settings: UserSettings) {
        updateBlockIndexFromTime(settings: settings)
        let index = blockProgress.currentBlockIndex
        let progress = dailyBlocksHistory[todayKey()]?.blockProgress ?? []
        let completed = progress.indices.contains(index) ? progress[index] : 0
        PlantJournal.shared.recordAbandonment(blockIndex: index, completed: completed)
    }

    /// Claim a block completion once per calendar date/index, including after reset/relaunch.
    @discardableResult
    func recordBlockComplete(settings: UserSettings, date: Date = Date()) -> Bool {
        let key = todayKey(date: date)
        let index = blockProgress.currentBlockIndex
        guard !(blockHistory[key] ?? []).contains(where: { $0.blockIndex == index && $0.isComplete }) else { return false }
        let counts = progress(settings: settings, date: date)
        let count = counts.indices.contains(index) ? counts[index] : 0
        guard count >= settings.blockPomoCount else { return false }
        let entry = BlockHistoryEntry(date: key, blockIndex: index, pomodoros: count, isComplete: true, completedAt: date)
        blockHistory[key, default: []].append(entry)
        saveHistory()
        return true
    }

    func getTodayBlockProgress(settings: UserSettings) -> [Int] { progress(settings: settings) }
    func progress(settings: UserSettings, date: Date = Date()) -> [Int] {
        var counts = dailyBlocksHistory[todayKey(date: date)]?.blockProgress ?? []
        while counts.count < settings.blockCount { counts.append(0) }
        return Array(counts.prefix(settings.blockCount))
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
        blockProgress.resetBlock()
        saveProgress()
        saveHistory()
        saveDailyBlocks()
        PlantJournal.shared.clear()
    }

    // 获取今天的块历史
    func getTodayBlocks() -> [BlockHistoryEntry] {
        return blockHistory[todayKey()] ?? []
    }
}

// MARK: - Top Three Manager (当天最重要的三件事 + 琐事，同步 Habitica)
#if os(macOS)
/// 主 App（非沙箱）→ 沙箱 widget 的数据桥。
/// macOS 强制 app extension 沙箱（pkd: "plug-ins must be sandboxed"），widget 无法直读
/// ~/Documents；主 App 把 Top3 快照写入 widget 容器的 Application Support/widget-data.json，
/// widget 在自己沙箱内读取合法。只写 widget 自己的容器，不影响任何其他数据。
enum WidgetBridge {
    static let widgetBundleId = "com.hermes.habitica-pomodoro.TodayTasksWidget"

    static func writeSnapshot(store: TopThreeStore) {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleId)/Data/Library/Application Support")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let storeData = try JSONEncoder().encode(store)
            let storeObj = try JSONSerialization.jsonObject(with: storeData)
            let snapshot: [String: Any] = [
                "updatedAt": Date().timeIntervalSince1970,
                "boundaryMinutes": SettingsManager.shared.settings.blockTimeRanges.first?.startMinutes ?? 0,
                "store": storeObj,
            ]
            let data = try JSONSerialization.data(withJSONObject: snapshot)
            try data.write(to: dir.appendingPathComponent("widget-data.json"), options: .atomic)
        } catch {
            print("WidgetBridge snapshot failed: \(error)")
        }
    }
}
#endif

class TopThreeManager: ObservableObject {
    static let shared = TopThreeManager()

    @Published var store: TopThreeStore { didSet { mutationGeneration += 1 } }
    @Published private(set) var syncInProgress = false
    @Published private(set) var syncMessage: String?
    private var mutationGeneration = 0
    private var syncingTasks = Set<UUID>()
    private var hasDeletionConflict = false

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
        #if os(macOS)
        // 首启即写 widget 快照（save() 未触发时 widget 也有数据）
        WidgetBridge.writeSnapshot(store: store)
        #endif
    }

    private static func loadFile<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        do {
            let jsonData = try PomodoroFileChanges.shared.readData(from: url)
            let decoded = try JSONDecoder().decode(type, from: jsonData)
            PomodoroFileChanges.shared.consume(url, data: jsonData)
            return decoded
        } catch {
            return nil
        }
    }

    @discardableResult
    func save() -> Bool {
        PomodoroFileChanges.shared.noteLocalMutation(fileURL)
        rememberCloudState()
        do {
            let url = fileURL
            let jsonData = try JSONEncoder().encode(store)
            UserDefaults.standard.set(jsonData, forKey: localBackupKey)
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try jsonData.write(to: url, options: .atomic)
            PomodoroDataDir.noteLocalWrite(url.lastPathComponent, data: jsonData)
            #if os(macOS)
            // 立即刷新桌面小组件（今日任务完成情况）；无 widget 时为空操作
            WidgetBridge.writeSnapshot(store: store)
            WidgetCenter.shared.reloadTimelines(ofKind: "TodayTasks")
            #endif
            print("TopThree saved to: \(url.path)")
            return true
        } catch {
            print("Error saving TopThree: \(error)")
            return false
        }
    }

    /// 数据目录变化后（如 iOS 授权 iCloud 文件夹）重新加载
    func reload() {
        let acknowledge = PomodoroFileChanges.shared.explicitReloadAcknowledgement(for: fileURL)
        if let loaded = Self.loadFile(TopThreeStore.self, from: fileURL) {
            store = loaded
            acknowledge()
        } else if PomodoroFileChanges.shared.fileExists(at: fileURL) {
            return // Keep an undecodable cloud revision pending rather than upgrade/write a backup over it.
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
        #if os(macOS)
        // iCloud 同步/目录切换重载后同步刷新 widget 快照
        WidgetBridge.writeSnapshot(store: store)
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayTasks")
        #endif
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
        prepareCloudAccount(settings: settings)
        guard index >= 0, index < store.categoryNames.count else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(" · "), !store.categoryNames.enumerated().contains(where: { $0.offset != index && $0.element == name }) else { return }
        let oldName = store.categoryNames[index]
        store.categoryNames[index] = name
        for (date, var day) in store.history where day.taskGroups.indices.contains(index) {
            for i in day.taskGroups[index].indices { day.taskGroups[index][i].syncPending = true }
            store.history[date] = day
        }
        rememberCloudState()
        for owner in Array(store.cloudStates.keys) {
            var state = store.cloudStates[owner]!
            if let tagId = state.categoryTagIds.removeValue(forKey: oldName) {
                state.categoryTagIds[name] = tagId
                state.pendingTagRenames[tagId] = name
            }
            store.cloudStates[owner] = state
        }
        if let state = store.cloudStates[store.cloudAccount] {
            store.categoryTagIds = state.categoryTagIds
            store.pendingTagRenames = state.pendingTagRenames
        }
        save()
        Task { @MainActor in await synchronize(settings: settings) }
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
        prepareCloudAccount(settings: settings)
        guard canAddTask(key: key, category: category, settings: settings) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ensureDay(key: key)
        var day = store.history[key]!
        let task = TopThreeTask(title: trimmed, syncPending: true, cloudAccount: HabiticaAPI.shared.cloudAccount(settings: settings))
        day.taskGroups[category].append(task)
        store.history[key] = day
        save()
        syncTaskToHabitica(task: task, category: category, key: key, settings: settings)
    }

    /// Resolve the UUID again at action time; a stale row may not edit its replacement.
    private func taskIndex(id: UUID, key: String, category: Int) -> Int? {
        guard category >= 0, let location = locate(id), location.key == key,
              location.category == category, let day = store.history[key],
              day.taskGroups.indices.contains(category) else { return nil }
        return day.taskGroups[category].firstIndex { $0.id == id && !$0.movedToToday }
    }

    func setTaskTitle(key: String, category: Int, id: UUID, title: String, settings: UserSettings) {
        prepareCloudAccount(settings: settings)
        guard isEditable(key: key, settings: settings),
              let index = taskIndex(id: id, key: key, category: category),
              var day = store.history[key] else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        day.taskGroups[category][index].title = trimmed
        day.taskGroups[category][index].syncPending = true
        store.history[key] = day
        save()
        let task = day.taskGroups[category][index]
        if !trimmed.isEmpty {
            syncTaskToHabitica(task: task, category: category, key: key, settings: settings)
        }
    }

    func toggleTask(key: String, category: Int, id: UUID, settings: UserSettings) {
        prepareCloudAccount(settings: settings)
        guard isEditable(key: key, settings: settings),
              let index = taskIndex(id: id, key: key, category: category),
              var day = store.history[key] else { return }
        day.taskGroups[category][index].isCompleted.toggle()
        day.taskGroups[category][index].syncPending = true
        store.history[key] = day
        save()
        let task = day.taskGroups[category][index]
        syncTaskToHabitica(task: task, category: category, key: key, settings: settings)
    }

    func getTasks(key: String, category: Int) -> [TopThreeTask] {
        if let day = store.history[key],
           day.taskGroups.indices.contains(category) {
            return day.taskGroups[category]
        }
        return []
    }

    // 统一删除任务（所有分类相同交互）
    func removeTask(key: String, category: Int, id: UUID, settings: UserSettings) {
        prepareCloudAccount(settings: settings)
        guard isEditable(key: key, settings: settings),
              let index = taskIndex(id: id, key: key, category: category),
              var day = store.history[key] else { return }
        let task = day.taskGroups[category].remove(at: index)
        if let owner = task.cloudAccount {
            if let remoteId = task.habiticaTaskId { queueDeletion(remoteId, account: owner) }
            else if let attempt = task.cloudCreateAttempt { queueDeletedAttempt(id: task.id, attempt: attempt, owner: owner) }
        }
        store.history[key] = day
        save()
        // Only the active owner may dispatch a deletion; other owners retain their tombstone.
        if task.cloudAccount == accountSignature(settings) {
            Task { @MainActor in await synchronize(settings: settings) }
        }
    }

    // MARK: 昨天未完成任务移动到今日

    func canMoveToToday(key: String, settings: UserSettings) -> Bool {
        return key == yesterdayKey(settings: settings)
    }

    @discardableResult
    func moveTaskToToday(fromKey: String, category: Int, id: UUID, settings: UserSettings) -> Bool {
        prepareCloudAccount(settings: settings)
        guard canMoveToToday(key: fromKey, settings: settings),
              let index = taskIndex(id: id, key: fromKey, category: category) else { return false }
        let todayK = todayKey(settings: settings)
        ensureDay(key: todayK)

        guard var srcDay = store.history[fromKey],
              srcDay.taskGroups.indices.contains(category),
              srcDay.taskGroups[category].indices.contains(index) else { return false }
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
        moved.syncPending = true
        dstDay.taskGroups[category].append(moved)

        // 标记昨天任务已移动
        srcDay.taskGroups[category][index].movedToToday = true
        store.history[fromKey] = srcDay
        store.history[todayK] = dstDay
        save()
        syncTaskToHabitica(task: moved, category: category, key: todayK, settings: settings)
        return true
    }

    // MARK: - Habitica 同步

    /// Ownership is independent of token/connection state. Keep every owner's mappings and queues.
    func prepareCloudAccount(settings: UserSettings) {
        guard let account = HabiticaAPI.shared.cloudAccount(settings: settings) else { return }
        var changed = false
        // Old versions kept raw host case/default ports/trailing slashes in the store-level owner.
        // Canonicalize those keys as well, so upgrading is not mistaken for an account switch.
        if let normalized = canonicalOwner(store.cloudAccount), normalized != store.cloudAccount {
            store.cloudAccount = normalized
            changed = true
        }
        for rawOwner in Array(store.cloudStates.keys) {
            guard let normalized = canonicalOwner(rawOwner), normalized != rawOwner,
                  let old = store.cloudStates.removeValue(forKey: rawOwner) else { continue }
            var state = store.cloudStates[normalized] ?? TopThreeCloudState()
            state.categoryTagIds.merge(old.categoryTagIds) { current, _ in current }
            state.pendingTagRenames.merge(old.pendingTagRenames) { current, _ in current }
            state.deletedCloudIds = Array(Set(state.deletedCloudIds + old.deletedCloudIds)).sorted()
            for intent in old.deletedCreateAttempts where !state.deletedCreateAttempts.contains(intent) {
                state.deletedCreateAttempts.append(intent)
            }
            store.cloudStates[normalized] = state
            changed = true
        }
        let legacyOwner = store.cloudAccount.isEmpty ? account : store.cloudAccount
        for (key, var day) in store.history {
            for g in day.taskGroups.indices {
                for t in day.taskGroups[g].indices {
                    let old = day.taskGroups[g][t].cloudAccount
                    let owner = old.flatMap(canonicalOwner) ?? old ?? legacyOwner
                    if old != owner {
                        day.taskGroups[g][t].cloudAccount = owner
                        changed = true
                    }
                }
            }
            if changed { store.history[key] = day }
        }
        if store.cloudAccount != account {
            if store.cloudAccount.isEmpty {
                store.cloudStates[account] = TopThreeCloudState(categoryTagIds: store.categoryTagIds,
                    deletedCloudIds: store.deletedCloudIds, pendingTagRenames: store.pendingTagRenames,
                    deletedCreateAttempts: store.deletedCreateAttempts)
            } else { rememberCloudState() }
            let state = store.cloudStates[account] ?? TopThreeCloudState()
            store.categoryTagIds = state.categoryTagIds
            store.deletedCloudIds = state.deletedCloudIds
            store.pendingTagRenames = state.pendingTagRenames
            store.deletedCreateAttempts = state.deletedCreateAttempts
            store.cloudAccount = account
            changed = true
        }
        if changed { save() }
    }

    private func canonicalOwner(_ value: String) -> String? {
        let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let root = HabiticaAPI.shared.configure(serverUrlOverride: String(parts[1]))
        return root.isEmpty ? nil : "\(parts[0])|\(root)"
    }

    private func rememberCloudState() {
        guard !store.cloudAccount.isEmpty else { return }
        store.cloudStates[store.cloudAccount] = TopThreeCloudState(categoryTagIds: store.categoryTagIds,
            deletedCloudIds: store.deletedCloudIds, pendingTagRenames: store.pendingTagRenames,
            deletedCreateAttempts: store.deletedCreateAttempts)
    }

    private func queueDeletion(_ remote: String, account: String) {
        if account == store.cloudAccount {
            if !store.deletedCloudIds.contains(remote) { store.deletedCloudIds.append(remote) }
        } else {
            var state = store.cloudStates[account] ?? TopThreeCloudState()
            if !state.deletedCloudIds.contains(remote) { state.deletedCloudIds.append(remote) }
            store.cloudStates[account] = state
        }
    }

    private func cloudState(owner: String) -> TopThreeCloudState {
        if owner == store.cloudAccount {
            return TopThreeCloudState(categoryTagIds: store.categoryTagIds, deletedCloudIds: store.deletedCloudIds,
                pendingTagRenames: store.pendingTagRenames, deletedCreateAttempts: store.deletedCreateAttempts)
        }
        return store.cloudStates[owner] ?? TopThreeCloudState()
    }

    private func queueDeletedAttempt(id: UUID, attempt: CloudCreateAttempt, owner: String) {
        let intent = DeletedCloudCreateAttempt(id: id, attempt: attempt)
        if owner == store.cloudAccount {
            if !store.deletedCreateAttempts.contains(intent) { store.deletedCreateAttempts.append(intent) }
        } else {
            var state = cloudState(owner: owner)
            if !state.deletedCreateAttempts.contains(intent) { state.deletedCreateAttempts.append(intent) }
            store.cloudStates[owner] = state
        }
    }

    /// Checking settings alone misses A→B→A while the active store still belongs to B.
    private func isActiveOwner(_ owner: String) -> Bool {
        !owner.isEmpty && store.cloudAccount == owner && accountSignature(SettingsManager.shared.settings) == owner
    }

    // 确保分类对应的 Habitica tag 存在，返回 tag id
    @MainActor
    func ensureTagId(category: Int, settings: UserSettings) async -> String? {
        let owner = accountSignature(settings)
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty,
              isActiveOwner(owner), store.categoryNames.indices.contains(category) else { return nil }
        let name = categoryName(index: category)
        if let cached = cloudState(owner: owner).categoryTagIds[name], !cached.isEmpty {
            if cloudState(owner: owner).pendingTagRenames[cached] != nil {
                await retryTagRenames(owner: owner, settings: settings)
                guard isActiveOwner(owner), categoryName(index: category) == name,
                      cloudState(owner: owner).pendingTagRenames[cached] == nil else { return nil }
            }
            return cached
        }
        let fetched = await HabiticaAPI.shared.fetchTags(settings: settings)
        guard isActiveOwner(owner), categoryName(index: category) == name, let tags = fetched else { return nil }
        let tagId: String?
        if let existing = tags.first(where: { $0.value == name }) {
            tagId = existing.key
        } else {
            // Keep the owner check between lookup and POST instead of hiding that await
            // inside ensureTag(), where the active task store cannot be checked.
            tagId = await HabiticaAPI.shared.createTag(name: name, settings: settings)
            guard isActiveOwner(owner), categoryName(index: category) == name else { return nil }
        }
        guard let tagId = tagId else { return nil }
        store.categoryTagIds[name] = tagId
        save()
        return tagId
    }

    @MainActor
    private func retryTagRenames(owner: String, settings: UserSettings) async {
        guard isActiveOwner(owner), accountSignature(settings) == owner else { return }
        for (id, desired) in cloudState(owner: owner).pendingTagRenames {
            guard isActiveOwner(owner), cloudState(owner: owner).pendingTagRenames[id] == desired else { return }
            let tags = await HabiticaAPI.shared.fetchTags(settings: settings)
            guard isActiveOwner(owner), let tags = tags else { return }
            if tags[id] != desired {
                let renamed = await HabiticaAPI.shared.renameTag(tagId: id, name: desired, settings: settings)
                guard isActiveOwner(owner) else { return }
                guard renamed else { continue }
                let verified = await HabiticaAPI.shared.fetchTags(settings: settings)
                guard isActiveOwner(owner) else { return }
                guard verified?[id] == desired else { continue }
            }
            if cloudState(owner: owner).pendingTagRenames[id] == desired {
                store.pendingTagRenames.removeValue(forKey: id)
                save()
            }
        }
    }

    private func accountSignature(_ settings: UserSettings) -> String {
        HabiticaAPI.shared.cloudAccount(settings: settings) ?? ""
    }
    private func locate(_ id: UUID) -> (key: String, category: Int, task: TopThreeTask)? {
        // Prefer the latest moved copy, whose completion state is authoritative.
        for key in store.history.keys.sorted().reversed() {
            guard let day = store.history[key] else { continue }
            for (category, tasks) in day.taskGroups.enumerated() {
                if let task = tasks.first(where: { $0.id == id && !$0.movedToToday }) { return (key, category, task) }
            }
        }
        return nil
    }

    private func syncTaskToHabitica(task: TopThreeTask, category: Int, key: String, settings: UserSettings) {
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty else { return }
        Task { @MainActor in await pushTask(id: task.id, settings: settings) }
    }

    private func updateCopies(id: UUID, owner: String, _ update: (inout TopThreeTask) -> Void) {
        for (key, var day) in store.history {
            for g in day.taskGroups.indices {
                for t in day.taskGroups[g].indices where day.taskGroups[g][t].id == id && day.taskGroups[g][t].cloudAccount == owner {
                    update(&day.taskGroups[g][t])
                }
            }
            store.history[key] = day
        }
    }

    private func sameAttempt(_ lhs: CloudCreateAttempt, _ rhs: CloudCreateAttempt) -> Bool {
        lhs.title == rhs.title && lhs.notes == rhs.notes && Set(lhs.tags) == Set(rhs.tags)
    }

    private func matches(_ todo: HabiticaAPI.CloudTodo, attempt: CloudCreateAttempt) -> Bool {
        todo.title == attempt.title && todo.notes == attempt.notes && Set(todo.tags) == Set(attempt.tags)
    }

    private func attemptCandidateIds(_ attempt: CloudCreateAttempt, owner: String) -> Set<UUID> {
        let tasks = store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }
        let live = tasks.filter { task in
            task.cloudAccount == owner && task.habiticaTaskId == nil &&
                task.cloudCreateAttempt.map { sameAttempt($0, attempt) } == true
        }.map(\.id)
        let removed = cloudState(owner: owner).deletedCreateAttempts.filter { sameAttempt($0.attempt, attempt) }.map(\.id)
        return Set(live + removed)
    }

    private func remoteIsAvailable(_ remote: String, id: UUID, owner: String) -> Bool {
        !remote.isEmpty && !cloudState(owner: owner).deletedCloudIds.contains(remote) &&
            !store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }.contains {
                $0.cloudAccount == owner && $0.id != id && $0.habiticaTaskId == remote
            }
    }

    /// Do not guess between identical ambiguous POSTs or steal an ID already mapped to another UUID.
    private func matchingAttempt(_ attempt: CloudCreateAttempt, id: UUID, owner: String, todos: [HabiticaAPI.CloudTodo]) -> [HabiticaAPI.CloudTodo] {
        guard !hasReservedDeletionMarker(attempt, id: id, owner: owner) else { return [] }
        return todos.filter { remoteIsAvailable($0.id, id: id, owner: owner) && matches($0, attempt: attempt) }
    }

    private func hasReservedDeletionMarker(_ attempt: CloudCreateAttempt, id: UUID, owner: String) -> Bool {
        cloudState(owner: owner).deletedCreateAttempts.contains {
            $0.id != id && $0.attempt.notes == attempt.notes && Set($0.attempt.tags) == Set(attempt.tags)
        }
    }

    /// Called only in a non-suspending MainActor segment, immediately before binding or deleting.
    @MainActor
    private func canBind(_ remote: String, attempt: CloudCreateAttempt, id: UUID, owner: String) -> Bool {
        isActiveOwner(owner) && attemptCandidateIds(attempt, owner: owner) == Set([id]) &&
            !hasReservedDeletionMarker(attempt, id: id, owner: owner) &&
            remoteIsAvailable(remote, id: id, owner: owner)
    }

    /// A unique unresolved removal becomes an owner tombstone before any import or task POST.
    @MainActor
    private func resolveDeletedAttempts(_ todos: [HabiticaAPI.CloudTodo], owner: String) -> Bool {
        guard isActiveOwner(owner) else { return false }
        var resolved: [DeletedCloudCreateAttempt] = []
        for intent in cloudState(owner: owner).deletedCreateAttempts {
            let candidates = matchingAttempt(intent.attempt, id: intent.id, owner: owner, todos: todos)
            guard candidates.count == 1, let remote = candidates.first?.id,
                  canBind(remote, attempt: intent.attempt, id: intent.id, owner: owner) else { continue }
            queueDeletion(remote, account: owner)
            resolved.append(intent)
        }
        guard !resolved.isEmpty else { return true }
        store.deletedCreateAttempts.removeAll { resolved.contains($0) }
        return save()
    }

    @MainActor
    private func pushTask(id: UUID, settings: UserSettings) async {
        let owner = accountSignature(settings)
        guard isActiveOwner(owner), !syncingTasks.contains(id), let location = locate(id),
              location.task.syncPending, location.task.cloudAccount == owner else { return }
        syncingTasks.insert(id)
        defer { syncingTasks.remove(id) }
        for _ in 0..<4 {
            guard isActiveOwner(owner), let current = locate(id), current.task.syncPending,
                  current.task.cloudAccount == owner else { return }
            let task = current.task
            let categoryName = categoryName(index: current.category)
            let tagResult = await ensureTagId(category: current.category, settings: settings)
            guard isActiveOwner(owner), let tag = tagResult, let afterTag = locate(id),
                  afterTag.task.cloudAccount == owner else { return }
            guard afterTag.task == task, afterTag.key == current.key, afterTag.category == current.category,
                  self.categoryName(index: current.category) == categoryName else { continue }
            let notes = "From HabiticaPomodoro Top3 · \(categoryName) · \(current.key)"
            var remoteId = task.habiticaTaskId
            if remoteId == nil {
                let attempt: CloudCreateAttempt
                if let original = task.cloudCreateAttempt {
                    attempt = original
                    let fetched = await HabiticaAPI.shared.fetchTopThreeTodos(settings: settings)
                    guard isActiveOwner(owner), let todos = fetched else { return }
                    // Recompute after the fetch: a second local UUID may have acquired this attempt.
                    guard attemptCandidateIds(original, owner: owner) == Set([id]) else { return }
                    let candidates = matchingAttempt(original, id: id, owner: owner, todos: todos)
                    // Absence is not proof that a response-lost POST failed. Never blindly re-POST.
                    guard candidates.count == 1 else { return }
                    remoteId = candidates.first?.id
                } else {
                    attempt = CloudCreateAttempt(title: task.title, notes: notes, tags: [tag])
                    // Removed attempts with this marker also reserve it until uniquely resolved.
                    guard !hasReservedDeletionMarker(attempt, id: id, owner: owner) else { return }
                    guard attemptCandidateIds(attempt, owner: owner).subtracting([id]).isEmpty else { return }
                    updateCopies(id: id, owner: owner) { $0.cloudCreateAttempt = attempt }
                    guard save() else { return } // Durable exact version BEFORE dispatch.
                    remoteId = await HabiticaAPI.shared.createTodo(text: task.title, notes: notes, tagIds: [tag], settings: settings)
                    guard isActiveOwner(owner) else { return }
                }
                guard let created = remoteId,
                      canBind(created, attempt: attempt, id: id, owner: owner) else { return }
                // The occupancy check and binding/deletion have no intervening await.
                guard let latest = locate(id), latest.task.cloudAccount == owner else {
                    guard cloudState(owner: owner).deletedCreateAttempts.contains(where: { $0.id == id && sameAttempt($0.attempt, attempt) }) else { return }
                    queueDeletion(created, account: owner)
                    store.deletedCreateAttempts.removeAll { $0.id == id && sameAttempt($0.attempt, attempt) }
                    save()
                    return
                }
                guard latest.task.habiticaTaskId == nil,
                      latest.task.cloudCreateAttempt.map({ sameAttempt($0, attempt) }) == true else { return }
                updateCopies(id: id, owner: owner) { $0.habiticaTaskId = created; $0.cloudCreateAttempt = nil }
                guard save() else { return }
            }
            guard let remote = remoteId else { return }
            var expected = task
            expected.habiticaTaskId = remote
            expected.cloudCreateAttempt = nil
            // Identity loss is terminal; a changed revision instead restarts from the current row.
            // These checks and each following dispatch share a non-suspending MainActor segment.
            func hasIdentity() -> Bool {
                guard isActiveOwner(owner), remoteIsAvailable(remote, id: id, owner: owner),
                      let latest = locate(id) else { return false }
                return latest.task.cloudAccount == owner && latest.task.habiticaTaskId == remote
            }
            func hasRevision(_ generation: Int) -> Bool {
                guard generation == mutationGeneration, let latest = locate(id) else { return false }
                return latest.task == expected && latest.key == current.key && latest.category == current.category &&
                    self.categoryName(index: latest.category) == categoryName && store.categoryTagIds[categoryName] == tag
            }
            guard hasIdentity() else { return }
            let revision = mutationGeneration
            guard hasRevision(revision) else { continue }
            let updated = await HabiticaAPI.shared.updateTodo(taskId: remote, text: task.title, tagIds: [tag], notes: notes, settings: settings)
            guard hasIdentity(), updated else { return }
            guard hasRevision(revision) else { continue }
            let fetched = await HabiticaAPI.shared.fetchTopThreeTodos(settings: settings)
            guard hasIdentity(), let todos = fetched,
                  let todo = todos.first(where: { $0.id == remote }) else { return }
            guard hasRevision(revision) else { continue }
            if todo.completed != task.isCompleted {
                let scored = await HabiticaAPI.shared.scoreTodo(taskId: remote, completed: task.isCompleted, settings: settings)
                guard hasIdentity(), scored else { return }
                guard hasRevision(revision) else { continue }
            }
            // A successful PUT/score is not an acknowledgement: read back the entire pushed version.
            let verified = await HabiticaAPI.shared.fetchTopThreeTodos(settings: settings)
            guard hasIdentity(), let confirmation = verified?.first(where: { $0.id == remote }) else { return }
            guard hasRevision(revision) else { continue }
            guard confirmation.title == task.title, confirmation.completed == task.isCompleted,
                  confirmation.notes == notes, Set(confirmation.tags) == Set([tag]) else { return }
            updateCopies(id: id, owner: owner) { $0.syncPending = false }
            save()
            return
        }
    }

    static func parseOwnedNotes(_ notes: String) -> (category: String, date: String)? {
        let prefix = "From HabiticaPomodoro Top3 · "
        guard notes.hasPrefix(prefix) else { return nil }
        let parts = String(notes.dropFirst(prefix.count)).components(separatedBy: " · ")
        guard parts.count == 2, !parts[0].isEmpty,
              parts[0] == parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
              parts[1].range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: parts[1]), formatter.string(from: date) == parts[1] else { return nil }
        return (parts[0], parts[1])
    }

    /// No deletes inferred from an incomplete list. Dirty records, quotas and owner tombstones win.
    @MainActor
    @discardableResult
    func mergeOwnedTodos(_ todos: [HabiticaAPI.CloudTodo], owner: String) -> Int {
        guard isActiveOwner(owner), resolveDeletedAttempts(todos, owner: owner) else { return 0 }
        hasDeletionConflict = false
        var imported = 0
        for todo in todos {
            guard !todo.id.isEmpty, !todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !cloudState(owner: owner).deletedCloudIds.contains(todo.id),
                  let marker = Self.parseOwnedNotes(todo.notes) else { continue }
            var tasks = store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }.filter { $0.cloudAccount == owner }
            // Title is mutable: notes/tags quarantine an unknown ID, never establish identity.
            // Already-bound lawful tasks remain protected by UUID/ID and may still merge.
            if !tasks.contains(where: { $0.habiticaTaskId == todo.id }),
               cloudState(owner: owner).deletedCreateAttempts.contains(where: {
                   todo.notes == $0.attempt.notes && Set(todo.tags) == Set($0.attempt.tags)
               }) {
                hasDeletionConflict = true
                continue
            }
            // Recover a response-lost POST without importing a second UUID. Pending local version wins.
            if !tasks.contains(where: { $0.habiticaTaskId == todo.id }) {
                let candidates = Set(tasks.filter {
                    guard $0.habiticaTaskId == nil, let attempt = $0.cloudCreateAttempt else { return false }
                    return matchingAttempt(attempt, id: $0.id, owner: owner, todos: todos).count == 1 &&
                        matchingAttempt(attempt, id: $0.id, owner: owner, todos: todos).first?.id == todo.id
                }.map(\.id))
                if candidates.count == 1, let id = candidates.first,
                   let attempt = tasks.first(where: { $0.id == id })?.cloudCreateAttempt,
                   canBind(todo.id, attempt: attempt, id: id, owner: owner) {
                    updateCopies(id: id, owner: owner) { $0.habiticaTaskId = todo.id; $0.cloudCreateAttempt = nil }
                } else if tasks.contains(where: {
                    guard $0.habiticaTaskId == nil, let attempt = $0.cloudCreateAttempt else { return false }
                    return todo.title == attempt.title && todo.notes == attempt.notes && Set(todo.tags) == Set(attempt.tags)
                }) { continue }
                tasks = store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }.filter { $0.cloudAccount == owner }
            }
            let matchingTags = store.categoryNames.indices.filter { i in
                store.categoryTagIds[store.categoryNames[i]].map { todo.tags.contains($0) } ?? false
            }
            guard let category = store.categoryNames.firstIndex(of: marker.category) ?? (matchingTags.count == 1 ? matchingTags.first : nil) else { continue }
            let known = tasks.first(where: { $0.habiticaTaskId == todo.id && !$0.movedToToday })
            if let known = known, known.syncPending { continue }
            // A deleted active row may still have archived moved copies: never resurrect it.
            if known == nil && tasks.contains(where: { $0.habiticaTaskId == todo.id }) { continue }
            let source = known.flatMap { locate($0.id) }
            let targetTasks = getTasks(key: marker.date, category: category)
            if source?.key != marker.date || source?.category != category {
                if let limit = taskLimit(category: category), targetTasks.filter({ $0.id != known?.id }).count >= limit { continue }
            }
            var merged = known ?? TopThreeTask(title: todo.title, habiticaTaskId: todo.id, cloudAccount: owner)
            merged.title = todo.title
            merged.isCompleted = todo.completed
            merged.movedToToday = false
            if let source = source, source.key != marker.date || source.category != category,
               var oldDay = store.history[source.key],
               let index = oldDay.taskGroups[source.category].firstIndex(where: { $0.id == merged.id && !$0.movedToToday }) {
                if source.key != marker.date {
                    // Keep the old day's row as a moved archive with its original UUID and values.
                    oldDay.taskGroups[source.category][index].movedToToday = true
                } else { oldDay.taskGroups[source.category].remove(at: index) }
                store.history[source.key] = oldDay
            }
            ensureDay(key: marker.date)
            var destination = store.history[marker.date]!
            if let index = destination.taskGroups[category].firstIndex(where: { $0.id == merged.id }) {
                destination.taskGroups[category][index] = merged
            } else { destination.taskGroups[category].append(merged) }
            store.history[marker.date] = destination
            if known == nil { imported += 1 }
        }
        save()
        if hasDeletionConflict { syncMessage = "云端任务与未解决的删除意图冲突，已隔离；请人工核对。" }
        return imported
    }

    @MainActor
    func synchronize(settings: UserSettings) async {
        let owner = accountSignature(settings)
        guard settings.connectHabitica, !settings.uid.isEmpty, !settings.apiToken.isEmpty,
              !owner.isEmpty, accountSignature(SettingsManager.shared.settings) == owner else { return }
        prepareCloudAccount(settings: settings)
        guard isActiveOwner(owner), !syncInProgress else { return }
        syncInProgress = true
        defer { syncInProgress = false }
        // Resolve removed response-lost POSTs first; unresolved markers reserve their UUIDs.
        if !cloudState(owner: owner).deletedCreateAttempts.isEmpty {
            let generation = mutationGeneration
            let fetched = await HabiticaAPI.shared.fetchTopThreeTodos(settings: settings)
            guard isActiveOwner(owner), let todos = fetched, generation == mutationGeneration,
                  resolveDeletedAttempts(todos, owner: owner) else { return }
        }
        await retryTagRenames(owner: owner, settings: settings)
        guard isActiveOwner(owner) else { return }
        let pending = Set(store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }
            .filter { $0.syncPending && $0.cloudAccount == owner }.map(\.id))
        for id in pending {
            guard isActiveOwner(owner) else { return }
            await pushTask(id: id, settings: settings)
            guard isActiveOwner(owner) else { return }
        }
        for id in cloudState(owner: owner).deletedCloudIds {
            guard isActiveOwner(owner) else { return }
            _ = await HabiticaAPI.shared.deleteTodo(taskId: id, settings: settings)
            guard isActiveOwner(owner) else { return }
        }
        guard isActiveOwner(owner) else { return }
        let generation = mutationGeneration
        let fetched = await HabiticaAPI.shared.fetchTopThreeTodos(settings: settings)
        guard isActiveOwner(owner) else { return }
        guard let todos = fetched else {
            syncMessage = "同步失败，已保留本机任务；稍后可重试。"
            return
        }
        guard generation == mutationGeneration else {
            syncMessage = "同步期间本机任务有修改，未采用旧响应，请再刷新。"
            return
        }
        let count = mergeOwnedTodos(todos, owner: owner)
        if hasDeletionConflict { return } // Do not overwrite manual-review feedback with success.
        let state = cloudState(owner: owner)
        let stillPending = !state.pendingTagRenames.isEmpty || !state.deletedCreateAttempts.isEmpty ||
            store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }.contains { $0.syncPending && $0.cloudAccount == owner }
        syncMessage = stillPending ? "已合并云端任务；本机仍有待上传修改。" : "已同步 · 新导入 \(count) 个任务"
    }

}

extension Notification.Name {
    static let histogramChanged = Notification.Name("histogramChanged")
}

// MARK: - Histogram Manager
class HistogramManager: ObservableObject {
    static let shared = HistogramManager()

    @Published var histogram: Histogram

    private let key = "habitica_pomodoro_histogram" // keep the original backup key for migration
    private let fileName = "habitica_pomodoro_histogram.json"
    private var fileURL: URL { PomodoroDataDir.fileURL(fileName) }
    private var loadedHistogram: Histogram = [:]
    private var loadedData: Data?
    private var loadedPath: String?

    private static func backupPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func rememberBackup(_ data: Data, at url: URL) {
        let key = "habitica_pomodoro_histogram"
        let path = backupPath(url)
        var backups = UserDefaults.standard.dictionary(forKey: key + "_backupsByPath") ?? [:]
        backups[path] = data
        UserDefaults.standard.set(backups, forKey: key + "_backupsByPath")
        // Atomic (data, path) pair in ONE write: a crash between writes can never leave
        // new data paired with a stale recorded path (or vice versa).
        UserDefaults.standard.set(["path": path, "data": data], forKey: key + "_backupEntry")
        // Legacy contract for older readers (best-effort; no longer the recovery source of truth).
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.set(path, forKey: key + "_backupPath")
    }

    private static func backup(at url: URL) -> Histogram? {
        let key = "habitica_pomodoro_histogram"
        let path = backupPath(url)
        var data = UserDefaults.standard.dictionary(forKey: key + "_backupsByPath")?[path] as? Data
        // Prefer the atomic entry: its data is only ever paired with its own path.
        if data == nil,
           let entry = UserDefaults.standard.dictionary(forKey: key + "_backupEntry"),
           (entry["path"] as? String) == path {
            data = entry["data"] as? Data
        }
        let legacyPath = UserDefaults.standard.string(forKey: key + "_backupPath")
        // Ownerless old backup belongs only to the original sandbox/Documents store, not a grant.
        // Require explicit proof the legacy backup matches the target path; absence of metadata
        // means unknown provenance and must not be auto-attributed.
        if data == nil, legacyPath == path {
            data = UserDefaults.standard.data(forKey: key)
        }
        return data.flatMap { try? JSONDecoder().decode(Histogram.self, from: $0) }
    }

    init() {
        let url = PomodoroDataDir.fileURL("habitica_pomodoro_histogram.json")
        if let data = try? PomodoroFileChanges.shared.readData(from: url), let decoded = try? JSONDecoder().decode(Histogram.self, from: data) {
            histogram = decoded
            loadedHistogram = decoded
            loadedData = data
            loadedPath = url.path
            PomodoroFileChanges.shared.consume(url, data: data)
            Self.rememberBackup(data, at: url)
        } else if let decoded = Self.backup(at: url) {
            histogram = decoded
            // Only migrate when absent, never overwrite an unreadable existing file.
            if !PomodoroFileChanges.shared.fileExists(at: url) { save() }
        } else { histogram = [:] }
        loadedHistogram = histogram
        loadedPath = url.path
    }

    func reload() {
        let url = fileURL
        let samePath = loadedPath == url.path
        let acknowledge = PomodoroFileChanges.shared.explicitReloadAcknowledgement(for: url)
        var replacedDirtyState = false
        if let data = try? PomodoroFileChanges.shared.readData(from: url), let decoded = try? JSONDecoder().decode(Histogram.self, from: data) {
            // Same-path reload merges unsaved deltas rather than discarding them.
            replacedDirtyState = !samePath || histogram == loadedHistogram
            histogram = samePath ? mergingUnwrittenChanges(into: decoded) : decoded
            loadedHistogram = decoded
            loadedData = data
            loadedPath = url.path
            PomodoroFileChanges.shared.consume(url, data: data)
            Self.rememberBackup(data, at: url)
        } else if samePath && PomodoroFileChanges.shared.fileExists(at: url) {
            return // Same-path corruption retains unsaved cache, without acknowledging bad bytes.
        } else {
            // A directory switch must never display or apply deltas from the previous folder.
            histogram = Self.backup(at: url) ?? [:]
            loadedHistogram = histogram
            loadedData = nil
            loadedPath = url.path
        }
        NotificationCenter.default.post(name: .histogramChanged, object: nil)
        if replacedDirtyState { acknowledge() }
    }

    /// Narrow read-before-write protection, not a distributed conflict-resolution protocol.
    /// Untouched days come from disk; unsaved local increments are applied as deltas to that file.
    private func mergingUnwrittenChanges(into remote: Histogram) -> Histogram {
        var merged = remote
        for date in Set(loadedHistogram.keys).union(histogram.keys) {
            let local = histogram[date]
            let base = loadedHistogram[date]
            guard local != base else { continue }
            guard let local = local else { merged.removeValue(forKey: date); continue }
            var day = remote[date] ?? DayHistogram(pomodoros: 0, minutes: 0, weekday: local.weekday)
            day.pomodoros = max(0, day.pomodoros + local.pomodoros - (base?.pomodoros ?? 0))
            day.minutes = max(0, day.minutes + local.minutes - (base?.minutes ?? 0))
            if day.weekday.isEmpty { day.weekday = local.weekday }
            merged[date] = day
        }
        return merged
    }
    func todayKey(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    func weekday(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
    func getToday() -> DayHistogram? { histogram[todayKey()] }
    func incrementToday(pomodoros: Int, minutes: Int, date: Date = Date()) {
        let dateKey = todayKey(date: date)
        var day = histogram[dateKey] ?? DayHistogram(pomodoros: 0, minutes: 0, weekday: weekday(date: date))
        day.pomodoros += pomodoros
        day.minutes += minutes
        histogram[dateKey] = day
        save()
    }
    func clear() {
        reload() // Consume any arrived file before the user's explicit destructive clear.
        histogram = [:]
        save(replacingAll: true)
        // Update the timer's cached Today count too.
        NotificationCenter.default.post(name: .histogramChanged, object: nil)
    }
    @discardableResult
    func save(replacingAll: Bool = false) -> Bool {
        PomodoroFileChanges.shared.noteLocalMutation(fileURL)
        if loadedPath != fileURL.path {
            reload()
            // The explicit path replacement may acknowledge the previous dirty value;
            // this save attempt must still own dirty protection if its write fails.
            PomodoroFileChanges.shared.noteLocalMutation(fileURL)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let disk = try? Data(contentsOf: fileURL),
                  let remote = try? JSONDecoder().decode(Histogram.self, from: disk) else {
                if let data = try? JSONEncoder().encode(histogram) { Self.rememberBackup(data, at: fileURL) }
                return false
            }
            if disk != loadedData || loadedPath != fileURL.path {
                if !replacingAll {
                    histogram = loadedPath == fileURL.path ? mergingUnwrittenChanges(into: remote) : remote
                }
                loadedHistogram = remote
                loadedData = disk
                loadedPath = fileURL.path
                PomodoroFileChanges.shared.consume(fileURL, data: disk)
            }
        }
        guard let data = try? JSONEncoder().encode(histogram) else { return false }
        Self.rememberBackup(data, at: fileURL)
        do {
            try data.write(to: fileURL, options: .atomic)
            loadedHistogram = histogram
            loadedData = data
            loadedPath = fileURL.path
            PomodoroDataDir.noteLocalWrite(fileName, data: data)
            NotificationCenter.default.post(name: .histogramChanged, object: nil)
            return true
        } catch {
            print("Error saving histogram: \(error)")
            return false
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
// MARK: - 栖时场景库（qishi_presets.json 随包快照；音频 macOS 优先本机栖时仓库、缺失走公开站流式，iOS 直接流式）

struct QishiTrack: Codable {
    let id: String
    let file: String
    let volume: Int   // 0-100，栖时调好的场景混音比例
}

struct QishiPreset: Codable {
    let id: String
    let name: String
    let subtitle: String
    let tracks: [QishiTrack]
}

struct QishiLibraryFile: Codable {
    let version: Int
    let presets: [QishiPreset]
}

enum QishiSceneStore {
    static let streamBase = "https://allen7wang.github.io/qishi-meditation-web/audio/"

    static let presets: [QishiPreset] = {
        let url = Bundle.main.url(forResource: "qishi_presets", withExtension: "json", subdirectory: "audio")
            ?? Bundle.main.url(forResource: "qishi_presets", withExtension: "json")
        guard let url = url, let data = try? Data(contentsOf: url),
              let lib = try? JSONDecoder().decode(QishiLibraryFile.self, from: data) else { return [] }
        return lib.presets
    }()

    static func audioURL(for file: String) -> URL? {
        #if os(macOS)
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("GitHub/qishi-meditation/public/audio").appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        #endif
        guard let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: streamBase + encoded)
    }

    /// 随机一个场景；候选多于一个时避开 excluding（不与上个番茄重复）
    static func randomPreset(excluding id: String?) -> QishiPreset? {
        guard !presets.isEmpty else { return nil }
        var pool = presets
        if let id = id, pool.count > 1 { pool.removeAll { $0.id == id } }
        return pool.randomElement()
    }
}

class AudioManager: ObservableObject {
    static let shared = AudioManager()

    private var ambientPlayer: AVAudioPlayer?
    private var soundPlayer: AVAudioPlayer?
    private var ambientFilename: String?
    // 栖时场景多轨播放（AVPlayer：本地文件与公开站流式统一支持；循环 = 播完 seek 0 重播）
    private var qishiPlayers: [(player: AVPlayer, trackVolume: Int)] = []
    private var qishiObservers: [NSObjectProtocol] = []
    private var qishiPaused = false
    private var qishiPreviewManager: AudioManager?
    private(set) var currentQishiSceneId: String?
    /// 跨番茄记忆：新番茄随机场景时避开上一个（stop 后保留）
    private(set) var lastQishiSceneId: String?
    @Published var lastError: String?

    // Sound file lists (mirror the extension)
    static let sounds = ["Sound1", "Sound2", "Sound3", "Sound4", "Sound5", "Sound6", "Sound7", "Sound8", "Sound9"]
    static let ambientSounds = ["Ambient Clock", "Ambient Rain", "Ambient Crickets", "Ambient Birds"]
    static var allSoundOptions: [String] { ["None"] + (sounds.map { "\($0).mp3" } + ["clockTicking.mp3"]).filter { bundledAudio($0) != nil } }
    static var allAmbientOptions: [String] { ["None"] + ambientSounds.map { "\($0).mp3" }.filter { bundledAudio($0) != nil } }

    private static func bundledAudio(_ filename: String) -> URL? {
        Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "audio") ?? Bundle.main.url(forResource: filename, withExtension: nil)
    }

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
        guard filename != "None" else { stopPreview(); return }
        lastError = nil
        guard let url = audioURL(filename) else { lastError = "音频文件不存在：\(filename)"; return }
        do {
            soundPlayer = try AVAudioPlayer(contentsOf: url)
            soundPlayer?.volume = Float(volume)
            soundPlayer?.play()
        } catch { lastError = "无法播放音效：\(error.localizedDescription)"; print("Audio error: \(error)") }
    }

    func playAmbient(sound: String, volume: Double) {
        guard sound != "None" else { stopAmbient(); return }
        if ambientFilename == sound, let player = ambientPlayer {
            player.volume = Float(min(1, max(0, volume)))
            if !player.isPlaying { player.play() }
            return
        }
        stopAmbient()
        ambientFilename = sound
        guard let url = audioURL(sound) else { lastError = "音频文件不存在：\(sound)"; return }
        do {
            ambientPlayer = try AVAudioPlayer(contentsOf: url)
            ambientPlayer?.numberOfLoops = -1
            ambientPlayer?.volume = Float(volume)
            ambientPlayer?.play()
        } catch { lastError = "无法播放环境音：\(error.localizedDescription)"; print("Ambient audio error: \(error)") }
    }

    /// Pause playback resources without discarding this focus session's scene or position.
    func pauseAmbient() {
        ambientPlayer?.pause()
        qishiPaused = true
        for entry in qishiPlayers { entry.player.pause() }
    }

    func stopAmbient() {
        ambientPlayer?.stop()
        ambientPlayer = nil
        ambientFilename = nil
        stopQishi()
    }

    // MARK: - 栖时随机场景（ambientSource == "qishi"）

    /// 统一环境音入口：qishi 模式每个番茄随机一个场景混音；custom 模式维持原单轨方案。
    /// newSession=true 在番茄开始时调用（换新场景，避开上个番茄）；
    /// false 在暂停恢复/回前台时调用（延续当前场景，只调音量或重播同一场景）。
    func playAmbientFor(settings: UserSettings, newSession: Bool) {
        if newSession { stopPreview() }
        guard settings.ambientSource == "qishi" else {
            stopQishi()
            playAmbient(sound: settings.ambientSound, volume: settings.ambientSoundVolume)
            return
        }
        // 停掉自定义单轨（若之前是 custom 模式）
        ambientPlayer?.stop(); ambientPlayer = nil; ambientFilename = nil
        let preset: QishiPreset?
        if !newSession, let id = currentQishiSceneId,
           let p = QishiSceneStore.presets.first(where: { $0.id == id }) {
            preset = p
        } else {
            preset = QishiSceneStore.randomPreset(excluding: lastQishiSceneId)
        }
        guard let chosen = preset else {
            lastError = "栖时场景库不可用（qishi_presets.json 缺失或为空）"
            return
        }
        if currentQishiSceneId == chosen.id, !qishiPlayers.isEmpty {
            setQishiVolume(settings.ambientSoundVolume)
            if qishiPaused {
                qishiPaused = false
                for entry in qishiPlayers { entry.player.play() }
            }
            return
        }
        playQishiScene(chosen, volume: settings.ambientSoundVolume)
    }

    private static func trackGain(_ trackVolume: Int, user: Double) -> Double {
        min(1, max(0, Double(trackVolume) / 100.0 * min(1, max(0, user))))
    }

    func playQishiScene(_ preset: QishiPreset, volume: Double) {
        stopQishi()
        for track in preset.tracks {
            guard let url = QishiSceneStore.audioURL(for: track.file) else { continue }
            let player = AVPlayer(url: url)
            player.volume = Float(Self.trackGain(track.volume, user: volume))
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { [weak self, weak player] _ in
                guard let self = self, let player = player,
                      self.qishiPlayers.contains(where: { $0.player === player }) else { return }
                // EOF can be delivered after pause. Keep the owned loop ready for resume,
                // but never restart playback while this focus session is paused.
                player.seek(to: .zero)
                if !self.qishiPaused { player.play() }
            }
            qishiObservers.append(observer)
            qishiPlayers.append((player, track.volume))
            player.play()
        }
        guard !qishiPlayers.isEmpty else {
            lastError = "栖时场景播放失败：\(preset.name)（音频不可用）"
            return
        }
        currentQishiSceneId = preset.id
        lastQishiSceneId = preset.id
        lastError = nil
    }

    /// 只调音量不重启播放（暂停恢复/设置变更）
    func setQishiVolume(_ volume: Double) {
        for entry in qishiPlayers {
            entry.player.volume = Float(Self.trackGain(entry.trackVolume, user: volume))
        }
    }

    func stopQishi() {
        for o in qishiObservers { NotificationCenter.default.removeObserver(o) }
        qishiObservers.removeAll()
        for entry in qishiPlayers { entry.player.pause(); entry.player.replaceCurrentItem(with: nil) }
        qishiPlayers.removeAll()
        qishiPaused = false
        currentQishiSceneId = nil
    }

    /// Preview has its own player owner and never changes focus scene identity/history.
    func playQishiPreview(_ preset: QishiPreset, volume: Double) {
        stopPreview()
        let preview = AudioManager()
        preview.playQishiScene(preset, volume: volume)
        qishiPreviewManager = preview
        lastError = preview.lastError
    }

    /// Settings disappearance and stop-preview release preview resources only.
    func stopPreview() {
        soundPlayer?.stop()
        soundPlayer = nil
        qishiPreviewManager?.stopAmbient()
        qishiPreviewManager = nil
    }
}

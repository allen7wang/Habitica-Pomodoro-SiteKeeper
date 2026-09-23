import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// iOS 端 iCloud Drive 文件夹授权管理。
///
/// 平台事实（已核实）：iOS 应用是强沙箱，无法自动读写 iCloud Drive 根目录；
/// 唯一受支持的入口是文档选择器（UIDocumentPickerViewController / SwiftUI.fileImporter），
/// 用户选一次目录 → 系统返回 security-scoped URL → 存成普通 bookmark（iOS 上没有
/// NSURLBookmarkCreationWithSecurityScope，picker 返回的 URL 本身已带 scope）→
/// 之后每次启动 resolve bookmark 即可恢复访问，无需再弹窗、无需任何 entitlement、
/// 无需付费开发者账号。授权范围是**递归**的，覆盖目录内所有子项（含隐藏目录）。
///
/// 注意：`.` 开头的文件夹在 iOS Files 选择器里不可见，所以用户选的是父级
/// （iCloud Drive → Documents），App 再在其中定位/创建 `.habitica-pomodoro`，
/// 与 macOS 端 `~/Documents/.habitica-pomodoro/` 指向同一批文件。
final class ICloudFolderGrant: ObservableObject {
    static let shared = ICloudFolderGrant()

    private let bookmarkKey = "habitica_pomodoro_icloud_folder_bookmark"
    private let fm = FileManager.default

    /// 用户授权的根目录（已 resolve bookmark 并 startAccessing）
    @Published private(set) var grantedRoot: URL?
    /// 供 UI 显示的人类可读状态
    @Published private(set) var statusText: String = "未连接"
    /// bookmark 失效（文件夹被移动/重命名，或用户在设置里撤销了授权）
    @Published private(set) var isStale: Bool = false

    private var didResolve = false

    private init() {
        resolveStoredBookmark()
        // 本地写入钩子：刷新基线，避免把自己的写入误判为云端变更
        PomodoroDataDir.onLocalWrite = { [weak self] in
            self?.refreshBaseline()
        }
    }

    // MARK: - 状态

    var isConnected: Bool { grantedRoot != nil }

    private static let dataFileNames = [
        "habitica_pomodoro_settings.json",
        "habitica_pomodoro_block_progress.json",
        "habitica_pomodoro_block_history.json",
        "habitica_pomodoro_daily_blocks.json",
        "habitica_pomodoro_top_three.json",
    ]

    /// 数据文件夹：在授权目录内定位 `.habitica-pomodoro`。
    ///
    /// Files 选择器里看不到 `.` 开头的隐藏文件夹，用户只能选父级，而父级可能是
    /// iCloud Drive 根，也可能是里面的 Documents —— 两者都合法，所以这里做智能定位：
    /// 1. 优先「已存在且有数据文件」的目录（保证接上 Mac 端已有的那批 JSON）
    /// 2. 其次「父级本身叫 Documents」时直接用 <root>/.habitica-pomodoro
    /// 3. 父级是 iCloud Drive 根且里面有 Documents 时，用 <root>/Documents/.habitica-pomodoro
    ///    （与 macOS 的 ~/Documents/.habitica-pomodoro 对齐，避免数据分叉）
    /// 4. 都不匹配才在 <root>/.habitica-pomodoro 新建
    var dataFolderURL: URL? {
        guard let root = grantedRoot else { return nil }
        let dir = Self.resolveDataFolder(under: root, fm: fm)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func resolveDataFolder(under root: URL, fm: FileManager) -> URL {
        let folder = PomodoroDataDir.folderName
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

    /// 数据目录里已存在的数据文件数量（用于 UI 反馈"是否接上了 Mac 的数据"）
    @Published private(set) var dataFileCount: Int = 0

    /// 授权根目录的显示名（iCloud Drive 里的 Documents 等）
    private var rootDisplayName: String {
        guard let root = grantedRoot else { return "" }
        let last = root.lastPathComponent
        // FileProvider 路径常以 "Documents" 结尾，用 iCloud Drive 前缀更易懂
        return last == "Documents" ? "iCloud Drive/Documents" : last
    }

    /// 数据目录的可读描述，如 "iCloud Drive/Documents/.habitica-pomodoro"
    var dataFolderDescription: String {
        guard let dir = dataFolderURL else { return "—" }
        return "\(rootDisplayName)/\(dir.lastPathComponent)"
    }

    private func refreshStatus() {
        guard grantedRoot != nil else {
            dataFileCount = 0
            statusText = "未连接"
            return
        }
        if let dir = dataFolderURL {
            dataFileCount = Self.dataFileNames.filter {
                fm.fileExists(atPath: dir.appendingPathComponent($0).path)
            }.count
        } else {
            dataFileCount = 0
        }
        if isStale {
            statusText = "授权已失效，请重新选择文件夹"
        } else if dataFileCount > 0 {
            statusText = "已连接：\(rootDisplayName) · 找到 \(dataFileCount) 个数据文件"
        } else {
            statusText = "已连接：\(rootDisplayName) · 暂无数据文件（首次使用或目录不对）"
        }
    }

    // MARK: - 授权（用户在文件选择器里选完目录后调用）

    /// 用 picker 返回的 security-scoped URL 建立持久 bookmark。
    @discardableResult
    func grant(from pickedURL: URL) -> Bool {
        // picker 返回的 URL 尚未 start，必须先 start 才能创建 bookmark
        //（否则 bookmarkData 不报错但内容是空的，resolve 后无法访问 —— 已知坑）
        let started = pickedURL.startAccessingSecurityScopedResource()

        do {
            let bookmark = try pickedURL.bookmarkData(options: [],
                                                      includingResourceValuesForKeys: nil,
                                                      relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            grantedRoot = pickedURL
            isStale = false
            refreshStatus()
            // 立刻确保数据文件夹存在
            _ = dataFolderURL
            print("[iCloud] 已授权文件夹: \(pickedURL.path) (startAccessing=\(started))")
            return true
        } catch {
            print("[iCloud] 创建 bookmark 失败: \(error)")
            if started { pickedURL.stopAccessingSecurityScopedResource() }
            return false
        }
    }

    /// 断开：清除 bookmark，回到 App 沙箱本地存储。
    func revoke() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        if let root = grantedRoot {
            root.stopAccessingSecurityScopedResource()
        }
        grantedRoot = nil
        isStale = false
        refreshStatus()
        print("[iCloud] 已断开授权")
    }

    // MARK: - 启动时恢复授权

    private func resolveStoredBookmark() {
        guard didResolve == false else { return }
        didResolve = true

        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            refreshStatus()
            return
        }

        var stale = false
        do {
            // resolve 不带 withoutImplicitStartAccessing：resolve 后 URL 带隐式临时 scope，
            // 再由我们 startAccessing 取得"所有权"，这是 Apple 文档要求的配对用法
            let url = try URL(resolvingBookmarkData: data,
                              options: [],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            let ok = url.startAccessingSecurityScopedResource()
            if ok || fm.fileExists(atPath: url.path) {
                grantedRoot = url
                isStale = stale
                if stale {
                    // stale bookmark 仍可能 resolve 出看似正确但写入失败的 URL；
                    // 按 Apple 建议：提示用户重新授权，同时保留访问以便尽量读取
                    print("[iCloud] bookmark 已失效(stale)，需重新选择文件夹")
                }
            } else {
                print("[iCloud] startAccessing 失败，授权可能已被撤销")
            }
        } catch {
            print("[iCloud] resolve bookmark 失败: \(error)")
        }
        refreshStatus()
        refreshBaseline()
    }

    /// bookmark 失效后重新生成（用当前仍可访问的 URL 刷新 bookmark）
    func refreshBookmarkIfNeeded() {
        guard isStale, let root = grantedRoot else { return }
        if let bookmark = try? root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            isStale = false
            refreshStatus()
            print("[iCloud] bookmark 已刷新")
        }
    }

    /// 调试/自动化入口：用命令行参数 -grantFolder <path> 授权指定文件夹，
    /// 与文件选择器走完全相同的 grant(from:) 代码路径。仅 DEBUG 构建生效。
    func handleLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-grantFolder"), i + 1 < args.count else { return }
        let path = args[i + 1]
        let url = URL(fileURLWithPath: path)
        if grant(from: url), verifyWritable() {
            reloadAllManagers()
            print("[iCloud] 启动参数授权成功: \(url.path)")
        } else {
            revoke()
            print("[iCloud] 启动参数授权失败: \(path)")
        }
        #endif
    }

    // MARK: - 远端变更检测（iCloud 同步下来 Mac 端的修改）
    //
    // iOS 沙箱内无法订阅 iCloud Drive 文件的推送变更，采用回前台轮询：
    // 对比数据目录 5 个 JSON 的 (修改时间, 大小) 快照，与基线不同则说明
    // Mac 端写入已经过 iCloud 同步下来，触发全部 Manager 重载。
    // 本地写入会通过 noteLocalWrite 钩子刷新基线，不会被误判。
    // （数据文件清单见上方 dataFileNames）

    private var baselineSnapshot: [String: (mtime: Date, size: Int64)] = [:]

    private func snapshot() -> [String: (mtime: Date, size: Int64)] {
        guard let dir = dataFolderURL else { return [:] }
        var snap: [String: (mtime: Date, size: Int64)] = [:]
        for name in Self.dataFileNames {
            let url = dir.appendingPathComponent(name)
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let mtime = attrs[.modificationDate] as? Date,
               let size = attrs[.size] as? NSNumber {
                snap[name] = (mtime, size.int64Value)
            }
        }
        return snap
    }

    /// 本地写入后刷新基线（PomodoroDataDir.noteLocalWrite → 这里）
    func refreshBaseline() {
        baselineSnapshot = snapshot()
    }

    /// 回前台检查：iCloud 是否同步来了新数据。有变更则重载全部 Manager。
    func syncFromCloudIfNeeded() {
        guard isConnected else { return }
        let current = snapshot()
        var changed = false
        for name in Self.dataFileNames {
            let now = current[name]
            let base = baselineSnapshot[name]
            switch (now, base) {
            case let (n?, b?):
                // mtime 或大小变了即视为远端修改（1 秒容差避免亚秒抖动）
                if abs(n.mtime.timeIntervalSince(b.mtime)) > 1.0 || n.size != b.size { changed = true }
            case (.some, .none):
                changed = true   // 新出现的文件（如 Mac 端首次生成）
            default:
                break            // 消失/都没有：不触发（删除场景由各自 load 回退兜底）
            }
        }
        if changed {
            print("[iCloud] 检测到云端数据变更，重新加载")
            reloadAllManagers()
        }
        baselineSnapshot = current
    }

    // MARK: - 连通性自检

    /// 写一个临时探针文件验证真的可写（授权被撤销时 fileExists 可能仍为真）
    func verifyWritable() -> Bool {
        guard let dir = dataFolderURL else { return false }
        let probe = dir.appendingPathComponent(".write_probe")
        do {
            try Data("ok".utf8).write(to: probe)
            try? fm.removeItem(at: probe)
            return true
        } catch {
            print("[iCloud] 写入自检失败: \(error)")
            return false
        }
    }

    // MARK: - 授权变更后重载数据

    /// 从（新的）数据目录重新加载所有 Manager 的持久化数据。
    /// iCloud 里的文件为准；不存在时回退各 Manager 的 UserDefaults 本地备份。
    func reloadAllManagers() {
        SettingsManager.shared.reload()
        BlockProgressManager.shared.reload()
        TopThreeManager.shared.reload()
        refreshBaseline()
    }
}

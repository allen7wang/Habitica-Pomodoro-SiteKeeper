// TodayTasksWidget — macOS 桌面小组件（中尺寸）
// 显示今天（逻辑日）Top3 任务完成进度：Work / MyOwn / Chores 各 done/total
//
// 数据读取：主 App 非沙箱，widget 进程直接读 ~/Documents/.habitica-pomodoro/ 的
// habitica_pomodoro_top_three.json（与主 App 同一份，iCloud Drive 自动同步）。
// 只读不写；movedToToday 归档行不计入今日统计。
import WidgetKit
import SwiftUI
import Foundation

// MARK: - 宽容解析（字段缺失给默认值，旧版 JSON 兼容）

struct WTask: Decodable {
    let title: String
    let isCompleted: Bool
    let movedToToday: Bool
    enum CodingKeys: String, CodingKey { case title, isCompleted, movedToToday }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        isCompleted = (try? c.decode(Bool.self, forKey: .isCompleted)) ?? false
        movedToToday = (try? c.decode(Bool.self, forKey: .movedToToday)) ?? false
    }
}

struct WDay: Decodable {
    let taskGroups: [[WTask]]
    enum CodingKeys: String, CodingKey { case taskGroups }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskGroups = (try? c.decode([[WTask]].self, forKey: .taskGroups)) ?? []
    }
}

struct WStore: Decodable {
    let categoryNames: [String]
    let history: [String: WDay]
    enum CodingKeys: String, CodingKey { case categoryNames, history }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryNames = (try? c.decode([String].self, forKey: .categoryNames)) ?? []
        history = (try? c.decode([String: WDay].self, forKey: .history)) ?? [:]
    }
}

struct WRange: Decodable {
    let startHour: Int
    let startMinute: Int
    enum CodingKeys: String, CodingKey { case startHour, startMinute }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startHour = (try? c.decode(Int.self, forKey: .startHour)) ?? 0
        startMinute = (try? c.decode(Int.self, forKey: .startMinute)) ?? 0
    }
}

struct WSettings: Decodable {
    let blockTimeRanges: [WRange]
    enum CodingKeys: String, CodingKey { case blockTimeRanges }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockTimeRanges = (try? c.decode([WRange].self, forKey: .blockTimeRanges)) ?? []
    }
}

// MARK: - 数据加载
//
// macOS 强制 app extension 沙箱（pkd: "plug-ins must be sandboxed"），沙箱 widget
// 无法直接读 ~/Documents。数据链路：主 App（非沙箱）在 TopThreeManager.save() 后
// 把快照写入本 widget 容器的 Application Support/widget-data.json；widget 沙箱内
// 读自己容器合法。快照缺失时回退尝试真实目录（仅非沙箱运行时有意义）再退默认空行。

enum WData {
    /// 主 App 写入的快照（widget 沙箱容器内；非沙箱进程解析为真实 home，读不到则走回退）
    static var snapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/widget-data.json")
    }
    static var dataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/.habitica-pomodoro")
    }

    /// 第一个块的开始分钟 = 逻辑日界（与主 App logicalDateKey 一致）
    static func dayBoundaryMinutes() -> Int {
        let url = dataDir.appendingPathComponent("habitica_pomodoro_settings.json")
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(WSettings.self, from: data),
              let first = s.blockTimeRanges.first else { return 0 }
        return first.startHour * 60 + first.startMinute
    }

    static func todayKey(boundary: Int, now: Date = Date()) -> String {
        let cal = Calendar.current
        let minuteOfDay = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var logical = now
        if minuteOfDay < boundary {
            logical = cal.date(byAdding: .day, value: -1, to: now) ?? now
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: logical)
    }

    struct Row: Identifiable {
        let id: Int
        let done: Int
        let total: Int
        let name: String
    }

    static let defaultNames = ["Work", "MyOwn", "Chores"]

    private static func rowsFrom(store: WStore, boundary: Int, now: Date) -> [Row] {
        let names = store.categoryNames.isEmpty ? defaultNames : store.categoryNames
        let key = todayKey(boundary: boundary, now: now)
        let groups = store.history[key]?.taskGroups ?? []
        return (0..<max(names.count, 3)).map { idx in
            let name = idx < names.count ? names[idx] : "Category \(idx + 1)"
            let tasks = idx < groups.count ? groups[idx] : []
            // 归档顺延行（movedToToday）是昨日只读副本，不计入今日完成度
            let active = tasks.filter { !$0.movedToToday && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return Row(id: idx, done: active.filter(\.isCompleted).count, total: active.count, name: name)
        }
    }

    static func emptyRows() -> [Row] {
        (0..<3).map { Row(id: $0, done: 0, total: 0, name: defaultNames[$0]) }
    }

    static func loadRows(now: Date = Date()) -> [Row] {
        // 1) 首选：主 App 写入容器的快照 { store: <top_three JSON>, boundaryMinutes: Int }
        if let data = try? Data(contentsOf: snapshotURL),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let storeAny = obj["store"],
           let storeData = try? JSONSerialization.data(withJSONObject: storeAny),
           let store = try? JSONDecoder().decode(WStore.self, from: storeData) {
            let boundary = (obj["boundaryMinutes"] as? Int) ?? 0
            return rowsFrom(store: store, boundary: boundary, now: now)
        }
        // 2) 回退：直读真实数据目录（非沙箱运行时；沙箱下此路径必然失败）
        let url = dataDir.appendingPathComponent("habitica_pomodoro_top_three.json")
        if let data = try? Data(contentsOf: url),
           let store = try? JSONDecoder().decode(WStore.self, from: data) {
            return rowsFrom(store: store, boundary: dayBoundaryMinutes(), now: now)
        }
        // 3) 无数据：空行占位
        return emptyRows()
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let rows: [WData.Row]
    static var sample: Entry {
        Entry(date: Date(), rows: [
            .init(id: 0, done: 2, total: 3, name: "Work"),
            .init(id: 1, done: 1, total: 3, name: "MyOwn"),
            .init(id: 2, done: 3, total: 3, name: "Chores"),
        ])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry.sample }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), rows: WData.loadRows()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), rows: WData.loadRows())
        // 15 分钟兜底刷新；主 App 保存数据时也会 WidgetCenter.reloadTimelines 主动推
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

// MARK: - 视图（systemMedium）

struct TodayTasksWidgetView: View {
    var entry: Entry

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M月d日 EEE"
        return f.string(from: entry.date)
    }
    private var allDone: Bool {
        entry.rows.contains { $0.total > 0 } && entry.rows.allSatisfy { $0.done >= $0.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日任务")
                    .font(.system(size: 14, weight: .semibold))
                if allDone {
                    Text("全部完成 ✓")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                Text(dateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.rows) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(width: 58, alignment: .leading)
                    ProgressView(value: Double(row.done), total: Double(max(row.total, 1)))
                        .tint(row.total > 0 && row.done >= row.total ? .green : .accentColor)
                    Text(row.total == 0 ? "—" : "\(row.done)/\(row.total)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget 入口

@main
struct TodayTasksWidget: Widget {
    let kind = "TodayTasks"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .supportedFamilies([.systemMedium])
        .configurationDisplayName("今日任务完成情况")
        .description("Top3 任务（Work / MyOwn / Chores）今日完成进度")
    }
}

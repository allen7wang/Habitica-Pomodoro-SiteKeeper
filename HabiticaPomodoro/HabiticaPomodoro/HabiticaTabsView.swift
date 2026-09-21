import SwiftUI

// MARK: - Habits Tab (Habitica 习惯列表，支持 +/- 打分)
struct HabiticaHabitsView: View {
    @ObservedObject var engine = PomodoroEngine.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    @State private var habits: [HabiticaTaskItem] = []
    @State private var loading = false
    @State private var scoredIds = Set<String>()

    var body: some View {
        Group {
            if !isConfigured {
                notConfiguredView
            } else if loading && habits.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if habits.isEmpty {
                emptyView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(habits) { habit in
                            HabitRow(item: habit, onScore: { direction in
                                score(item: habit, direction: direction)
                            }, scored: scoredIds.contains(habit.id))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .task { await load() }
    }

    private var isConfigured: Bool {
        settingsManager.settings.connectHabitica &&
        !settingsManager.settings.uid.isEmpty &&
        !settingsManager.settings.apiToken.isEmpty
    }

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.key")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("未配置 Habitica")
                .font(.headline)
            Text("请在 Settings → Habitica 填入 User ID 与 API Token")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("暂无 Habits")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("刷新") { Task { await load() } }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func load() async {
        loading = true
        let items = await HabiticaAPI.shared.fetchTasks(type: "habits", settings: settingsManager.settings)
        await MainActor.run {
            habits = items.sorted { $0.value < $1.value } // 红色（弱项）在前
            scoredIds.removeAll()
            loading = false
        }
    }

    func score(item: HabiticaTaskItem, direction: String) {
        guard !scoredIds.contains(item.id) else { return }
        Task {
            let result = await HabiticaAPI.shared.scoreTask(taskId: item.id, direction: direction, settings: settingsManager.settings)
            await MainActor.run {
                if result != nil {
                    scoredIds.insert(item.id)
                    // 刷新本地 value 与顶部状态栏
                    if let idx = habits.firstIndex(where: { $0.id == item.id }) {
                        habits[idx] = HabiticaTaskItem(
                            id: item.id, text: item.text, notes: item.notes,
                            value: item.value + (direction == "up" ? 1 : -1),
                            completed: item.completed, canUp: item.canUp, canDown: item.canDown, isDue: item.isDue)
                    }
                    Task { await engine.refreshHabitica() }
                }
            }
        }
    }
}

// MARK: - Habit Row
struct HabitRow: View {
    let item: HabiticaTaskItem
    let onScore: (String) -> Void
    let scored: Bool

    private var valueColor: Color {
        if item.value < -1 { return .red }
        if item.value < 1 { return .orange }
        if item.value < 5 { return Color(red: 0.85, green: 0.8, blue: 0.3) }
        return .green
    }

    var body: some View {
        HStack(spacing: 0) {
            // 减分按钮
            Button(action: { onScore("down") }) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 44)
                    .background(item.canDown && !scored ? Color.secondary : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!item.canDown || scored)

            // 内容
            HStack(spacing: 8) {
                Circle()
                    .fill(valueColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.text)
                        .font(.callout)
                        .lineLimit(1)
                    Text(String(format: "value %.1f", item.value))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                if scored {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color(NSColor.controlBackgroundColor))

            // 加分按钮
            Button(action: { onScore("up") }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 44)
                    .background(item.canUp && !scored ? Color.green : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!item.canUp || scored)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .opacity(scored ? 0.6 : 1)
    }
}

// MARK: - Dailies Tab (今日打卡)
struct HabiticaDailiesView: View {
    @ObservedObject var engine = PomodoroEngine.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    @State private var dailies: [HabiticaTaskItem] = []
    @State private var loading = false

    var body: some View {
        Group {
            if !isConfigured {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.key")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("未配置 Habitica")
                        .font(.headline)
                    Text("请在 Settings → Habitica 填入 User ID 与 API Token")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loading && dailies.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dailies.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无 Dailies")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("刷新") { Task { await load() } }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(dailies) { daily in
                            DailyRow(item: daily, onToggle: { toggle(item: daily) })
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .task { await load() }
    }

    private var isConfigured: Bool {
        settingsManager.settings.connectHabitica &&
        !settingsManager.settings.uid.isEmpty &&
        !settingsManager.settings.apiToken.isEmpty
    }

    func load() async {
        loading = true
        let items = await HabiticaAPI.shared.fetchTasks(type: "dailys", settings: settingsManager.settings)
        await MainActor.run {
            dailies = items
            loading = false
        }
    }

    func toggle(item: HabiticaTaskItem) {
        Task {
            let result = await HabiticaAPI.shared.scoreTask(taskId: item.id, direction: item.completed ? "down" : "up", settings: settingsManager.settings)
            await MainActor.run {
                if result != nil, let idx = dailies.firstIndex(where: { $0.id == item.id }) {
                    dailies[idx] = HabiticaTaskItem(
                        id: item.id, text: item.text, notes: item.notes, value: item.value,
                        completed: !item.completed, canUp: item.canUp, canDown: item.canDown, isDue: item.isDue)
                    Task { await engine.refreshHabitica() }
                }
            }
        }
    }
}

// MARK: - Daily Row
struct DailyRow: View {
    let item: HabiticaTaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.completed ? "checkmark.square.fill" : "square")
                    .foregroundColor(item.completed ? .green : .secondary)
                    .font(.system(size: 17))
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .font(.callout)
                    .strikethrough(item.completed, color: .secondary)
                    .lineLimit(1)
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.completed ? Color.green.opacity(0.07) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .opacity(item.completed ? 0.75 : 1)
    }
}

// MARK: - Role Tab (Habitica 角色信息：血量/法力/经验/属性)
struct HabiticaProfileView: View {
    @ObservedObject var engine = PomodoroEngine.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    @State private var profile: HabiticaProfile? = nil
    @State private var loading = false

    var body: some View {
        Group {
            if !isConfigured {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.key")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("未配置 Habitica")
                        .font(.headline)
                    Text("请在 Settings → Habitica 填入 User ID 与 API Token")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loading && profile == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let p = profile {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // 头像区
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Text(p.username.prefix(1).uppercased())
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.purple)
                            }
                            Text("@\(p.username)")
                                .font(.headline)
                            if !p.className.isEmpty {
                                Text("\(p.className) · Lv.\(p.level)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Lv.\(p.level)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 20)

                        // 三条资源（角色状态）
                        VStack(spacing: 8) {
                            StatBar(icon: "heart.fill", color: .red, label: "HP 生命",
                                    value: p.hp, maxValue: max(p.maxHealth, 50),
                                    valueText: String(format: "%.0f / %.0f", p.hp, max(p.maxHealth, 50)))
                            StatBar(icon: "sparkles", color: .blue, label: "MP 法力",
                                    value: p.mp, maxValue: max(p.maxMP, p.mp, 1),
                                    valueText: String(format: "%.0f", p.mp))
                            StatBar(icon: "star.fill", color: .purple, label: "EXP 经验",
                                    value: p.exp, maxValue: max(expInLevel(p), 1),
                                    valueText: String(format: "%.0f / %.0f", p.exp, expInLevel(p)))
                        }
                        .padding(.horizontal, 24)

                        // 金币
                        HStack(spacing: 6) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.2f GP", p.gp))
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(.horizontal, 24)

                        Divider().padding(.horizontal, 24)

                        // 属性
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            AttrCell(name: "STR 力量", value: p.str, color: .red)
                            AttrCell(name: "CON 体质", value: p.con, color: .orange)
                            AttrCell(name: "INT 智力", value: p.int, color: .blue)
                            AttrCell(name: "PER 感知", value: p.per, color: .green)
                        }
                        .padding(.horizontal, 24)

                        Divider().padding(.horizontal, 24)

                        // 成就
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            AchieveCell(name: "连续完美天数", value: "\(p.streak)")
                            AchieveCell(name: "完美日总数", value: "\(p.perfectDays)")
                            AchieveCell(name: "任务卷轴", value: "\(p.questsTotal)")
                            AchieveCell(name: "注册时间", value: p.joinedAt.map { fmtDate($0) } ?? "—")
                        }
                        .padding(.horizontal, 24)

                        // 刷新
                        Button(action: { Task { await load() } }) {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                }
            } else {
                // 加载失败兜底
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("角色数据加载失败")
                        .font(.headline)
                    Text("请检查网络或 Habitica 服务状态")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("重试") { Task { await load() } }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private var isConfigured: Bool {
        settingsManager.settings.connectHabitica &&
        !settingsManager.settings.uid.isEmpty &&
        !settingsManager.settings.apiToken.isEmpty
    }

    private func expInLevel(_ p: HabiticaProfile) -> Double {
        // Habitica: exp needed = ((lvl^2)*0.25 + 10*lvl + 139.75)
        let lvl = Double(p.level)
        return (lvl * lvl) * 0.25 + 10 * lvl + 139.75
    }

    private func fmtDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: d)
    }

    func load() async {
        loading = true
        let p = await HabiticaAPI.shared.fetchProfile(settings: settingsManager.settings)
        await MainActor.run {
            profile = p
            loading = false
        }
    }
}

// MARK: - StatBar
struct StatBar: View {
    let icon: String
    let color: Color
    let label: String
    let value: Double
    let maxValue: Double
    var valueText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 13))
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(0, min(1, value / max(maxValue, 0.001)) * geo.size.width))
                }
            }
            .frame(height: 8)
            Text(valueText ?? String(format: "%.0f", value))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

// MARK: - AttrCell
struct AttrCell: View {
    let name: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(value)")
                .font(.callout.bold().monospacedDigit())
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.06))
        )
    }
}

// MARK: - AchieveCell
struct AchieveCell: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.callout.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.06))
        )
    }
}

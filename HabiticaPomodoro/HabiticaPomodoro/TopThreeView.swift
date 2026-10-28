import SwiftUI

// MARK: - Top Three View (Task 页：Work / MyOwn / 琐事 × 今天 / 昨天)
struct TopThreeView: View {
    @ObservedObject var manager = TopThreeManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @Environment(\.appTheme) private var theme

    private var settings: UserSettings { settingsManager.settings }
    private var todayKey: String { manager.todayKey(settings: settings) }
    private var yesterdayKey: String { manager.yesterdayKey(settings: settings) }

    var body: some View {
        ScrollView(showsIndicators: false) {
#if os(macOS)
            themedContent
#else
            VStack(spacing: 14) {
                HStack {
                    Text("每日任务").font(.headline)
                    Spacer()
                    Button(manager.syncInProgress ? "同步中…" : "同步 Habitica") {
                        Task { await manager.synchronize(settings: settings) }
                    }
                    .disabled(manager.syncInProgress || !settings.connectHabitica || settings.uid.isEmpty || settings.apiToken.isEmpty)
                }
                if let message = manager.syncMessage { Text(message).font(.caption).foregroundColor(.secondary) }
                // ── Today 卡片：绿色调，可编辑 ──
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Today")
                            .font(.headline)
                        Text(shortDate(todayKey))
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("点击文字编辑 · 点击圆圈完成")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    ForEach(0..<manager.categoryCount, id: \.self) { cat in
                        TopThreeCategorySection(
                            dateKey: todayKey,
                            category: cat,
                            editable: true,
                            canMoveToToday: false
                        )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.accentSoft.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.line, lineWidth: 1)
                )

                // ── Yesterday 卡片：灰色调，归档感 ──
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                        Text("Yesterday")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(shortDate(yesterdayKey))
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("已归档 · 未完成任务可 ➡ 移到今天")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    ForEach(0..<manager.categoryCount, id: \.self) { cat in
                        TopThreeCategorySection(
                            dateKey: yesterdayKey,
                            category: cat,
                            editable: false,
                            canMoveToToday: true
                        )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.subtle.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.line.opacity(0.8), lineWidth: 1)
                )
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
#endif
        }
        .task { await manager.synchronize(settings: settings) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            manager.objectWillChange.send()
        }
    }

#if os(macOS)
    private var themedContent: some View {
        VStack(alignment: .leading, spacing: theme.pageSpacing) {
            ThemedPageHeader(title: "每日任务", subtitle: "把重要的事，先做好。", symbol: "checklist")

            HStack(spacing: 10) {
                Label("今天完成 \(todayCompleted)/\(todayTasks.count)", systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.muted)
                Spacer(minLength: 0)
                Button {
                    Task { await manager.synchronize(settings: settings) }
                } label: {
                    Label(manager.syncInProgress ? "同步中…" : "同步 Habitica", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(QuietButtonStyle(theme: theme))
                .disabled(manager.syncInProgress || !settings.connectHabitica || settings.uid.isEmpty || settings.apiToken.isEmpty)
            }
            if let message = manager.syncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if theme.style == .studio {
                HStack(alignment: .top, spacing: theme.pageSpacing) {
                    daySection(key: todayKey, editable: true)
                    daySection(key: yesterdayKey, editable: false)
                }
            } else {
                daySection(key: todayKey, editable: true)
                daySection(key: yesterdayKey, editable: false)
            }
        }
        .padding(.horizontal, theme.pageInset)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private var todayTasks: [TopThreeTask] {
        (0..<manager.categoryCount).flatMap { manager.getTasks(key: todayKey, category: $0) }
    }

    private var todayCompleted: Int { todayTasks.filter { $0.isCompleted }.count }

    private func daySection(key: String, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            HStack(spacing: 7) {
                Circle()
                    .fill(editable ? theme.accent : theme.muted)
                    .frame(width: 6, height: 6)
                Text(editable ? "今天" : "昨天")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(editable ? theme.ink : theme.muted)
                Text(shortDate(key))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(theme.muted)
                Spacer(minLength: 0)
                if !editable {
                    Text("已归档")
                        .font(.system(size: 10))
                        .foregroundColor(theme.muted)
                }
            }
            Text(editable ? "点击任务文字编辑，点击圆圈完成" : "未完成的任务可移到今天")
                .font(.system(size: 10))
                .foregroundColor(theme.muted)
                .padding(.bottom, 3)

            ForEach(0..<manager.categoryCount, id: \.self) { cat in
                TopThreeCategorySection(dateKey: key, category: cat, editable: editable, canMoveToToday: !editable)
                    .themeCard(theme, padding: theme.cardPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
#endif

    private func shortDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }
}

// MARK: - Category Section (一个分类：Work / MyOwn / 琐事)
struct TopThreeCategorySection: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var manager = TopThreeManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    let dateKey: String
    let category: Int
    let editable: Bool
    let canMoveToToday: Bool

    @State private var editingUUID: UUID? = nil
    @State private var draftTitle: String = ""
    @State private var renamingCategory = false
    @State private var draftCategoryName: String = ""
    @State private var newTaskTitle: String = ""

    private var settings: UserSettings { settingsManager.settings }
    private var tasks: [TopThreeTask] { manager.getTasks(key: dateKey, category: category) }
    private var completedCount: Int { tasks.filter { $0.isCompleted }.count }
    private var isFreeList: Bool { manager.isFreeList(category: category) }

    private var categoryColor: Color {
#if os(macOS)
        return theme.accent
#else
        switch category {
        case 0: return .blue
        case 1: return .purple
        default: return .orange
        }
#endif
    }

    private var mutedColor: Color {
#if os(macOS)
        return theme.muted
#else
        return .secondary
#endif
    }

    private var completionColor: Color {
#if os(macOS)
        return theme.accent
#else
        return .green
#endif
    }

    private var hintColor: Color {
#if os(macOS)
        return theme.muted.opacity(0.8)
#else
        return .secondary.opacity(0.6)
#endif
    }

    private var sectionSpacing: CGFloat {
#if os(macOS)
        return theme.rowSpacing
#else
        return 4
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            // 分类标题行（今天可点击重命名）
            HStack(spacing: 6) {
                if renamingCategory {
                    TextField("分类名", text: $draftCategoryName, onCommit: {
                        manager.setCategoryName(index: category, name: draftCategoryName.isEmpty ? manager.categoryName(index: category) : draftCategoryName, settings: settings)
                        renamingCategory = false
                    })
                    .modifier(TaskInputStyle())
                    .font(.caption.bold())
                    .frame(width: 120)
                    .cancelOnExitCommand { renamingCategory = false }
                } else {
                    HStack(spacing: 4) {
                        Text(manager.categoryName(index: category))
                            .font(.subheadline.bold())
                            .foregroundColor(categoryColor)
                        if editable {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(hintColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editable else { return }
                        draftCategoryName = manager.categoryName(index: category)
                        renamingCategory = true
                    }

                    Text("\(completedCount)/\(tasks.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(!tasks.isEmpty && completedCount == tasks.count ? completionColor : mutedColor)
                }
                Spacer()
            }
            .padding(.leading, 2)

#if os(macOS)
            if tasks.isEmpty && !editable {
                Text("这一天没有任务")
                    .font(.system(size: 11))
                    .foregroundColor(theme.muted)
                    .padding(.vertical, 8)
            }
#endif

            // 任务列表
            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    editable: editable,
                    isEditing: editable && editingUUID == task.id,
                    draftTitle: $draftTitle,
                    canMove: canMoveToToday && !task.isCompleted && !task.movedToToday && !task.title.isEmpty,
                    onToggle: {
                        manager.toggleTask(key: dateKey, category: category, id: task.id, settings: settings)
                    },
                    onStartEdit: {
                        guard editable, manager.isEditable(key: dateKey, settings: settings),
                              tasks.contains(where: { $0.id == task.id && !$0.movedToToday }) else { return }
                        editingUUID = task.id
                        draftTitle = task.title
                    },
                    onCommitEdit: {
                        guard editable, editingUUID == task.id else { return }
                        manager.setTaskTitle(key: dateKey, category: category, id: task.id, title: draftTitle, settings: settings)
                        editingUUID = nil
                    },
                    onCancelEdit: { editingUUID = nil },
                    onMoveToToday: {
                        manager.moveTaskToToday(fromKey: dateKey, category: category, id: task.id, settings: settings)
                    },
                    onDelete: editable ? {
                        manager.removeTask(key: dateKey, category: category, id: task.id, settings: settings)
                    } : nil
                )
            }

            // 统一添加输入行（所有分类一致；有上限的分类满 3 条后隐藏）
            if manager.canAddTask(key: dateKey, category: category, settings: settings) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(categoryColor)
                        .font(.system(size: 15))
                    TextField(placeholder, text: $newTaskTitle, onCommit: {
                        manager.addTask(key: dateKey, category: category, title: newTaskTitle, settings: settings)
                        newTaskTitle = ""
                    })
                    .modifier(TaskInputStyle())
                    .font(.callout)
                }
                .padding(.vertical, 1)
                .padding(.leading, 8)
            } else if editable && manager.taskLimit(category: category) != nil {
                // 固定分类已满 3 条
                Text("已满 3 件，删除后可再添加")
                    .font(.caption2)
                    .foregroundColor(hintColor)
                    .padding(.leading, 8)
                    .padding(.vertical, 1)
            }
        }
        .onChange(of: tasks.filter { !$0.movedToToday }.map(\.id)) { ids in
            if let id = editingUUID, !ids.contains(id) { cancelEditing() }
        }
        .onChange(of: dateKey) { _ in cancelEditing() }
        .onChange(of: category) { _ in cancelEditing() }
        .onChange(of: editable) { value in if !value { cancelEditing() } }
        .onDisappear { cancelEditing() }
    }

    private func cancelEditing() {
        editingUUID = nil
        draftTitle = ""
    }

    private var placeholder: String {
        if let limit = manager.taskLimit(category: category) {
            return "添加任务（最多 \(limit) 件），回车确认..."
        }
        return "添加任务，回车确认..."
    }
}

// MARK: - Task Row (单条任务)
struct TaskRow: View {
    @Environment(\.appTheme) private var theme
    let task: TopThreeTask
    let editable: Bool
    let isEditing: Bool
    @Binding var draftTitle: String
    let canMove: Bool
    let onToggle: () -> Void
    let onStartEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onMoveToToday: () -> Void
    let onDelete: (() -> Void)?

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            if editable {
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.isCompleted ? completionColor : mutedColor)
                        .font(.system(size: 15))
                        .modifier(TaskActionTarget())
                }
                .buttonStyle(.borderless)
            } else {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : (task.movedToToday ? "arrow.right.circle.fill" : "circle"))
                    .foregroundColor(task.isCompleted ? completionColor : (task.movedToToday ? movedColor : mutedColor))
                    .font(.system(size: 15))
                    .opacity(0.55)
            }

            if isEditing {
                TextField("输入任务...", text: $draftTitle, onCommit: onCommitEdit)
                    .modifier(TaskInputStyle())
                    .font(.callout)
                    .cancelOnExitCommand { onCancelEdit() }
            } else {
                Text(displayTitle)
                    .font(.callout)
                    .foregroundColor(titleColor)
                    .strikethrough(task.isCompleted, color: mutedColor)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editable else { return }
                        onStartEdit()
                    }
                Spacer(minLength: 0)
            }

            // 移动到今日按钮（昨天未完成任务）
            if canMove {
                Button(action: onMoveToToday) {
                    Image(systemName: "arrow.uturn.right")
                        .font(.system(size: 12))
#if os(macOS)
                        .foregroundColor(movedColor)
#endif
                        .modifier(TaskActionTarget())
                }
                .buttonStyle(.borderless)
                .help("移动到今日")
            }

            // 已移动标记
            if task.movedToToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(movedColor.opacity(0.7))
                    .help("已移动到今日")
            }

            // 删除按钮
            if let onDelete = onDelete {
                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(mutedColor.opacity(0.7))
                        .modifier(TaskActionTarget())
                }
                .buttonStyle(.borderless)
                .help("删除任务")
                .confirmationDialog("确定删除这条任务？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { onDelete() }
                    Button("取消", role: .cancel) {}
                }
            }
        }
        .padding(.vertical, rowPadding)
        .padding(.leading, 8)
        .opacity(task.movedToToday ? 0.55 : 1)
    }

    private var displayTitle: String {
        if task.title.isEmpty {
            return editable ? "点击添加..." : "—"
        }
        return task.title
    }

    private var titleColor: Color {
#if os(macOS)
        if task.title.isEmpty || task.isCompleted || !editable { return theme.muted }
        return theme.ink
#else
        if task.title.isEmpty { return .secondary.opacity(editable ? 0.7 : 0.4) }
        return editable ? .primary : .primary.opacity(0.65)
#endif
    }

    private var mutedColor: Color {
#if os(macOS)
        return theme.muted
#else
        return .secondary
#endif
    }

    private var completionColor: Color {
#if os(macOS)
        return theme.accent
#else
        return .green
#endif
    }

    private var movedColor: Color {
#if os(macOS)
        return theme.accent
#else
        return .blue
#endif
    }

    private var rowPadding: CGFloat {
#if os(macOS)
        return theme.style == .garden ? 4 : 2
#else
        return 1
#endif
    }
}

private struct TaskInputStyle: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
#if os(macOS)
        content
            .textFieldStyle(.plain)
            .foregroundColor(theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.subtle))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
            .tint(theme.accent)
#else
        content.textFieldStyle(.roundedBorder)
#endif
    }
}

private struct TaskActionTarget: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content.frame(minWidth: 24, minHeight: 26).contentShape(Rectangle())
#else
        content
#endif
    }
}

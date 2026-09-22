import SwiftUI

// MARK: - Top Three View (Task 页：Work / MyOwn / 琐事 × 今天 / 昨天)
struct TopThreeView: View {
    @ObservedObject var manager = TopThreeManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    private var settings: UserSettings { settingsManager.settings }
    private var todayKey: String { manager.todayKey(settings: settings) }
    private var yesterdayKey: String { manager.yesterdayKey(settings: settings) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
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
                        .fill(Color.green.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
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
                        .fill(Color.gray.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    private func shortDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }
}

// MARK: - Category Section (一个分类：Work / MyOwn / 琐事)
struct TopThreeCategorySection: View {
    @ObservedObject var manager = TopThreeManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    let dateKey: String
    let category: Int
    let editable: Bool
    let canMoveToToday: Bool

    @State private var editingIndex: Int? = nil
    @State private var draftTitle: String = ""
    @State private var renamingCategory = false
    @State private var draftCategoryName: String = ""
    @State private var newTaskTitle: String = ""

    private var settings: UserSettings { settingsManager.settings }
    private var tasks: [TopThreeTask] { manager.getTasks(key: dateKey, category: category) }
    private var completedCount: Int { tasks.filter { $0.isCompleted }.count }
    private var isFreeList: Bool { manager.isFreeList(category: category) }

    private var categoryColor: Color {
        switch category {
        case 0: return .blue
        case 1: return .purple
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 分类标题行（今天可点击重命名）
            HStack(spacing: 6) {
                if renamingCategory {
                    TextField("分类名", text: $draftCategoryName, onCommit: {
                        manager.setCategoryName(index: category, name: draftCategoryName.isEmpty ? manager.categoryName(index: category) : draftCategoryName, settings: settings)
                        renamingCategory = false
                    })
                    .textFieldStyle(.roundedBorder)
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
                                .foregroundColor(.secondary.opacity(0.6))
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
                        .foregroundColor(!tasks.isEmpty && completedCount == tasks.count ? .green : .secondary)
                }
                Spacer()
            }
            .padding(.leading, 2)

            // 任务列表
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRow(
                    task: task,
                    editable: editable,
                    isEditing: editable && editingIndex == index,
                    draftTitle: $draftTitle,
                    canMove: canMoveToToday && !task.isCompleted && !task.movedToToday && !task.title.isEmpty,
                    onToggle: {
                        manager.toggleTask(key: dateKey, category: category, index: index, settings: settings)
                    },
                    onStartEdit: {
                        editingIndex = index
                        draftTitle = task.title
                    },
                    onCommitEdit: {
                        manager.setTaskTitle(key: dateKey, category: category, index: index, title: draftTitle, settings: settings)
                        editingIndex = nil
                    },
                    onCancelEdit: { editingIndex = nil },
                    onMoveToToday: {
                        manager.moveTaskToToday(fromKey: dateKey, category: category, index: index, settings: settings)
                    },
                    onDelete: editable ? {
                        manager.removeTask(key: dateKey, category: category, index: index, settings: settings)
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
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                }
                .padding(.vertical, 1)
                .padding(.leading, 8)
            } else if editable && manager.taskLimit(category: category) != nil {
                // 固定分类已满 3 条
                Text("已满 3 件，完成或删除后可再添加")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 8)
                    .padding(.vertical, 1)
            }
        }
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
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
            } else {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : (task.movedToToday ? "arrow.right.circle.fill" : "circle"))
                    .foregroundColor(task.isCompleted ? .green : (task.movedToToday ? .blue : .secondary))
                    .font(.system(size: 15))
                    .opacity(0.55)
            }

            if isEditing {
                TextField("输入任务...", text: $draftTitle, onCommit: onCommitEdit)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .cancelOnExitCommand { onCancelEdit() }
            } else {
                Text(displayTitle)
                    .font(.callout)
                    .foregroundColor(titleColor)
                    .strikethrough(task.isCompleted, color: .secondary)
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
                }
                .buttonStyle(.borderless)
                .help("移动到今日")
            }

            // 已移动标记
            if task.movedToToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.blue.opacity(0.7))
                    .help("已移动到今日")
            }

            // 删除按钮
            if let onDelete = onDelete {
                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("删除任务")
                .confirmationDialog("确定删除这条任务？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { onDelete() }
                    Button("取消", role: .cancel) {}
                }
            }
        }
        .padding(.vertical, 1)
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
        if task.title.isEmpty { return .secondary.opacity(editable ? 0.7 : 0.4) }
        return editable ? .primary : .primary.opacity(0.65)
    }
}

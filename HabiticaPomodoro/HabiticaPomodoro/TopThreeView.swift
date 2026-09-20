import SwiftUI

// MARK: - Top Three View (Task 页：Work / MyOwn 两类 × 今天 / 昨天)
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
                            editable: true
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
                        Text("已归档 · 不可修改")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    ForEach(0..<manager.categoryCount, id: \.self) { cat in
                        TopThreeCategorySection(
                            dateKey: yesterdayKey,
                            category: cat,
                            editable: false
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
        }
    }

    private func shortDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }
}

// MARK: - Category Section (一个分类：Work 或 MyOwn)
struct TopThreeCategorySection: View {
    @ObservedObject var manager = TopThreeManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared

    let dateKey: String
    let category: Int
    let editable: Bool

    @State private var editingIndex: Int? = nil
    @State private var draftTitle: String = ""
    @State private var renamingCategory = false
    @State private var draftCategoryName: String = ""

    private var settings: UserSettings { settingsManager.settings }
    private var tasks: [TopThreeTask] { manager.getTasks(key: dateKey, category: category) }
    private var completedCount: Int { tasks.filter { $0.isCompleted }.count }

    private var categoryColor: Color {
        category == 0 ? .blue : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 分类标题行（今天可点击重命名）
            HStack(spacing: 6) {
                if renamingCategory {
                    TextField("分类名", text: $draftCategoryName, onCommit: {
                        manager.setCategoryName(index: category, name: draftCategoryName.isEmpty ? manager.categoryName(index: category) : draftCategoryName)
                        renamingCategory = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.bold())
                    .frame(width: 120)
                    .onExitCommand { renamingCategory = false }
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

                    Text("\(completedCount)/3")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(completedCount == 3 ? .green : .secondary)
                }
                Spacer()
            }
            .padding(.leading, 2)

            // 3 个任务槽位
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                HStack(spacing: 8) {
                    if editable {
                        Button(action: { manager.toggleTask(key: dateKey, category: category, index: index, settings: settings) }) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isCompleted ? .green : .secondary)
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(task.isCompleted ? .green : .secondary)
                            .font(.system(size: 15))
                            .opacity(0.55)
                    }

                    if editable && editingIndex == index {
                        TextField("输入任务...", text: $draftTitle, onCommit: {
                            manager.setTaskTitle(key: dateKey, category: category, index: index, title: draftTitle, settings: settings)
                            editingIndex = nil
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .onExitCommand { editingIndex = nil }
                    } else {
                        Text(displayTitle(task))
                            .font(.callout)
                            .foregroundColor(titleColor(task))
                            .strikethrough(task.isCompleted, color: .secondary)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editable else { return }
                                editingIndex = index
                                draftTitle = task.title
                            }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 1)
                .padding(.leading, 8)
            }
        }
    }

    private func titleColor(_ task: TopThreeTask) -> Color {
        if task.title.isEmpty { return .secondary.opacity(editable ? 0.7 : 0.4) }
        return editable ? .primary : .primary.opacity(0.65)
    }

    private func displayTitle(_ task: TopThreeTask) -> String {
        if task.title.isEmpty {
            return editable ? "点击添加..." : "—"
        }
        return task.title
    }
}

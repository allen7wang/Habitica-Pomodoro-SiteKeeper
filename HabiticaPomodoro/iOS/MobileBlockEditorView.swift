import SwiftUI

/// Edits the same block goal, schedule and task arrays used by the Mac timeline.
struct MobileBlockEditorView: View {
    let blockIndex: Int
    @ObservedObject private var manager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newTitle = ""
    @State private var newEstimate = 1
    @State private var deleteTask: UUID?

    private var tasks: [BlockTask] {
        manager.settings.blockTasks.indices.contains(blockIndex) ? manager.settings.blockTasks[blockIndex] : []
    }

    private var goal: Binding<String> {
        Binding(get: {
            manager.settings.blockGoals.indices.contains(blockIndex) ? manager.settings.blockGoals[blockIndex] : ""
        }, set: { value in
            while manager.settings.blockGoals.count <= blockIndex { manager.settings.blockGoals.append("") }
            manager.settings.blockGoals[blockIndex] = value
        })
    }

    private func timeBinding(_ keyPath: WritableKeyPath<BlockTimeRange, Int>, fallback: Int) -> Binding<Int> {
        Binding(get: {
            manager.settings.blockTimeRanges.indices.contains(blockIndex)
                ? manager.settings.blockTimeRanges[blockIndex][keyPath: keyPath] : fallback
        }, set: { value in
            while manager.settings.blockTimeRanges.count <= blockIndex {
                manager.settings.blockTimeRanges.append(BlockTimeRange(startHour: 4, startMinute: 0, endHour: 7, endMinute: 0))
            }
            manager.settings.blockTimeRanges[blockIndex][keyPath: keyPath] = value
        })
    }

    var body: some View {
        Form {
            Section("时间与目标") {
                TextField("本块目标", text: goal)
                HStack {
                    hourPicker("开始时", value: timeBinding(\.startHour, fallback: 4))
                    minutePicker("分", value: timeBinding(\.startMinute, fallback: 0))
                }
                HStack {
                    hourPicker("结束时", value: timeBinding(\.endHour, fallback: 7))
                    minutePicker("分", value: timeBinding(\.endMinute, fallback: 0))
                }
            }
            Section("任务 · \(tasks.filter(\.isCompleted).count)/\(tasks.count)") {
                ForEach(tasks) { task in
                    HStack {
                        Button {
                            guard let index = manager.settings.blockTasks[blockIndex].firstIndex(where: { $0.id == task.id }) else { return }
                            manager.settings.blockTasks[blockIndex][index].isCompleted.toggle()
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isCompleted ? .green : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        TextField("任务标题", text: taskBinding(task.id, \.title, fallback: task.title))
                            .strikethrough(task.isCompleted)
                        Stepper("\(task.estimatedPomo)p", value: taskBinding(task.id, \.estimatedPomo, fallback: 1), in: 1...12)
                            .font(.caption).fixedSize()
                        Button(role: .destructive) {
                            deleteTask = task.id
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("新任务", text: $newTitle)
                    Stepper("\(newEstimate)p", value: $newEstimate, in: 1...12)
                        .fixedSize()
                    Button { addTask() } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("B\(blockIndex + 1)")
        .confirmationDialog("删除这条块任务？", isPresented: Binding(get: { deleteTask != nil }, set: { if !$0 { deleteTask = nil } })) {
            Button("删除", role: .destructive) {
                if let id = deleteTask, manager.settings.blockTasks.indices.contains(blockIndex) {
                    manager.settings.blockTasks[blockIndex].removeAll { $0.id == id }
                }
                deleteTask = nil
            }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }

    private func hourPicker(_ label: String, value: Binding<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(0..<24, id: \.self) { hour in Text(String(format: "%02d", hour)).tag(hour) }
        }
    }
    private func minutePicker(_ label: String, value: Binding<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(0..<60, id: \.self) { minute in Text(String(format: "%02d", minute)).tag(minute) }
        }
    }
    private func taskBinding<Value>(_ id: UUID, _ key: WritableKeyPath<BlockTask, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { tasks.first(where: { $0.id == id })?[keyPath: key] ?? fallback }, set: { value in
            guard manager.settings.blockTasks.indices.contains(blockIndex),
                  let index = manager.settings.blockTasks[blockIndex].firstIndex(where: { $0.id == id }) else { return }
            manager.settings.blockTasks[blockIndex][index][keyPath: key] = value
        })
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        while manager.settings.blockTasks.count <= blockIndex { manager.settings.blockTasks.append([]) }
        manager.settings.blockTasks[blockIndex].append(BlockTask(title: title, estimatedPomo: newEstimate))
        newTitle = ""
        newEstimate = 1
    }
}

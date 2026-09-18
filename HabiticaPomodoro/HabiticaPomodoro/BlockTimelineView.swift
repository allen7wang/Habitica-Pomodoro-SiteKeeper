import SwiftUI

// MARK: - Block Timeline View (可视化时间轴)
struct BlockTimelineView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var draggedBlock: Int?
    @State private var showTaskEditor: Bool = false
    @State private var selectedBlockIndex: Int = 0
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Block Timeline")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Horizontal timeline
            ScrollView([.horizontal], showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<settingsManager.settings.blockCount, id: \.self) { blockIndex in
                        BlockCardView(
                            blockIndex: blockIndex,
                            isDragging: draggedBlock == blockIndex,
                            onDrag: { draggedBlock = blockIndex },
                            onDrop: { newIndex in reorderBlocks(from: blockIndex, to: newIndex) },
                            onTap: { selectedBlockIndex = blockIndex; showTaskEditor = true }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 180)
        }
        .sheet(isPresented: $showTaskEditor) {
            BlockTaskEditorView(blockIndex: selectedBlockIndex)
        }
    }
    
    private func reorderBlocks(from: Int, to: Int) {
        var ranges = settingsManager.settings.blockTimeRanges
        var goals = settingsManager.settings.blockGoals
        var tasks = settingsManager.settings.blockTasks
        
        // Reorder each array
        let movedRange = ranges.remove(at: from)
        ranges.insert(movedRange, at: to)
        
        let movedGoal = goals.remove(at: from)
        goals.insert(movedGoal, at: to)
        
        while tasks.count <= max(from, to) {
            tasks.append([])
        }
        let movedTasks = tasks.remove(at: from)
        tasks.insert(movedTasks, at: to)
        
        settingsManager.settings.blockTimeRanges = ranges
        settingsManager.settings.blockGoals = goals
        settingsManager.settings.blockTasks = tasks
    }
}

// MARK: - Block Card View (单个块卡片)
struct BlockCardView: View {
    let blockIndex: Int
    let isDragging: Bool
    let onDrag: () -> Void
    let onDrop: (Int) -> Void
    let onTap: () -> Void
    
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var blockManager = BlockProgressManager.shared
    
    var body: some View {
        let timeRange = blockIndex < settingsManager.settings.blockTimeRanges.count 
            ? settingsManager.settings.blockTimeRanges[blockIndex] 
            : nil
        let goal = blockIndex < settingsManager.settings.blockGoals.count 
            ? settingsManager.settings.blockGoals[blockIndex] 
            : ""
        let tasks = blockIndex < settingsManager.settings.blockTasks.count 
            ? settingsManager.settings.blockTasks[blockIndex] 
            : []
        let progress = blockManager.getTodayBlockProgress(settings: settingsManager.settings)
        let completed = blockIndex < progress.count ? progress[blockIndex] : 0
        let total = settingsManager.settings.blockPomoCount
        let isCurrent = blockManager.blockProgress.currentBlockIndex == blockIndex
        
        return VStack(spacing: 8) {
            // Block header
            HStack(spacing: 6) {
                Text("B\(blockIndex + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isCurrent ? .white : .primary)
                
                if let range = timeRange {
                    Text(range.displayString)
                        .font(.caption2)
                        .foregroundColor(isCurrent ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
            }
            
            // Progress bar
            ProgressView(value: Double(completed), total: Double(total))
                .progressViewStyle(LinearProgressViewStyle(tint: completed >= total ? .green : .orange))
            
            // Goal and tasks
            VStack(alignment: .leading, spacing: 4) {
                if !goal.isEmpty {
                    Text(goal)
                        .font(.caption)
                        .foregroundColor(isCurrent ? .white : .primary)
                        .lineLimit(2)
                }
                
                if !tasks.isEmpty {
                    Text("\(tasks.filter { $0.isCompleted }.count)/\(tasks.count) tasks")
                        .font(.caption2)
                        .foregroundColor(isCurrent ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: 120)
        }
        .padding(12)
        .frame(width: 140, height: 160)
        .background(isCurrent ? Color.orange : Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(isDragging ? 0.2 : 0.05), radius: isDragging ? 8 : 4)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCurrent)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .onTapGesture(perform: onTap)
        .onDrag {
            onDrag()
            return NSItemProvider(object: "block_\(blockIndex)" as NSString)
        }
    }
}

// MARK: - Block Card Preview (拖拽预览)
struct BlockCardPreview: View {
    let blockIndex: Int
    
    var body: some View {
        Text("B\(blockIndex + 1)")
            .font(.caption)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
    }
}

// MARK: - Block Task Editor View (块任务编辑器)
struct BlockTaskEditorView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    let blockIndex: Int
    
    @State private var newTaskTitle: String = ""
    @State private var newTaskPomo: Int = 1
    
    var body: some View {
        let tasks = blockIndex < settingsManager.settings.blockTasks.count 
            ? settingsManager.settings.blockTasks[blockIndex] 
            : []
        
        return NavigationView {
            VStack(spacing: 16) {
                Text("Block \(blockIndex + 1) Tasks")
                    .font(.headline)
                
                // Goal input
                TextField("Block Goal", text: Binding(
                    get: { blockIndex < settingsManager.settings.blockGoals.count ? settingsManager.settings.blockGoals[blockIndex] : "" },
                    set: { newValue in
                        while settingsManager.settings.blockGoals.count <= blockIndex {
                            settingsManager.settings.blockGoals.append("")
                        }
                        settingsManager.settings.blockGoals[blockIndex] = newValue
                    }
                ))
                .textFieldStyle(.roundedBorder)
                
                Divider()
                
                // Tasks list
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            HStack(spacing: 8) {
                                Button(action: {
                                    toggleTask(task: task)
                                }) {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(task.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                
                                Text(task.title)
                                    .font(.body)
                                    .strikethrough(task.isCompleted)
                                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                                
                                Spacer()
                                
                                Text("\(task.estimatedPomo)p")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    deleteTask(task: task)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Divider()
                
                // Add new task
                HStack(spacing: 8) {
                    TextField("Task title", text: $newTaskTitle)
                        .textFieldStyle(.roundedBorder)
                    
                    Stepper("\(newTaskPomo)p", value: $newTaskPomo, in: 1...12)
                    
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Block Tasks")
            .frame(minWidth: 500, minHeight: 600)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func addTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let task = BlockTask(title: newTaskTitle, isCompleted: false, estimatedPomo: newTaskPomo)
        
        while settingsManager.settings.blockTasks.count <= blockIndex {
            settingsManager.settings.blockTasks.append([])
        }
        settingsManager.settings.blockTasks[blockIndex].append(task)
        
        newTaskTitle = ""
        newTaskPomo = 1
    }
    
    private func toggleTask(task: BlockTask) {
        guard let index = settingsManager.settings.blockTasks[blockIndex].firstIndex(where: { $0.id == task.id }) else { return }
        settingsManager.settings.blockTasks[blockIndex][index].isCompleted.toggle()
    }
    
    private func deleteTask(task: BlockTask) {
        settingsManager.settings.blockTasks[blockIndex].removeAll { $0.id == task.id }
    }
}
import SwiftUI
import Combine

// MARK: - Notification names
extension Notification.Name {
    static let scrollToCurrentBlock = Notification.Name("scrollToCurrentBlock")
}

// MARK: - Block Timeline View (可视化时间轴)
struct BlockTimelineView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var draggedBlock: Int?
    @State private var selectedBlockIndex: Int = 0
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Block Timeline")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Scroll to current block button
                Button(action: {
                    NotificationCenter.default.post(name: .scrollToCurrentBlock, object: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text("Current")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Horizontal timeline
            ScrollViewReader { proxy in
                ScrollView([.horizontal], showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(0..<settingsManager.settings.blockCount, id: \.self) { blockIndex in
                            BlockCardView(
                                blockIndex: blockIndex,
                                isDragging: draggedBlock == blockIndex,
                                onDrag: { draggedBlock = blockIndex },
                                onDrop: { newIndex in reorderBlocks(from: blockIndex, to: newIndex) },
                                onTap: { selectedBlockIndex = blockIndex; showTaskEditorWindow(blockIndex: blockIndex) }
                            )
                            .id("block_\(blockIndex)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 180)
                .onAppear {
                    // Initial scroll to current block
                    let currentBlockIdx = BlockProgressManager.shared.blockProgress.currentBlockIndex
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("block_\(currentBlockIdx)", anchor: .center)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollToCurrentBlock)) { _ in
                    let currentBlockIdx = BlockProgressManager.shared.blockProgress.currentBlockIndex
                    proxy.scrollTo("block_\(currentBlockIdx)", anchor: .center)
                }
            }
        }
    }
    
    private func showTaskEditorWindow(blockIndex: Int) {
        let contentView = BlockTaskEditorView(blockIndex: blockIndex)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Block \(blockIndex + 1) Tasks"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 550, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
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
        
        return VStack(spacing: 6) {
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
            }
            
            // Progress bar
            ProgressView(value: Double(completed), total: Double(total))
                .progressViewStyle(LinearProgressViewStyle(tint: completed >= total ? .green : .orange))
                .controlSize(.small)
            
            // Goal
            if !goal.isEmpty {
                Text(goal)
                    .font(.caption2)
                    .foregroundColor(isCurrent ? .white.opacity(0.9) : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            // Tasks list (show first 2 tasks, or all if few)
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tasks.prefix(2)), id: \.id) { task in
                        HStack(spacing: 4) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundColor(task.isCompleted ? .green : (isCurrent ? .white.opacity(0.6) : .secondary))
                            Text(task.title)
                                .font(.caption2)
                                .foregroundColor(isCurrent ? .white : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    
                    if tasks.count > 2 {
                        Text("+\(tasks.count - 2) more")
                            .font(.caption2)
                            .foregroundColor(isCurrent ? .white.opacity(0.6) : .secondary)
                    }
                }
            }
            
            // Tasks count
            if !tasks.isEmpty {
                Text("\(tasks.filter { $0.isCompleted }.count)/\(tasks.count)")
                    .font(.caption2)
                    .foregroundColor(isCurrent ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(10)
        .frame(width: 130, height: 170)
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
    let blockIndex: Int
    
    @State private var newTaskTitle: String = ""
    @State private var newTaskPomo: Int = 1
    
    var body: some View {
        let tasks = blockIndex < settingsManager.settings.blockTasks.count 
            ? settingsManager.settings.blockTasks[blockIndex] 
            : []
        
        return VStack(spacing: 16) {
            // Header with goal
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Block \(blockIndex + 1)")
                        .font(.headline)
                    
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
                    .font(.subheadline)
                }
                
                Spacer()
                
                Button("Done") {
                    if let window = NSApp.keyWindow {
                        window.close()
                    }
                }
            }
            
            Divider()
            
            // Tasks list
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tasks")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !tasks.isEmpty {
                        Text("\(tasks.filter { $0.isCompleted }.count)/\(tasks.count) completed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            HStack(spacing: 8) {
                                Button(action: {
                                    toggleTask(task: task)
                                }) {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
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
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            
            Divider()
            
            // Add new task
            VStack(alignment: .leading, spacing: 4) {
                Text("Add New Task")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("Task title", text: $newTaskTitle)
                        .textFieldStyle(.roundedBorder)
                    
                    Stepper("\(newTaskPomo)p", value: $newTaskPomo, in: 1...12)
                    
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 600)
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
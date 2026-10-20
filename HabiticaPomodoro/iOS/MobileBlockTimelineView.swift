import SwiftUI

/// Chronological horizontal timeline with a Current anchor; uses the desktop's block arrays.
struct MobileBlockTimelineView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var blocks = BlockProgressManager.shared
    @State private var selection: Int?
    private var settings: UserSettings { settingsManager.settings }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Block Timeline").font(.headline)
                    Spacer()
                    Button {
                        blocks.updateBlockIndexFromTime(settings: settings)
                        withAnimation { proxy.scrollTo(blocks.blockProgress.currentBlockIndex, anchor: .center) }
                    } label: { Label("Current", systemImage: "location.fill") }
                        .font(.caption)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<settings.blockCount, id: \.self) { index in
                            let counts = blocks.getTodayBlockProgress(settings: settings)
                            let completed = counts.indices.contains(index) ? counts[index] : 0
                            let tasks = settings.blockTasks.indices.contains(index) ? settings.blockTasks[index] : []
                            let isCurrent = index == blocks.blockProgress.currentBlockIndex
                            Button { selection = index } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("B\(index + 1)").font(.subheadline.bold())
                                    if settings.blockTimeRanges.indices.contains(index) {
                                        Text(settings.blockTimeRanges[index].displayString).font(.caption2.monospacedDigit())
                                    }
                                    ProgressView(value: Double(min(completed, settings.blockPomoCount)), total: Double(settings.blockPomoCount))
                                    Text("\(completed)/\(settings.blockPomoCount) 🍅").font(.caption)
                                    ForEach(tasks.prefix(2)) { task in
                                        Label(task.title, systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(.caption2).lineLimit(1)
                                    }
                                    Text("任务 \(tasks.filter(\.isCompleted).count)/\(tasks.count)")
                                        .font(.caption2)
                                }
                                .foregroundColor(isCurrent ? .white : .primary)
                                .tint(isCurrent ? .white : .orange)
                                .frame(width: 142, height: 152, alignment: .topLeading)
                                .padding(12)
                                .background(isCurrent ? Color.orange : Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onAppear {
                    blocks.updateBlockIndexFromTime(settings: settings)
                    proxy.scrollTo(blocks.blockProgress.currentBlockIndex, anchor: .center)
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            if let index = selection { NavigationStack { MobileBlockEditorView(blockIndex: index) } }
        }
    }
}

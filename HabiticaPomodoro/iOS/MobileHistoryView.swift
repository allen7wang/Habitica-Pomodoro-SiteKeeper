import SwiftUI

/// Local focus histogram and persisted block history; uses the same stores as the desktop app.
struct MobileHistoryView: View {
    @ObservedObject private var histogram = HistogramManager.shared
    @ObservedObject private var blocks = BlockProgressManager.shared
    @ObservedObject private var plants = PlantJournal.shared
    @State private var confirmClear = false
    @State private var clearBlocks = false

    var body: some View {
        List {
            Section("专注统计") {
                LabeledContent("今天番茄", value: "\(histogram.getToday()?.pomodoros ?? 0)")
                LabeledContent("今天分钟", value: "\(histogram.getToday()?.minutes ?? 0)")
                LabeledContent("今天小时", value: String(format: "%.1f", Double(histogram.getToday()?.minutes ?? 0) / 60))
                LabeledContent("累计番茄", value: "\(histogram.totalPomodoros)")
                LabeledContent("累计分钟", value: "\(histogram.histogram.values.reduce(0) { $0 + $1.minutes })")
                LabeledContent("累计小时", value: String(format: "%.1f", histogram.totalHours))
                LabeledContent("每日平均番茄", value: String(format: "%.1f", histogram.avgPomodoros))
                LabeledContent("每日平均小时", value: String(format: "%.1f", histogram.avgHours))
            }
            Section("近 14 个有记录的日期") {
                ForEach(Array(histogram.sortedEntries.suffix(14).reversed()), id: \.date) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.date).font(.caption.monospacedDigit())
                            Spacer()
                            Text("\(item.day.pomodoros) 🍅 · \(item.day.minutes) 分")
                        }
                        ProgressView(value: Double(item.day.pomodoros), total: Double(max(1, histogram.sortedEntries.map { $0.day.pomodoros }.max() ?? 1)))
                    }
                }
            }
            Section("时间块历史") {
                ForEach(blocks.blockHistory.keys.sorted().reversed(), id: \.self) { date in
                    DisclosureGroup(date) {
                        ForEach(Array((blocks.blockHistory[date] ?? []).enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text("B\(entry.blockIndex + 1)")
                                Spacer()
                                Text("\(entry.pomodoros) / " + (entry.isComplete ? "已完成" : "未完成"))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Section("植物历史") {
                ForEach(plants.days.keys.sorted().reversed(), id: \.self) { key in
                    if let day = plants.days[key] {
                        DisclosureGroup(key) {
                            ForEach(day.attempts.indices, id: \.self) { index in
                                HStack {
                                    Text("B\(index + 1)")
                                    Spacer()
                                    Text("🌿 \(day.attempts[index].filter { $0 == .shrub }.count) · 🥀 \(day.attempts[index].filter { $0 == .wilted }.count) · 🌳 \(day.trees.indices.contains(index) ? day.trees[index] : 0)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button("清空番茄统计", role: .destructive) { confirmClear = true }
                Button("清空块与植物历史", role: .destructive) { clearBlocks = true }
            }
        }
        .navigationTitle("统计与历史")
        .confirmationDialog("确认清空番茄统计？不删除时间块、植物或 Task。", isPresented: $confirmClear) {
            Button("清空番茄统计", role: .destructive) { histogram.clear() }
        }
        .confirmationDialog("确认清空块与植物历史？不删除番茄统计或 Task。", isPresented: $clearBlocks) {
            Button("清空块与植物历史", role: .destructive) { blocks.clearHistory() }
        }
    }
}

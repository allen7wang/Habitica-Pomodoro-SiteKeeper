import Foundation

enum FocusReviewRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var title: String { "\(rawValue) 天" }
}

struct FocusReviewBlock: Identifiable {
    let id: Int  // Zero-based index in the saved block records.
    let completedPomodoros: Int
    let isCompleted: Bool
    let goal: String?
    let shrubs: Int
    let trees: Int
    let wilted: Int
}

struct FocusReviewDay: Identifiable {
    let id: String
    let date: Date
    let pomodoros: Int
    let minutes: Int
    let blocks: [FocusReviewBlock]

    var hasRecords: Bool { pomodoros > 0 || minutes > 0 || !blocks.isEmpty }
    var completedBlocks: Int { blocks.filter(\.isCompleted).count }
    var shrubs: Int { blocks.reduce(0) { $0 + $1.shrubs } }
    var trees: Int { blocks.reduce(0) { $0 + $1.trees } }
    var wilted: Int { blocks.reduce(0) { $0 + $1.wilted } }
}

struct FocusReviewTotals {
    var pomodoros = 0
    var minutes = 0
    var activeDays = 0
    var completedBlocks = 0
    var shrubs = 0
    var trees = 0
    var wilted = 0
}

/// A read-only projection of the existing calendar-day stores.
struct FocusReview {
    let days: [FocusReviewDay]
    let totals: FocusReviewTotals

    var startKey: String { days.first?.id ?? "" }
    var endKey: String { days.last?.id ?? "" }
    var hasRecords: Bool { days.contains(where: \.hasRecords) }

    init(range: FocusReviewRange, now: Date, histogram: Histogram, dailyBlocks: DailyBlocksHistory,
         blockHistory: BlockHistory, plants: [String: PlantDay], calendar: Calendar = .current) {
        let formatter = Self.dateKeyFormatter(calendar: calendar)
        let today = calendar.startOfDay(for: now)

        days = (0..<range.rawValue).reversed().compactMap { offset in
            guard let offsetDate = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let date = calendar.startOfDay(for: offsetDate)
            let key = formatter.string(from: date)
            return Self.day(key: key, date: date, focus: histogram[key], daily: dailyBlocks[key],
                            history: blockHistory[key] ?? [], plants: plants[key])
        }

        totals = days.reduce(into: FocusReviewTotals()) { totals, day in
            totals.pomodoros += day.pomodoros
            totals.minutes += day.minutes
            if day.pomodoros > 0 || day.minutes > 0 { totals.activeDays += 1 }
            totals.completedBlocks += day.completedBlocks
            totals.shrubs += day.shrubs
            totals.trees += day.trees
            totals.wilted += day.wilted
        }
    }

    static func earliestDate(histogram: Histogram, dailyBlocks: DailyBlocksHistory, blockHistory: BlockHistory,
                             plants: [String: PlantDay], calendar: Calendar = .current) -> Date? {
        let formatter = dateKeyFormatter(calendar: calendar)
        let keys = Set(histogram.keys).union(dailyBlocks.keys).union(blockHistory.keys).union(plants.keys)
        for key in keys.sorted() {
            guard let date = formatter.date(from: key), formatter.string(from: date) == key else { continue }
            if day(key: key, date: date, focus: histogram[key], daily: dailyBlocks[key],
                   history: blockHistory[key] ?? [], plants: plants[key]).hasRecords {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    var csv: String {
        let header = "date,pomodoros,minutes,completed_blocks,shrubs,trees,wilted"
        let rows = days.map { day in
            "\(day.id),\(day.pomodoros),\(day.minutes),\(day.completedBlocks),\(day.shrubs),\(day.trees),\(day.wilted)"
        }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private static func dateKeyFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func day(key: String, date: Date, focus: DayHistogram?, daily: DailyBlockProgress?,
                            history: [BlockHistoryEntry], plants: PlantDay?) -> FocusReviewDay {
        FocusReviewDay(id: key, date: date, pomodoros: max(0, focus?.pomodoros ?? 0),
                       minutes: max(0, focus?.minutes ?? 0), blocks: blocks(daily: daily, history: history, plants: plants))
    }

    private static func blocks(daily: DailyBlockProgress?, history: [BlockHistoryEntry],
                               plants: PlantDay?) -> [FocusReviewBlock] {
        let progress = daily?.blockProgress ?? []
        let goals = daily?.blockGoals ?? []
        let attempts = plants?.attempts ?? []
        let treeCounts = plants?.trees ?? []
        // UserSettings supports up to 24 blocks, including blocks from older configurations.
        let validIndices = 0..<24
        let historyByBlock = Dictionary(grouping: history.filter { validIndices.contains($0.blockIndex) }, by: \.blockIndex)
        let storedBlockCount = min(validIndices.count, max(progress.count, attempts.count, treeCounts.count))
        let indices = Set(0..<storedBlockCount).union(historyByBlock.keys)

        return indices.sorted().compactMap { index in
            let entries = historyByBlock[index] ?? []
            let historicalCount = entries.map(\.pomodoros).max() ?? 0
            // A saved zero can be an explicit reset. Use the historical count only when absent.
            let count = max(0, progress.indices.contains(index) ? progress[index] : historicalCount)
            let isCompleted = entries.contains(where: \.isComplete)
            let outcomes = attempts.indices.contains(index) ? attempts[index] : []
            let shrubs = outcomes.filter { $0 == .shrub }.count
            let trees = treeCounts.indices.contains(index) ? max(0, treeCounts[index]) : 0
            let wilted = outcomes.count - shrubs
            guard count > 0 || isCompleted || shrubs > 0 || trees > 0 || wilted > 0 else { return nil }
            let goal = goals.indices.contains(index) ? goals[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return FocusReviewBlock(id: index, completedPomodoros: count, isCompleted: isCompleted,
                                    goal: goal.isEmpty ? nil : goal, shrubs: shrubs, trees: trees, wilted: wilted)
        }
    }
}

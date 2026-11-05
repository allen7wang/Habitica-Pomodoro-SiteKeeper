import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let now = calendar.date(from: DateComponents(year: 2024, month: 3, day: 12, hour: 2))!

func focus(_ pomodoros: Int, _ minutes: Int) -> DayHistogram {
    DayHistogram(pomodoros: pomodoros, minutes: minutes, weekday: "")
}

func completed(_ date: String, _ block: Int, _ count: Int) -> BlockHistoryEntry {
    BlockHistoryEntry(date: date, blockIndex: block, pomodoros: count, isComplete: true, completedAt: nil)
}

let legacyDay = "2024-03-07"
let overlapDay = "2024-03-09"
let plantOnlyDay = "2024-03-10"
let histogram = [
    "2024-01-01": focus(0, 0),
    "2024-02-30": focus(99, 99),
    overlapDay: focus(2, 35),
    "2024-03-12": focus(1, 25),
    "2024-03-13": focus(99, 99),
]
let dailyBlocks = [overlapDay: DailyBlockProgress(
    date: overlapDay, blockProgress: [0, 2, 0], blockGoals: ["Reset", "  Private, focus  ", "Unused"]
)]
let blockHistory = [
    legacyDay: [completed(legacyDay, 4, 3), completed(legacyDay, 4, 2)],
    overlapDay: [completed(overlapDay, 0, 3), completed(overlapDay, 1, 1),
                 completed(overlapDay, -1, 99), completed(overlapDay, Int.max, 99)],
]
let plants = [
    overlapDay: PlantDay(attempts: [[.shrub], [.shrub, .wilted]], trees: [0, 1]),
    plantOnlyDay: PlantDay(attempts: [[], [], [.wilted, .wilted]], trees: [0, 0, 1]),
]

let review = FocusReview(range: .week, now: now, histogram: histogram, dailyBlocks: dailyBlocks,
                         blockHistory: blockHistory, plants: plants, calendar: calendar)
precondition(review.days.map(\.id) == (6...12).map { String(format: "2024-03-%02d", $0) })
precondition(review.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
precondition(review.startKey == "2024-03-06" && review.endKey == "2024-03-12")
precondition(review.hasRecords && !review.days[0].hasRecords && !review.days[2].hasRecords)
precondition(review.totals.pomodoros == 3 && review.totals.minutes == 60 && review.totals.activeDays == 2)
print("PASS calendar-day range, DST, zero-filled days and histogram-only focus totals")

let legacy = review.days[1]
precondition(legacy.hasRecords && legacy.completedBlocks == 1 && legacy.shrubs == 0)
precondition(legacy.blocks.count == 1 && legacy.blocks[0].id == 4 && legacy.blocks[0].completedPomodoros == 3)
let overlap = review.days[3]
precondition(overlap.blocks.map(\.id) == [0, 1] && overlap.blocks.map(\.completedPomodoros) == [0, 2])
precondition(overlap.blocks[1].goal == "Private, focus" && overlap.completedBlocks == 2 && overlap.shrubs == 2)
let plantOnly = review.days[4]
precondition(plantOnly.hasRecords && plantOnly.pomodoros == 0 && plantOnly.wilted == 2)
precondition(review.totals.completedBlocks == 3 && review.totals.shrubs == 2 &&
             review.totals.trees == 2 && review.totals.wilted == 3)
print("PASS legacy block fallback, duplicate records, reset counts, and explicit plant markers")

let rows = review.csv.components(separatedBy: "\r\n")
precondition(rows.count == 9 && rows.last == "")
precondition(rows[0] == "date,pomodoros,minutes,completed_blocks,shrubs,trees,wilted")
precondition(rows[1] == "2024-03-06,0,0,0,0,0,0" && rows[4] == "2024-03-09,2,35,2,2,1,1")
precondition(!review.csv.contains("Private") && !review.csv.contains("2024-03-13"))
print("PASS CSV includes all selected dates and excludes goals and out-of-window records")

let earliest = FocusReview.earliestDate(histogram: histogram, dailyBlocks: dailyBlocks,
                                        blockHistory: blockHistory, plants: plants, calendar: calendar)
precondition(earliest == legacy.date)
let month = FocusReview(range: .month, now: now, histogram: [:], dailyBlocks: [:],
                        blockHistory: [:], plants: [:], calendar: calendar)
precondition(month.days.count == 30 && month.startKey == "2024-02-12" && !month.hasRecords)
precondition(month.days.contains { $0.id == "2024-02-29" })
let quarter = FocusReview(range: .quarter, now: now, histogram: [:], dailyBlocks: [:],
                          blockHistory: [:], plants: [:], calendar: calendar)
precondition(quarter.days.count == 90 && quarter.startKey == "2023-12-14" && !quarter.hasRecords)
precondition(FocusReview.earliestDate(histogram: [:], dailyBlocks: [:], blockHistory: [:], plants: [:]) == nil)
print("PASS earliest activity excludes invalid and zero records, 30-day leap and 90-day year boundaries")

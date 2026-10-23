import Foundation
import Combine
import Darwin

// Only synthetic A/B directories selected through the DEBUG seam. This does
// not exercise iOS security-scoped access, bookmarks, or real folder migration.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let a = root.appendingPathComponent("A", isDirectory: true)
let b = root.appendingPathComponent("B", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: a, withIntermediateDirectories: true)
try fm.createDirectory(at: b, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
let decoder = JSONDecoder()
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
let key = formatter.string(from: Date())
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { print("PASS \(label)") }
    else { print("FAIL \(label)"); failures += 1 }
}
func write<T: Encodable>(_ directory: URL, _ name: String, _ value: T) {
    try! encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
}
func seed(_ directory: URL, _ value: Int) {
    var configuration = UserSettings()
    configuration.connectHabitica = false
    configuration.uid = ""
    configuration.apiToken = ""
    configuration.ambientSource = "custom"
    configuration.ambientSound = "None"
    configuration.pomoDurationMins = value
    write(directory, "habitica_pomodoro_settings.json", configuration)
    var progress = BlockProgress()
    progress.progressDate = key
    progress.blockPomoCounter = value
    write(directory, "habitica_pomodoro_block_progress.json", progress)
    write(directory, "habitica_pomodoro_block_history.json", [key: [BlockHistoryEntry(
        date: key, blockIndex: 0, pomodoros: value, isComplete: false, completedAt: nil)]])
    write(directory, "habitica_pomodoro_daily_blocks.json", [key: DailyBlockProgress(
        date: key, blockProgress: [value], blockGoals: [])])
    var top = TopThreeStore()
    top.categoryNames = ["Fixture \(value)", "Own", "Chores"]
    write(directory, "habitica_pomodoro_top_three.json", top)
    write(directory, "habitica_pomodoro_plants.json", [key: PlantDay(attempts: [[.shrub]], trees: [value])])
    write(directory, "habitica_pomodoro_histogram.json", [key: DayHistogram(
        pomodoros: value, minutes: value, weekday: "Fixture")])
}
seed(a, 25)
seed(b, 26)
PomodoroDataDir.isolatedDirectory = a
let settings = SettingsManager.shared
let blocks = BlockProgressManager.shared
let top = TopThreeManager.shared
let plants = PlantJournal.shared
let histogram = HistogramManager.shared
let monitor = PomodoroFileChanges.shared
check(!settings.settings.connectHabitica && settings.settings.uid.isEmpty && settings.settings.apiToken.isEmpty,
      "dirty reload fixture disables account and audio transports")
func reloadAll(_ directory: URL) {
    PomodoroDataDir.isolatedDirectory = directory
    settings.reload()
    blocks.reload()
    top.reload()
    plants.reload()
    histogram.reload()
}
func pump(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
func sync() {
    var done = false
    monitor.syncFromDiskIfNeeded { done = true }
    let timeout = Date().addingTimeInterval(8)
    while !done && Date() < timeout { pump(0.01) }
    precondition(done, "scan timed out")
}
func failedSaves() {
    try! fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: a.path)
    settings.settings.pomoDurationMins = 48
    blocks.blockProgress.blockPomoCounter = 48
    blocks.blockHistory[key] = [BlockHistoryEntry(date: key, blockIndex: 0, pomodoros: 48, isComplete: false, completedAt: nil)]
    blocks.dailyBlocksHistory[key] = DailyBlockProgress(date: key, blockProgress: [48], blockGoals: [])
    top.store.categoryNames[0] = "Failed edit"
    plants.recordAbandonment(blockIndex: 0, completed: 1)
    histogram.incrementToday(pomodoros: 1, minutes: 1)
    check(!settings.save() && !blocks.saveProgress() && !blocks.saveHistory() && !blocks.saveDailyBlocks() &&
          !top.save() && !plants.save() && !histogram.save(), "all seven local saves really fail")
    try! fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: a.path)
}
failedSaves()
reloadAll(b)
reloadAll(a)
check(settings.settings.pomoDurationMins == 25 && blocks.blockProgress.blockPomoCounter == 25 &&
      top.store.categoryNames[0] == "Fixture 25" && plants.days[key]?.trees == [25] &&
      histogram.histogram[key]?.pomodoros == 25, "A-B-A explicit reload replaces discarded failed edits with valid A files")
seed(a, 27)
sync()
check(settings.settings.pomoDurationMins == 27, "settings remote update accepted after successful explicit reload")
check(blocks.blockProgress.blockPomoCounter == 27, "block progress remote update accepted after successful explicit reload")
check(blocks.blockHistory[key]?.first?.pomodoros == 27, "block history remote update accepted after successful explicit reload")
check(blocks.dailyBlocksHistory[key]?.blockProgress == [27], "daily blocks remote update accepted after successful explicit reload")
check(top.store.categoryNames[0] == "Fixture 27", "Top3 remote update accepted after successful explicit reload")
check(plants.days[key]?.trees == [27], "plants remote update accepted after successful explicit reload")
check(histogram.histogram[key]?.pomodoros == 27, "histogram remote update accepted after successful explicit reload")

// A failed/undecodable explicit reload is not a discard/acknowledgement.
failedSaves()
for name in PomodoroDataDir.dataFileNames {
    try Data("bad-json".utf8).write(to: a.appendingPathComponent(name), options: .atomic)
}
reloadAll(a)
let retainedSettings = settings.settings.pomoDurationMins
let retainedBlocks = blocks.blockProgress.blockPomoCounter
let retainedTop = top.store.categoryNames
let retainedPlants = try encoder.encode(plants.days)
let retainedHistogram = histogram.histogram
seed(a, 29)
sync()
check(settings.settings.pomoDurationMins == retainedSettings && blocks.blockProgress.blockPomoCounter == retainedBlocks &&
      top.store.categoryNames == retainedTop && (try! encoder.encode(plants.days)) == retainedPlants &&
      histogram.histogram == retainedHistogram, "bad JSON explicit reload retains dirty protection across sibling stores")

// A synchronous subscriber creates a NEW failed edit during a valid reload.
// Acknowledge only the dirty generation the reload actually replaced.
reloadAll(b)
reloadAll(a)
var injectedHistogram = false
let notification = NotificationCenter.default.addObserver(forName: .histogramChanged, object: nil, queue: .main) { _ in
    guard !injectedHistogram else { return }
    injectedHistogram = true
    try! fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: a.path)
    histogram.incrementToday(pomodoros: 5, minutes: 5)
    try! fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: a.path)
}
histogram.reload()
NotificationCenter.default.removeObserver(notification)
let reentrantHistogram = histogram.histogram
var injectedPlants = false
let subscription = plants.$days.dropFirst().sink { _ in
    guard !injectedPlants else { return }
    injectedPlants = true
    try! fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: a.path)
    precondition(!plants.save(), "subscriber save must fail")
    try! fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: a.path)
}
plants.reload()
subscription.cancel()
let reentrantPlants = try encoder.encode(plants.days)
seed(a, 30)
sync()
check(injectedHistogram && histogram.histogram == reentrantHistogram,
      "synchronous histogram notification failed edit remains protected after explicit reload")
check(injectedPlants && (try! encoder.encode(plants.days)) == reentrantPlants,
      "synchronous plant publication failed edit remains protected after explicit reload")
print("DIRTY_RELOAD_SUITE \(failures == 0 ? "PASS" : "FAIL") failures=\(failures) (synthetic DEBUG folders only)")
exit(failures == 0 ? 0 : 1)

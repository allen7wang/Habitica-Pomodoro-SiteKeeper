import Foundation
import Combine
import Darwin
import UserNotifications

// Native-delay + real state machine/Timer probe. The runner compiles both real
// activation bodies verbatim into adapters; only media, notification delivery,
// and the unused iOS grant/status transport are fixture-local doubles.
let fixture = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sibling = fixture.appendingPathComponent("B", isDirectory: true)
try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
let encoder = JSONEncoder()
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { print("PASS \(label)") }
    else { print("FAIL \(label)"); failures += 1 }
}
func key(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
var configuration = UserSettings()
configuration.connectHabitica = false
configuration.uid = ""
configuration.apiToken = ""
configuration.ambientSource = "custom"
configuration.ambientSound = "None"
configuration.pomoEndSound = "None"
configuration.breakEndSound = "None"
configuration.pomoDurationMins = 1
configuration.pomoSetNum = 4
configuration.manualBreak = true
configuration.enableBlockMode = true
configuration.blockCount = 1
configuration.blockPomoCount = 100
configuration.blockStartReminder = false
configuration.blockSprintReminder = false
configuration.blockRewardEnabled = false
configuration.blockTimeRanges = [BlockTimeRange(startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)]
func write<T: Encodable>(_ directory: URL, _ name: String, _ value: T) {
    try! encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
}
func seed(_ directory: URL, day: String, count: Int = 5, blockCount: Int = 1, treeCount: Int = 1) {
    write(directory, "habitica_pomodoro_settings.json", configuration)
    var block = BlockProgress()
    block.currentBlockIndex = 0
    block.progressDate = day
    block.blockPomoCounter = blockCount
    write(directory, "habitica_pomodoro_block_progress.json", block)
    write(directory, "habitica_pomodoro_block_history.json", BlockHistory())
    write(directory, "habitica_pomodoro_daily_blocks.json", [day: DailyBlockProgress(
        date: day, blockProgress: [blockCount], blockGoals: [])])
    write(directory, "habitica_pomodoro_top_three.json", TopThreeStore())
    write(directory, "habitica_pomodoro_plants.json", [day: PlantDay(attempts: [[.wilted, .shrub]], trees: [treeCount])])
    write(directory, "habitica_pomodoro_histogram.json", [day: DayHistogram(
        pomodoros: count, minutes: count, weekday: "Fixture")])
}
seed(fixture, day: key(Date()))
PomodoroDataDir.isolatedDirectory = fixture
let settings = SettingsManager.shared
let blocks = BlockProgressManager.shared
let plants = PlantJournal.shared
let histogram = HistogramManager.shared
let monitor = PomodoroFileChanges.shared
let engine = PomodoroEngine.shared
check(!engine.settings.connectHabitica && engine.settings.uid.isEmpty && engine.settings.apiToken.isEmpty,
      "foreground recovery fixture disables Habitica and real output transports")
let handle = dlopen(nil, RTLD_NOW)!
guard let symbol = dlsym(handle, "pomo_slow_read_count") else { fatalError("missing native delay transport") }
let delayedReads = unsafeBitCast(symbol, to: (@convention(c) () -> UInt64).self)
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.01))) }
}
func sync() {
    var done = false
    monitor.syncFromDiskIfNeeded { done = true }
    let timeout = Date().addingTimeInterval(8)
    while !done && Date() < timeout { pump(0.01) }
    precondition(done, "scan timed out")
}
func reload(_ directory: URL) {
    PomodoroDataDir.isolatedDirectory = directory
    settings.reload()
    blocks.reload()
    TopThreeManager.shared.reload()
    plants.reload()
    histogram.reload()
}
func restore() {
    unsetenv("POMO_SLOW_READ_PATH")
    sync()
    engine.reset()
    configuration.manualBreak = true
    seed(fixture, day: key(Date()))
    reload(fixture)
}
func delay() { setenv("POMO_SLOW_READ_PATH", fixture.appendingPathComponent("habitica_pomodoro_settings.json").path, 1) }
var maxGap = 0.0
var lastBeat = Date()
var beats = 0
let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
    let now = Date()
    maxGap = max(maxGap, now.timeIntervalSince(lastBeat))
    lastBeat = now
    beats += 1
}

// Already-arrived remote files must be accepted before an elapsed focus writes.
engine.startPomodoro()
let deadline = engine.phaseEndsAt!
let day = key(deadline)
seed(fixture, day: day, count: 9, blockCount: 4, treeCount: 9)
let notificationsBefore = UNUserNotificationCenter.current().requests.count
let readsBefore = delayedReads()
delay()
engine.resyncAfterForeground(now: deadline.addingTimeInterval(0.01))
engine.resyncAfterForeground(now: deadline.addingTimeInterval(0.01))
pump(0.08)
check(engine.phase == .pomodoro && engine.pomoSetCounter == 0,
      "elapsed focus settlement waits for accepted asynchronous foreground reads")
sync()
unsetenv("POMO_SLOW_READ_PATH")
check(delayedReads() > readsBefore, "foreground recovery actually exercises native delayed reads")
check(blocks.dailyBlocksHistory[day]?.blockProgress == [5] && blocks.blockProgress.blockPomoCounter == 5,
      "elapsed focus appends to arrived remote block progress instead of overwriting it")
check(plants.days[day]?.trees == [9] && plants.days[day]?.attempts.first?.contains(.wilted) == true &&
      plants.days[day]?.attempts.first?.filter { $0 == .shrub }.count == 5,
      "elapsed focus preserves remote plant history and tree totals")
check(histogram.histogram[day]?.pomodoros == 10 && engine.pomoSetCounter == 1 &&
      UNUserNotificationCenter.current().requests.count == notificationsBefore + 1,
      "overlapping foreground recoveries settle focus exactly once")

// Both actual platform activation bodies must enter the same recovery boundary.
// A real 1-second scheduled Timer becomes due before the 1.2-second read ends.
for (name, activate) in [("Mac", fixtureMacDidBecomeActive), ("iOS", fixtureIOSDidBecomeActive)] {
    restore()
    engine.startBreakExtension(duration: 1)
    let due = engine.phaseEndsAt!
    delay()
    let before = delayedReads()
    activate()
    pump(max(0, due.timeIntervalSinceNow) + 0.06)
    check(delayedReads() > before && engine.phase == .breakExtension && engine.isRunning,
          "\(name) real activation body fences an actually scheduled expiry while refresh is pending")
    var phaseAtAcceptedRead: TimerPhase?
    monitor.syncFromDiskIfNeeded { phaseAtAcceptedRead = engine.phase }
    sync()
    unsetenv("POMO_SLOW_READ_PATH")
    check(phaseAtAcceptedRead == .idle && engine.phase == .idle,
          "\(name) foreground completion uses completion-time wall clock without waiting for another tick")
}

// Late accepted reads cannot settle the phase a user reset/paused/replaced.
for action in ["reset", "pause", "new phase", "folder switch", "A-B-A switch"] {
    restore()
    engine.startPomodoro()
    let simulatedExpiry = engine.phaseEndsAt!.addingTimeInterval(0.01)
    let countBefore = histogram.totalPomodoros
    delay()
    engine.resyncAfterForeground(now: simulatedExpiry)
    pump(0.06)
    switch action {
    case "reset": engine.reset()
    case "pause": engine.freeze()
    case "new phase": engine.reset(); engine.startPomodoro()
    default:
        // Synthetic DEBUG paths ONLY: no grant/bookmark APIs, no real migration.
        unsetenv("POMO_SLOW_READ_PATH")
        seed(sibling, day: key(Date()))
        reload(sibling)
        if action == "A-B-A switch" { reload(fixture) }
    }
    sync()
    unsetenv("POMO_SLOW_READ_PATH")
    check(histogram.totalPomodoros == countBefore && engine.pomoSetCounter == 0,
          "late foreground completion cannot settle after \(action)")
    if action == "pause" {
        check(engine.isFrozen && engine.phase == .pomodoro, "pause remains frozen after foreground read acceptance")
    }
    if action == "folder switch" || action == "A-B-A switch" {
        check(engine.isFrozen && engine.phase == .pomodoro,
              "folder change cancels old recovery ownership before any later scheduled settlement")
    }
    if action == "new phase" {
        check(engine.phase == .pomodoro && engine.isRunning && (engine.phaseEndsAt?.timeIntervalSinceNow ?? 0) > 50,
              "new focus owns its own deadline after stale foreground completion")
    }
}

restore()
configuration.manualBreak = false
configuration.breakDuration = 1
configuration.breakExtention = 1
seed(fixture, day: key(Date()))
reload(fixture)
engine.startPomodoro()
let chainDeadline = engine.phaseEndsAt!
let beforeChain = histogram.totalPomodoros
delay()
engine.resyncAfterForeground(now: chainDeadline.addingTimeInterval(121))
sync()
unsetenv("POMO_SLOW_READ_PATH")
check(engine.phase == .idle && histogram.totalPomodoros == beforeChain + 1,
      "accepted foreground recovery catches up focus-break-grace without fabricating another focus")
engine.reset()
BlockNotificationManager.shared.stopReminderTimer()
heartbeat.invalidate()
check(beats > 0 && maxGap < 0.3, "foreground recovery keeps the main run loop responsive")
print(String(format: "FOREGROUND_RECOVERY_SUITE %@ failures=%d main_max_gap=%.3fs delayed_reads=%llu (synthetic transports)",
             failures == 0 ? "PASS" : "FAIL", failures, maxGap, delayedReads()))
exit(failures == 0 ? 0 : 1)

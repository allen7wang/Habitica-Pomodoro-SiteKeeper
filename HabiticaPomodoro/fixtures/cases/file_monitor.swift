import Foundation
import Combine
import Darwin

// run.py verifies Foundation's home/Documents and sets the DEBUG seam before
// this case begins. Repeat the critical checks before touching any manager.
let environment = ProcessInfo.processInfo.environment
let fixture = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
guard let rootPath = environment["POMO_FIXTURE_RUN_ROOT"],
      let homePath = environment["CFFIXED_USER_HOME"],
      let dataPath = environment["POMO_FIXTURE_DATA_ROOT"] else {
    fatalError("Run this case through fixtures/run.py with an isolated scratch root")
}
let safeRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
let safeHome = URL(fileURLWithPath: homePath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
precondition(fixture.path.hasPrefix(safeRoot.path + "/"), "fixture must be inside this unique run root")
precondition(fixture.path == URL(fileURLWithPath: dataPath).resolvingSymlinksInPath().path)
precondition(safeHome.path.hasPrefix(safeRoot.path + "/"), "home must be synthetic")
precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path == safeHome.path,
             "CFFIXED_USER_HOME did not isolate Foundation")
precondition(geteuid() != 0, "permission-based failed-save probe requires a non-root user")
try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
PomodoroDataDir.isolatedDirectory = fixture
precondition(PomodoroDataDir.resolvedURL.standardizedFileURL == fixture, "DEBUG data directory isolation failed")

// The counter proves that the native read interposer was actually exercised;
// a missing/ignored DYLD_INSERT_LIBRARIES must not produce a false green result.
let processHandle = dlopen(nil, RTLD_NOW)!
guard let counterSymbol = dlsym(processHandle, "pomo_slow_read_count") else {
    fatalError("native slow-read interposer is not loaded")
}
let delayedReadCount = unsafeBitCast(counterSymbol, to: (@convention(c) () -> UInt64).self)

let encoder = JSONEncoder()
func write<T: Encodable>(_ name: String, _ value: T) {
    try! encoder.encode(value).write(to: fixture.appendingPathComponent(name), options: .atomic)
}
var initial = UserSettings()
initial.connectHabitica = false
initial.uid = ""
initial.apiToken = ""
initial.pomoDurationMins = 25
write("habitica_pomodoro_settings.json", initial)
write("habitica_pomodoro_block_progress.json", BlockProgress())
write("habitica_pomodoro_block_history.json", BlockHistory())
write("habitica_pomodoro_daily_blocks.json", DailyBlocksHistory())
write("habitica_pomodoro_top_three.json", TopThreeStore())
write("habitica_pomodoro_plants.json", [String: PlantDay]())
write("habitica_pomodoro_histogram.json", Histogram())
let settings = SettingsManager.shared
let blocks = BlockProgressManager.shared
let top = TopThreeManager.shared
let plants = PlantJournal.shared
let histogram = HistogramManager.shared
let monitor = PomodoroFileChanges.shared
let settingsURL = fixture.appendingPathComponent("habitica_pomodoro_settings.json")

var passedAssertions = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    passedAssertions += 1
    print("PASS \(label)")
}
let expectedFiles: Set<String> = [
    "habitica_pomodoro_settings.json", "habitica_pomodoro_block_progress.json",
    "habitica_pomodoro_block_history.json", "habitica_pomodoro_daily_blocks.json",
    "habitica_pomodoro_top_three.json", "habitica_pomodoro_plants.json",
    "habitica_pomodoro_histogram.json"
]
check(Set(PomodoroDataDir.dataFileNames) == expectedFiles && PomodoroDataDir.dataFileNames.count == 7,
      "all seven production stores are covered by the fixture")
check(!settings.settings.connectHabitica && settings.settings.uid.isEmpty && settings.settings.apiToken.isEmpty,
      "fixture settings contain no account and disable Habitica")

var maxGap = 0.0
var lastBeat = Date()
var beats = 0
let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
    let now = Date()
    maxGap = max(maxGap, now.timeIntervalSince(lastBeat))
    lastBeat = now
    beats += 1
}
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.01))) }
}
func sync() {
    var done = false
    monitor.syncFromDiskIfNeeded {
        precondition(Thread.isMainThread, "completion must run on main")
        done = true
    }
    let end = Date().addingTimeInterval(8)
    while !done && Date() < end { pump(0.01) }
    precondition(done, "background scan timed out")
}
var publications = 0
let subscription = settings.$settings.dropFirst().sink { _ in
    precondition(Thread.isMainThread, "settings publication on background queue")
    publications += 1
}

// Native read delays apply only to this exact synthetic settings file.
let readsBeforeSlowScan = delayedReadCount()
setenv("POMO_SLOW_READ_PATH", settingsURL.path, 1)
var remote = initial
remote.pomoDurationMins = 31
write("habitica_pomodoro_settings.json", remote)
sync()
check(settings.settings.pomoDurationMins == 31, "remote settings reload on main")
check(delayedReadCount() > readsBeforeSlowScan, "native slow read was actually injected")
check(beats > 0 && maxGap < 0.3, "slow disk leaves main responsive")
let beforeUnchanged = publications
sync()
check(publications == beforeUnchanged, "unchanged bytes do not republish")
unsetenv("POMO_SLOW_READ_PATH")

// Observe all real managers without calling account/network methods.
let key = histogram.todayKey()
var block = BlockProgress()
block.currentBlockIndex = 1
block.blockPomoCounter = 4
block.progressDate = key
write("habitica_pomodoro_block_progress.json", block)
write("habitica_pomodoro_block_history.json", [key: [BlockHistoryEntry(
    date: key, blockIndex: 1, pomodoros: 4, isComplete: true, completedAt: nil
)]])
write("habitica_pomodoro_daily_blocks.json", [key: DailyBlockProgress(date: key, blockProgress: [0, 4], blockGoals: [])])
var store = TopThreeStore()
store.categoryNames = ["Fixture Work", "Fixture Own", "Fixture Chores"]
write("habitica_pomodoro_top_three.json", store)
write("habitica_pomodoro_plants.json", [key: PlantDay(attempts: [[.shrub]], trees: [1])])
write("habitica_pomodoro_histogram.json", [key: DayHistogram(pomodoros: 3, minutes: 75, weekday: histogram.weekday())])
sync()
check(blocks.blockProgress.blockPomoCounter == 4 && blocks.dailyBlocksHistory[key]?.blockProgress == [0, 4] &&
      blocks.blockHistory[key]?.first?.pomodoros == 4,
      "three block files remain a consistent reload group")
check(top.store.categoryNames[0] == "Fixture Work", "Top3 snapshot applied")
check(plants.days[key]?.trees == [1], "plant snapshot applied")
check(histogram.histogram[key]?.pomodoros == 3, "histogram snapshot applied")

// A local write that races a delayed read must win. Its completion runs later.
remote.pomoDurationMins = 32
write("habitica_pomodoro_settings.json", remote)
setenv("POMO_SLOW_READ_PATH", settingsURL.path, 1)
var raceDone = false
monitor.syncFromDiskIfNeeded { raceDone = true }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    settings.settings.pomoDurationMins = 44
}
let raceEnd = Date().addingTimeInterval(8)
while !raceDone && Date() < raceEnd { pump(0.01) }
unsetenv("POMO_SLOW_READ_PATH")
check(raceDone && settings.settings.pomoDurationMins == 44, "local save invalidates in-flight remote read")

// Malformed bytes remain unconsumed: BOTH polls retry without resetting state.
let oldPublications = publications
try Data("not-json".utf8).write(to: settingsURL, options: .atomic)
sync()
let afterFirstCorruptPoll = publications
sync()
check(settings.settings.pomoDurationMins == 44 && afterFirstCorruptPoll > oldPublications && publications > afterFirstCorruptPoll,
      "bad decode remains retryable without resetting settings")
remote.pomoDurationMins = 45
write("habitica_pomodoro_settings.json", remote)
sync()
check(settings.settings.pomoDurationMins == 45, "valid revision after corruption is applied")

// Twenty overlapping requests share one scan, and each callback observes
// the accepted state AFTER all synchronous settings publications.
remote.pomoDurationMins = 46
write("habitica_pomodoro_settings.json", remote)
setenv("POMO_SLOW_READ_PATH", settingsURL.path, 1)
let old = publications
let readsBeforeCoalescing = delayedReadCount()
var callbacks = 0
var callbacksSawPublishedState = true
for _ in 0..<20 {
    monitor.syncFromDiskIfNeeded {
        callbacks += 1
        callbacksSawPublishedState = callbacksSawPublishedState && Thread.isMainThread &&
            settings.settings.pomoDurationMins == 46 && publications == old + 2
    }
}
let coalesceEnd = Date().addingTimeInterval(6)
while callbacks < 20 && Date() < coalesceEnd { pump(0.01) }
unsetenv("POMO_SLOW_READ_PATH")
check(callbacks == 20 && publications == old + 2 && callbacksSawPublishedState,
      "20 simultaneous requests coalesce; all completions run after publication")
// Settings normalizes once and publishes twice by its existing didSet contract.
check(delayedReadCount() == readsBeforeCoalescing + 1, "20 requests perform one native settings read")

// A failed local disk save keeps newer in-memory data dirty across polls.
remote.pomoDurationMins = 47
write("habitica_pomodoro_settings.json", remote)
setenv("POMO_SLOW_READ_PATH", settingsURL.path, 1)
var failedSaveDone = false
var failedSaveRetainedOldDisk = false
monitor.syncFromDiskIfNeeded { failedSaveDone = true }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    try! FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.path)
    settings.settings.pomoDurationMins = 48
    try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
}
let failedSaveEnd = Date().addingTimeInterval(8)
while !failedSaveDone && Date() < failedSaveEnd { pump(0.01) }
unsetenv("POMO_SLOW_READ_PATH")
let diskAfterFailedSave = try JSONDecoder().decode(UserSettings.self, from: Data(contentsOf: settingsURL))
failedSaveRetainedOldDisk = diskAfterFailedSave.pomoDurationMins == 47
check(failedSaveDone && settings.settings.pomoDurationMins == 48, "failed local save is not overwritten by an in-flight scan")
check(failedSaveRetainedOldDisk, "settings save really failed rather than silently writing through permissions")
sync()
check(settings.settings.pomoDurationMins == 48, "dirty in-memory settings survive later polls")
check(settings.save(), "dirty settings can be saved after permission recovery")

// A dirty member protects the entire related three-file block group.
blocks.blockProgress.blockPomoCounter = 7
try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.path)
check(!blocks.saveProgress(), "block write failure injected")
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
write("habitica_pomodoro_daily_blocks.json", [key: DailyBlockProgress(date: key, blockProgress: [0, 6], blockGoals: [])])
sync()
check(blocks.blockProgress.blockPomoCounter == 7 && blocks.dailyBlocksHistory[key]?.blockProgress == [0, 4],
      "dirty block progress is not replaced by a companion-file change")
check(blocks.saveProgress(), "dirty block progress can be saved after permission recovery")

// A synchronous settings subscriber may save another store while applying
// a snapshot; that local edit must invalidate later publications in the batch.
let remotePlant = [key: PlantDay(attempts: [[.shrub]], trees: [5])]
write("habitica_pomodoro_plants.json", remotePlant)
remote.pomoDurationMins = 49
write("habitica_pomodoro_settings.json", remote)
var injected = false
let reentrantSubscription = settings.$settings.dropFirst().sink { value in
    if value.pomoDurationMins == 49 && !injected {
        injected = true
        plants.recordAbandonment(blockIndex: 0, completed: 1)
        monitor.syncFromDiskIfNeeded()
    }
}
sync()
check(injected && plants.days[key]?.attempts.first?.contains(.wilted) == true, "reentrant local edit invalidates later snapshot publications")
reentrantSubscription.cancel()
subscription.cancel()
heartbeat.invalidate()
// The heartbeat stays active through races, corruption, dirty saves and reentry.
check(maxGap < 0.3, "all delayed-read scenarios leave the main run loop responsive")
print(String(format: "FILE_MONITOR_SUITE PASS assertions=%d main_max_gap=%.3fs beats=%d delayed_reads=%llu",
             passedAssertions, maxGap, beats, delayedReadCount()))

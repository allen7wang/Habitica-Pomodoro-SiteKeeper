import Darwin
import Foundation

// The runner verifies the synthetic home, bundle ID, and data folder before
// this case executes. Never construct a data manager before preparation.
let fixture = PomodoroDataDir.resolvedURL.standardizedFileURL
let monitor = PomodoroFileChanges.shared
let encoder = JSONEncoder()
let settingsURL = fixture.appendingPathComponent("habitica_pomodoro_settings.json")
let histogramURL = fixture.appendingPathComponent("habitica_pomodoro_histogram.json")
let missingURL = fixture.appendingPathComponent("habitica_pomodoro_block_history.json")
let dateKey = "2026-01-02"

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS \(label)")
}

func pumpUntil(_ finished: () -> Bool) {
    let deadline = ProcessInfo.processInfo.systemUptime + 8
    while !finished() && ProcessInfo.processInfo.systemUptime < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(finished(), "cold-launch preparation timed out")
}

let handle = dlopen(nil, RTLD_NOW)!
guard let counter = dlsym(handle, "pomo_slow_read_count") else {
    fatalError("native slow-read interposer is not loaded")
}
let delayedReads = unsafeBitCast(counter, to: (@convention(c) () -> UInt64).self)

// A regular file in place of the data directory produces a real directory-read
// failure independent of the user's filesystem permissions.
let blockedFile = fixture.appendingPathComponent("not-a-directory")
try Data("fixture sentinel".utf8).write(to: blockedFile)
PomodoroDataDir.isolatedDirectory = URL(fileURLWithPath: blockedFile.path, isDirectory: true)
var failureDelivered = false
monitor.prepareForMacLaunch { result in
    guard case .failure = result else { fatalError("invalid data directory was accepted") }
    check(Thread.isMainThread && monitor.prefetchedDirectory == nil,
          "directory-read failure reaches main without publishing a startup snapshot")
    failureDelivered = true
}
pumpUntil { failureDelivered }

PomodoroDataDir.isolatedDirectory = fixture
var configuration = UserSettings()
configuration.connectHabitica = false
configuration.uid = ""
configuration.apiToken = ""
configuration.pomoDurationMins = 37
configuration.blockStartReminder = false
configuration.blockSprintReminder = false
try encoder.encode(configuration).write(to: settingsURL, options: .atomic)
let seededDay = DayHistogram(pomodoros: 4, minutes: 148, weekday: "Fixture")
try encoder.encode([dateKey: seededDay]).write(to: histogramURL, options: .atomic)

var successDelivered = false
var beatsDuringRead = 0
let readsBefore = delayedReads()
precondition(setenv("POMO_SLOW_READ_PATH", settingsURL.path, 1) == 0)
let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
    if !successDelivered && delayedReads() > readsBefore {
        beatsDuringRead += 1
    }
}

monitor.prepareForMacLaunch { result in
    guard case .success = result else { fatalError("startup retry failed: \(result)") }
    check(Thread.isMainThread && monitor.prefetchedDirectory == fixture,
          "retry completion sees the accepted startup snapshot on main")
    let readsAtCompletion = delayedReads()
    check(readsAtCompletion > readsBefore, "cold start exercises the native delayed settings read")
    check(beatsDuringRead > 3, "main heartbeat continues while the cold settings read is in flight")

    let settings = SettingsManager.shared.settings
    check(settings.pomoDurationMins == 37 && !settings.connectHabitica && settings.uid.isEmpty && settings.apiToken.isEmpty,
          "first settings access sees the synthetic offline configuration")
    check(HistogramManager.shared.histogram[dateKey] == seededDay,
          "first histogram access sees the seeded history")
    check(!monitor.fileExists(at: missingURL) && BlockProgressManager.shared.blockHistory.isEmpty,
          "startup accepts missing files and initializes their stores empty")
    check(delayedReads() == readsAtCompletion, "manager warming reuses the snapshot without reading settings again")
    successDelivered = true
}
pumpUntil { successDelivered }
heartbeat.invalidate()
unsetenv("POMO_SLOW_READ_PATH")
check(monitor.prefetchedDirectory == nil, "startup snapshot is scoped to the successful completion")

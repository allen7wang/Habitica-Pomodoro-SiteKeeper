import Foundation
import Combine
import AVFoundation
import Darwin

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() {
        print("FAIL \(label)")
        fflush(stdout)
        exit(1)
    }
    print("PASS \(label)")
    fflush(stdout)
}

let fixture = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let isolatedHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
check(fixture.standardizedFileURL.deletingLastPathComponent() == isolatedHome.deletingLastPathComponent(), "fixture and isolated Foundation home share the verified case root")
check(Bundle.main.bundleIdentifier != "com.hermes.habitica-pomodoro", "fixture never uses installed app preferences domain")
try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
PomodoroDataDir.isolatedDirectory = fixture
var configuration = UserSettings()
configuration.connectHabitica = false
configuration.uid = ""
configuration.apiToken = ""
configuration.enableBlockMode = false
configuration.ambientSource = "qishi"
configuration.ambientSoundVolume = 0.4
try JSONEncoder().encode(configuration).write(to: fixture.appendingPathComponent("habitica_pomodoro_settings.json"))
check(QishiSceneStore.presets.count > 1, "bundled scene snapshot is available without fetching audio")
let manager = AudioManager.shared
let engine = PomodoroEngine.shared
engine.startPomodoro()
let first = manager.currentQishiSceneId
check(first != nil, "focus start chooses a scene")
let focusPlayers = AVPlayer.instances.filter { $0.currentItem != nil }
check(!focusPlayers.isEmpty && focusPlayers.allSatisfy { $0.rate > 0 }, "focus starts each scene track")
engine.freeze()
check(focusPlayers.allSatisfy { $0.rate == 0 }, "pause stops every focus track")
if let item = focusPlayers.first?.currentItem {
    NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
}
check(focusPlayers.allSatisfy { $0.rate == 0 }, "late loop notification cannot restart paused focus audio")
engine.unfreeze()
check(manager.currentQishiSceneId == first, "resume keeps the same focus scene")
check(focusPlayers.allSatisfy { $0.currentItem != nil && $0.rate > 0 }, "resume reuses paused focus players")
var foregroundRecovered = false
engine.resyncAfterForeground { foregroundRecovered = true }
let foregroundTimeout = Date().addingTimeInterval(8)
while !foregroundRecovered && Date() < foregroundTimeout {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
check(foregroundRecovered && manager.currentQishiSceneId == first && AVPlayer.instances.filter { $0.currentItem != nil }.count == focusPlayers.count, "foreground resync does not randomize or duplicate players")
engine.reset()
check(manager.currentQishiSceneId == nil && focusPlayers.allSatisfy { $0.currentItem == nil && $0.rate == 0 }, "reset releases players and clears active scene")
engine.startPomodoro()
check(manager.currentQishiSceneId != first, "next focus session avoids previous scene")
let second = manager.currentQishiSceneId
let secondPlayers = AVPlayer.instances.filter { $0.currentItem != nil }
let secondIdentities = Set(secondPlayers.map(ObjectIdentifier.init))
let previewPreset = QishiSceneStore.presets.first { $0.id == first }!
manager.playQishiPreview(previewPreset, volume: 0.2)
let previewPlayers = AVPlayer.instances.filter { $0.currentItem != nil && !secondIdentities.contains(ObjectIdentifier($0)) }
check(manager.currentQishiSceneId == second && manager.lastQishiSceneId == second, "preview never changes focus scene or cross-session history")
check(secondPlayers.allSatisfy { $0.currentItem != nil && $0.rate > 0 }, "preview never replaces ongoing focus players")
check(previewPlayers.count == previewPreset.tracks.count, "preview owns independent scene tracks")
check(zip(previewPlayers, previewPreset.tracks).allSatisfy { player, track in
    abs(player.volume - Float(track.volume) / 100 * 0.2) < 0.0001
}, "preview respects preset gain and user volume on every track")
manager.stopPreview()
check(previewPlayers.allSatisfy { $0.currentItem == nil && $0.rate == 0 }, "stop-preview releases only preview tracks")
check(manager.currentQishiSceneId == second && secondPlayers.allSatisfy { $0.rate > 0 }, "stop-preview leaves focus playback intact")
manager.playQishiPreview(previewPreset, volume: 0.2)
let nextPreview = AVPlayer.instances.filter { $0.currentItem != nil && !secondIdentities.contains(ObjectIdentifier($0)) }
engine.reset()
check(nextPreview.allSatisfy { $0.currentItem != nil && $0.rate > 0 }, "ending focus does not stop the independent preview")
engine.startPomodoro()
check(nextPreview.allSatisfy { $0.currentItem == nil && $0.rate == 0 }, "new focus session stops any outstanding preview")
engine.reset()

// The fake transport uses an existing resource URL as a token; it does not decode audio.
// The probe never copies MP3s or modifies its resources after Bundle caches their inventory.
SettingsManager.shared.settings.ambientSource = "custom"
SettingsManager.shared.settings.ambientSound = "qishi_presets.json"
engine.startPomodoro()
check(AVAudioPlayer.instances.last != nil, "custom transport receives the fixture resource URL")
let custom = AVAudioPlayer.instances.last!
custom.currentTime = 12
engine.freeze()
check(!custom.isPlaying && custom.currentTime == 12, "custom pause preserves playback position")
engine.unfreeze()
check(AVAudioPlayer.instances.last === custom && custom.isPlaying && custom.currentTime == 12, "custom resume reuses the paused track")
engine.reset()
check(!custom.isPlaying, "custom reset stops playback")

// F2: the item reaches EOF before pause, but its queued end notification
// arrives after pause. Reset the loop position without resuming paused audio.
SettingsManager.shared.settings.ambientSource = "qishi"
engine.startPomodoro()
let ended = AVPlayer.instances.first { $0.currentItem != nil }!
let endedItem = ended.currentItem!
ended.reachEnd()
ended.play()
check(ended.hasReachedEnd && ended.rate == 0, "EOF transport cannot restart with play alone")
engine.freeze()
let seeksBeforeEndNotification = ended.seekCalls
let playsBeforeEndNotification = ended.playCalls
NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: endedItem)
check(ended.seekCalls == seeksBeforeEndNotification + 1 && !ended.hasReachedEnd,
      "paused EOF notification resets the owned loop position")
check(ended.rate == 0 && ended.playCalls == playsBeforeEndNotification,
      "paused EOF loop reset never calls play")
engine.unfreeze()
check(ended.rate > 0 && ended.currentItem === endedItem,
      "resume after queued paused EOF reuses an audible-position player")
engine.reset()
let retiredSeeks = ended.seekCalls
NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: endedItem)
check(ended.seekCalls == retiredSeeks && ended.rate == 0,
      "retired EOF notification cannot seek or restart released players")
print("QISHI_AUDIO_SUITE PASS (transport stubs; no network or sound)")

// QISHI(c): pause/resume and the foreground-resync path CONTINUE the same
// scene — resume re-requests the SAME scene id and never re-randomizes.
// RED against gated sources: qishiScene / qishiLibraryLoader do not exist.
import com.habitica.pomodoro.data.QishiPreset
import com.habitica.pomodoro.data.QishiTrack
import com.habitica.pomodoro.engine.PomodoroViewModel

fun main() {
    val appDir = newTempDir("q1-03")
    seedSettings(appDir, connect = false)
    val vm = newVm(appDir)
    // >1 scene so any accidental re-randomize would be observable
    vm.qishiLibraryLoader = { (1..8).map { QishiPreset("scene-$it", "S$it", "", listOf(QishiTrack("t$it", "f$it.mp3", 30))) } }
    vm.updateSettings { it.copy(ambientSource = "qishi") }

    vm.startPomodoro()
    val chosen = vm.state.value.qishiScene
    expect(chosen != null, "scene selected at focus start")
    val id = chosen!!.id

    vm.pause()
    expect(!vm.state.value.isRunning, "paused")
    expectEq(vm.state.value.qishiScene?.id, id, "pause keeps the active scene for continuation")

    vm.resume()
    expect(vm.state.value.isRunning, "resumed")
    expectEq(vm.state.value.qishiScene?.id, id, "resume continues the SAME scene (no re-randomize)")

    // Foreground resync + timer-service re-attach must not re-randomize either.
    vm.resyncAfterForeground()
    expectEq(vm.state.value.qishiScene?.id, id, "foreground resync continues the same scene")
    vm.attachTimerService()
    expectEq(vm.state.value.qishiScene?.id, id, "timer-service attach continues the same scene")

    // Pin the state contract the service's refreshAudio consumes for playback.
    expect(vm.state.value.phase == PomodoroViewModel.Phase.POMODORO && vm.state.value.isRunning,
        "still a running pomodoro — refreshAudio keeps the same scene playing")
    println("Q1-03 OK")
}

// QISHI(b): focus start with ambientSource=="qishi" requests a scene from the
// VM-side selection logic; a newly started pomodoro avoids the previous
// pomodoro's scene when the library has >1 scene. Custom source never selects.
// RED against gated sources: qishiScene / qishiLibraryLoader do not exist.
import com.habitica.pomodoro.data.QishiPreset
import com.habitica.pomodoro.data.QishiTrack
import com.habitica.pomodoro.engine.PomodoroViewModel

private fun twoSceneLibrary() = listOf(
    QishiPreset("scene-a", "场景A", "", listOf(QishiTrack("ta", "a.mp3", 50))),
    QishiPreset("scene-b", "场景B", "", listOf(QishiTrack("tb", "b.mp3", 40))),
)

fun main() {
    val appDir = newTempDir("q1-02")
    seedSettings(appDir, connect = false)
    val vm = newVm(appDir)
    vm.qishiLibraryLoader = { twoSceneLibrary() }

    // custom (default): focus start selects no scene
    vm.startPomodoro()
    expectEq(vm.state.value.phase, PomodoroViewModel.Phase.POMODORO, "focus is running")
    expectEq(vm.state.value.qishiScene, null, "custom source selects no qishi scene")
    vm.stop()

    vm.updateSettings { it.copy(ambientSource = "qishi") }
    vm.startPomodoro()
    val first = vm.state.value.qishiScene
    expect(first != null, "qishi focus start selects a scene")
    expect(first!!.id in setOf("scene-a", "scene-b"), "scene comes from the library")

    // The anti-repeat memory survives stop: the next pomodoro must differ (library > 1).
    vm.stop()
    expectEq(vm.state.value.qishiScene, null, "stop clears the active scene")
    vm.startPomodoro()
    val second = vm.state.value.qishiScene
    expect(second != null, "second pomodoro selects a scene")
    expect(second!!.id != first.id, "new pomodoro avoids previous pomodoro's scene (was ${first.id}, got ${second.id})")

    // With a two-scene library the alternation is fully deterministic.
    vm.stop()
    vm.startPomodoro()
    expectEq(vm.state.value.qishiScene!!.id, first.id, "two-scene library alternates back")
    println("Q1-02 OK")
}

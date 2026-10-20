// QISHI(extra): an empty/unavailable scene library degrades loudly through the
// existing message-style state and selects no scene; the timer itself is
// unaffected. Mirrors Apple's "栖时场景库不可用" lastError path.
// RED against gated sources: qishiScene / qishiLibraryLoader do not exist.
import com.habitica.pomodoro.engine.PomodoroViewModel

fun main() {
    val appDir = newTempDir("q1-06")
    seedSettings(appDir, connect = false)
    val vm = newVm(appDir)
    vm.qishiLibraryLoader = { emptyList() }
    vm.updateSettings { it.copy(ambientSource = "qishi") }
    vm.startPomodoro()
    expectEq(vm.state.value.qishiScene, null, "empty library selects no scene")
    expect(vm.state.value.message?.contains("栖时场景库不可用") == true,
        "library failure surfaced via message state, was: ${vm.state.value.message}")
    expectEq(vm.state.value.phase, PomodoroViewModel.Phase.POMODORO, "timer still starts without a scene")
    expect(vm.state.value.isRunning, "timer runs without a scene")

    // Preview API over an empty library is safe.
    expectEq(vm.randomQishiPreviewScene(), null, "preview selection over an empty library is null")
    expectEq(vm.qishiSceneCount(), 0, "scene count over an empty library is 0")
    println("Q1-06 OK")
}

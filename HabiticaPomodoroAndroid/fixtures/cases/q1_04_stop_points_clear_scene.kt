// QISHI(d): every ambient-stop point clears the active scene: abandon/stop,
// skip-to-break, and the deadline-driven phase end (real production resync
// chain via a seeded expired timer). The anti-repeat memory survives clears.
// RED against gated sources: qishiScene / qishiLibraryLoader do not exist.
import com.habitica.pomodoro.data.QishiPreset
import com.habitica.pomodoro.data.QishiTrack
import com.habitica.pomodoro.engine.PomodoroViewModel
import org.json.JSONObject
import java.io.File

private fun library(n: Int) =
    (1..n).map { QishiPreset("scene-$it", "S$it", "", listOf(QishiTrack("t$it", "f$it.mp3", 30))) }

fun main() {
    // 1. abandon/stop clears the active scene.
    val appDir = newTempDir("q1-04")
    seedSettings(appDir, connect = false)
    val vm = newVm(appDir)
    vm.qishiLibraryLoader = { library(5) }
    vm.updateSettings { it.copy(ambientSource = "qishi") }
    vm.startPomodoro()
    val first = vm.state.value.qishiScene
    expect(first != null, "scene selected at focus start")
    vm.stop()
    expectEq(vm.state.value.qishiScene, null, "stop (abandon) clears the active scene")

    // 2. skip-to-break clears; skipping the break starts a fresh non-repeating scene.
    vm.startPomodoro()
    val second = vm.state.value.qishiScene
    expect(second != null && second.id != first!!.id, "second pomodoro avoids the previous scene")
    vm.skipToBreak()
    expectEq(vm.state.value.phase, PomodoroViewModel.Phase.BREAK, "moved to break")
    expectEq(vm.state.value.qishiScene, null, "skip-to-break clears the active scene")
    vm.skipBreak()
    val third = vm.state.value.qishiScene
    expect(third != null, "skipping the break starts a new pomodoro with a scene")
    expect(third!!.id != second!!.id, "post-break pomodoro avoids the previous scene")

    // 3. Deadline-driven phase end through the real production chain:
    //    seeded expired focus -> init loadAll -> restoreTimer -> resyncTimer -> onPomodoroEnds.
    val dir2 = newTempDir("q1-04b")
    val data = File(dir2, ".habitica-pomodoro").apply { mkdirs() }
    File(data, "habitica_pomodoro_settings.json").writeText(JSONObject().apply {
        put("connectHabitica", false); put("ambientSource", "qishi")
    }.toString())
    File(data, "habitica_pomodoro_timer.json").writeText(JSONObject().apply {
        put("phase", "POMODORO"); put("phaseID", "fixture-session")
        put("endsAt", System.currentTimeMillis() - 5_000); put("pausedRemaining", 0)
        put("totalSeconds", 1500); put("combo", 0); put("running", true)
        put("customBreak", false); put("completedSet", false)
        put("phaseSnapshot", JSONObject.NULL)
    }.toString())
    val vm2 = newVm(dir2)
    expect(vm2.state.value.phase != PomodoroViewModel.Phase.POMODORO,
        "deadline phase-end ran during restore (phase=${vm2.state.value.phase})")
    expectEq(vm2.state.value.qishiScene, null, "phase end leaves no active scene")
    println("Q1-04 OK")
}

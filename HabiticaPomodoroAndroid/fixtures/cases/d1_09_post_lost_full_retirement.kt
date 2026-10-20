// D1-09: full in-flight-deletion lifecycle with a healthy delete — POST
// succeeds, task already deleted locally, id enqueued with link, delete
// confirms via 404 read-back: every queue drains and the cloud todo is gone.
// No duplicate POST ever happens. (No error assertions here: the transient
// ambiguity message set mid-flight is cleared by FIX3 semantics on a later
// successful refresh, so asserting it would couple D1 to D4.)
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-09")
    seedSettings(dir)
    val today = logicalTodayKey()
    seedTopThree(dir, ownedStore())

    lateinit var vm: com.habitica.pomodoro.engine.PomodoroViewModel
    vm = newVm(dir) {
        HabiticaAPI.createOutcome = { _, _ ->
            vm.deleteTask(0, 0) // in-flight local delete
            HabiticaAPI.Result.Success("RID-9")
        }
    }
    vm.addTask(0, "t9")

    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, emptySet(), "queue drained after confirmed delete")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "link drained")
    expectEq(s.deletedCreateMarkers, emptySet(), "marker retired")
    expectEq(s.deletedCloudTaskOrigins, emptyMap(), "origins clean")
    expect(HabiticaAPI.calls.count { it == "createTodo:t9" } == 1, "exactly one POST")
    expect(HabiticaAPI.calls.any { it == "deleteTodo:RID-9" }, "delete executed")
    expect(HabiticaAPI.cloud.none { it.id == "RID-9" }, "cloud todo removed")
    expect(s.history[today]?.taskGroups?.flatten()?.none { it.habiticaTaskId == "RID-9" } == true,
        "lost create never resurrected into history")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCreateMarkers, emptySet(), "final state persisted")
    println("D1-09 OK")
}

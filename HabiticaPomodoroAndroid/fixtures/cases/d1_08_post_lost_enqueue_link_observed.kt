// D1-08: POST succeeded but the task was deleted locally while the create was
// in flight. The binding branch must enqueue the fresh remote id WITH its
// id->marker link (not just the queue entry). Here the delete stays
// unconfirmed, so the linked record remains observable on disk.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-08")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nt8"
    seedTopThree(dir, ownedStore())

    lateinit var vm: com.habitica.pomodoro.engine.PomodoroViewModel
    vm = newVm(dir) {
        HabiticaAPI.deleteRemovesFromCloud = false // read-back still sees the todo
        HabiticaAPI.createOutcome = { _, _ ->
            // Simulate the user deleting the task while the POST is in flight.
            vm.deleteTask(0, 0)
            HabiticaAPI.Result.Success("RID-8")
        }
    }
    vm.addTask(0, "t8")

    val s = vm.state.value.store
    expect(s.history[today]?.taskGroups?.get(0)?.none { it.title == "t8" } == true, "task deleted locally")
    expectEq(s.deletedCloudIds, setOf("RID-8"), "in-flight create result enqueued")
    expectEq(s.deletedCloudIdMarkers, mapOf("RID-8" to marker), "link persisted at enqueue (D1)")
    expectEq(s.deletedCreateMarkers, setOf(marker), "marker still pending while delete unconfirmed")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCloudIdMarkers, mapOf("RID-8" to marker), "link on disk")
    expect(HabiticaAPI.calls.count { it == "createTodo:t8" } == 1, "exactly one POST")
    expect(HabiticaAPI.calls.any { it == "deleteTodo:RID-8" }, "delete attempted for the lost create")
    println("D1-08 OK")
}

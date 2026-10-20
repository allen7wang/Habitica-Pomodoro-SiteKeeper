// D1-11: quarantine exemption — a matching-signature inbound todo whose id is
// ALREADY bound to a local task is known, not an unresolved creation; it must
// merge normally without any conflict error.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-11")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nbound"
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-11", title = "bound", remoteId = "RID-11"))))).copy(
        deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) { HabiticaAPI.cloud += cloudTodo("RID-11", "bound") }

    val s = vm.state.value.store
    val task = s.history.getValue(today).taskGroups[0].single { it.id == "LOCAL-11" }
    expectEq(task.habiticaTaskId, "RID-11", "known binding untouched")
    expectEq(vm.state.value.topThreeSyncError, null, "no quarantine conflict for a known id")
    expectEq(s.deletedCreateMarkers, setOf(marker), "unrelated marker retained")
    println("D1-11 OK")
}

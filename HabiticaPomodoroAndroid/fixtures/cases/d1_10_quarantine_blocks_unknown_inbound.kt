// D1-10: quarantine — an inbound cloud todo whose dated notes match a pending
// create marker and whose id is UNKNOWN locally must not be imported or bound;
// the refresh reports the quarantine conflict instead.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-10")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nghost"
    seedTopThree(dir, ownedStore().copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) { HabiticaAPI.cloud += cloudTodo("RID-10", "ghost") }

    val s = vm.state.value.store
    expect(s.history.values.flatMap { it.taskGroups.flatten() }.none { it.habiticaTaskId == "RID-10" },
        "quarantined todo not imported")
    expectEq(s.deletedCreateMarkers, setOf(marker), "marker retained")
    expect(vm.state.value.topThreeSyncError?.contains("已隔离") == true,
        "quarantine conflict reported, was: ${vm.state.value.topThreeSyncError}")
    println("D1-10 OK")
}

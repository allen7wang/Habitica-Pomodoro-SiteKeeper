// FIX1(P0): after the confirmed cleanup, quarantine no longer blocks inbound
// todos with the same signature — the next refresh imports them normally.
// (No error-text assertions: stale-error clearing is FIX3's contract.)
// RED against gated sources: clearQuarantinedCreateMarkers() does not exist.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("fix1-03")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nghost"
    seedTopThree(dir, ownedStore().copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) { HabiticaAPI.cloud += cloudTodo("RID-G", "ghost") }
    expect(vm.state.value.store.history.values.flatMap { it.taskGroups.flatten() }
        .none { it.habiticaTaskId == "RID-G" }, "precondition: quarantined, not imported")

    vm.clearQuarantinedCreateMarkers()
    expectEq(vm.state.value.store.deletedCreateMarkers, emptySet(), "markers cleared")

    vm.refreshTopThreeFromCloud()
    val imported = vm.state.value.store.history.getValue(today).taskGroups[0]
        .singleOrNull { it.habiticaTaskId == "RID-G" }
    expect(imported != null, "same-signature todo imports after confirmed cleanup")
    expectEq(imported?.title, "ghost", "imported with its cloud title")
    expectEq(imported?.cloudAccount, OWNER_KEY, "imported into the current partition")
    println("FIX1-03 OK")
}

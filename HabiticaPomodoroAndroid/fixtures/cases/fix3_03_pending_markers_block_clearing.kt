// FIX3 guard: an unresolved create marker (ambiguous-marker condition) keeps
// the error displayed across an otherwise clean successful refresh — clearing
// would hide a still-active quarantine condition.
// Green before and after the fix.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("fix3-03")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\npending-forever"
    seedTopThree(dir, ownedStore().copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) // empty cloud: init refresh is clean
    expectEq(vm.state.value.topThreeSyncError, null, "precondition: no error yet")

    HabiticaAPI.fetchFailure = "网络连接失败，请检查网络或服务器"
    vm.refreshTopThreeFromCloud()
    expect(vm.state.value.topThreeSyncError != null, "precondition: stale error set")

    HabiticaAPI.fetchFailure = null
    vm.refreshTopThreeFromCloud() // clean success, but the marker is still pending
    expect(vm.state.value.topThreeSyncError != null,
        "marker still pending -> stale error must NOT be cleared")
    expectEq(vm.state.value.store.deletedCreateMarkers, setOf(marker), "marker still queued")
    println("FIX3-03 OK")
}

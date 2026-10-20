// FIX3 guard: while delete protection is active (a queued remote id is still
// bound to an active local task), a successful refresh must not clear the
// protection error. Green before and after the fix.
import com.habitica.pomodoro.data.HabiticaAPI

fun main() {
    val dir = newTempDir("fix3-04")
    seedSettings(dir)
    val today = logicalTodayKey()
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-P", title = "tp", remoteId = "RID-P"))))).copy(
        deletedCloudIds = setOf("RID-P")))

    val vm = newVm(dir)
    vm.retryPendingTasks()
    expect(vm.state.value.topThreeSyncError?.contains("删除保护") == true,
        "precondition: protection error set, was: ${vm.state.value.topThreeSyncError}")

    HabiticaAPI.fetchFailure = null
    vm.refreshTopThreeFromCloud() // clean success, protection still active
    expect(vm.state.value.topThreeSyncError?.contains("删除保护") == true,
        "protection error must survive while the condition is active, was: ${vm.state.value.topThreeSyncError}")
    expectEq(vm.state.value.store.deletedCloudIds, setOf("RID-P"), "queue retained")
    println("FIX3-04 OK")
}

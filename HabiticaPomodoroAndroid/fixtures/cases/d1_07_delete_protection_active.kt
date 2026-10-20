// D1-07: delete protection — a queued remote id still bound to an ACTIVE
// (non-archive) local task must never be deleted; the protection error is set
// and the queue entry stays for human review.
import com.habitica.pomodoro.data.HabiticaAPI

fun main() {
    val dir = newTempDir("d1-07")
    seedSettings(dir)
    val today = logicalTodayKey()
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-7", title = "t7", remoteId = "RID-7"))))).copy(
        deletedCloudIds = setOf("RID-7")))

    val vm = newVm(dir)
    vm.retryPendingTasks()

    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, setOf("RID-7"), "queue retained for human review")
    expect(vm.state.value.topThreeSyncError?.contains("待删除 ID 已绑定本地任务") == true,
        "delete protection reported, was: ${vm.state.value.topThreeSyncError}")
    expect(HabiticaAPI.calls.none { it == "deleteTodo:RID-7" }, "protected id never sent to DELETE")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCloudIds, setOf("RID-7"), "protection persisted")
    println("D1-07 OK")
}

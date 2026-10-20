// D1-06: archive-copy exemption — the queued remote id may still be bound to
// the ORIGINAL local UUID as a movedToToday archive copy; that is not an active
// binding, delete protection must not fire and the delete proceeds.
import com.habitica.pomodoro.data.HabiticaAPI

fun main() {
    val dir = newTempDir("d1-06")
    seedSettings(dir)
    val today = logicalTodayKey()
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-6", title = "t6", remoteId = "RID-6", movedToToday = true))))).copy(
        deletedCloudIds = setOf("RID-6"),
        deletedCloudTaskOrigins = mapOf("RID-6" to "LOCAL-6")))

    val vm = newVm(dir)
    vm.retryPendingTasks()

    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, emptySet(), "queue drained: archive copy did not block deletion")
    expectEq(s.deletedCloudTaskOrigins, emptyMap(), "origin drained")
    expect(vm.state.value.topThreeSyncError?.contains("删除保护") != true,
        "protection must not fire for the archive copy, was: ${vm.state.value.topThreeSyncError}")
    expect(HabiticaAPI.calls.any { it == "deleteTodo:RID-6" }, "delete executed despite archive binding")
    println("D1-06 OK")
}

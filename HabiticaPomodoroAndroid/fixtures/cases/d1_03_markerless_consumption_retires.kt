// D1-03 (core): a restart retry consumes the queue entry WITHOUT a marker
// (retryPendingTasks -> deleteCloudTask(id), marker == null). The id->marker
// link must retire the orphaned marker in the SAME atomic save, together with
// queue, origin and link. Pre-D1 this left the marker orphaned forever.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-03")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nt3"
    seedTopThree(dir, ownedStore().copy(
        deletedCloudIds = setOf("RID-3"),
        deletedCloudTaskOrigins = mapOf("RID-3" to "LOCAL-3"),
        deletedCloudIdMarkers = mapOf("RID-3" to marker),
        deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) // healthy delete stub: success -> read-back 404
    vm.retryPendingTasks() // marker-less consumption path

    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, emptySet(), "queue drained")
    expectEq(s.deletedCloudTaskOrigins, emptyMap(), "origin drained")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "link drained")
    expectEq(s.deletedCreateMarkers, emptySet(), "marker retired via link in the same save (D1)")
    expectEq(vm.state.value.topThreeSyncError, null, "clean end state, no error")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCreateMarkers, emptySet(), "marker retirement persisted")
    expectEq(disk.deletedCloudIds, emptySet(), "queue drain persisted")
    expect(HabiticaAPI.calls.any { it == "deleteTodo:RID-3" }, "delete executed")
    expect(HabiticaAPI.calls.any { it == "fetchTodo:RID-3" }, "read-back executed")
    println("D1-03 OK")
}

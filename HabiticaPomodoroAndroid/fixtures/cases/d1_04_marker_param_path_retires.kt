// D1-04: the explicit-marker consumption path — retryDeletedCreations resolves
// the unique match and passes the marker straight to deleteCloudTask; a healthy
// delete + 404 read-back retires marker, link and queue entry completely.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-04")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nt4"
    seedTopThree(dir, ownedStore().copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) { HabiticaAPI.cloud += cloudTodo("RID-4", "t4") }
    vm.retryPendingTasks()

    val s = vm.state.value.store
    expectEq(s.deletedCreateMarkers, emptySet(), "marker retired via explicit marker param")
    expectEq(s.deletedCloudIds, emptySet(), "queue drained")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "link drained")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCreateMarkers, emptySet(), "retirement persisted")
    expect(HabiticaAPI.calls.count { it == "createTodo:t4" } == 0, "never re-creates a deleted task")
    println("D1-04 OK")
}

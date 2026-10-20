// D1-17: user-visible recovery loop — a transient delete failure leaves the
// id enqueued WITH its link (phase A); the next retryPendingTasks with a
// healthy network consumes the queue entry marker-lessly and retires marker,
// link, queue and origin completely (phase B).
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-17")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nt17"
    seedTopThree(dir, ownedStore().copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) {
        HabiticaAPI.cloud += cloudTodo("RID-17", "t17")
        HabiticaAPI.deleteOutcome = { HabiticaAPI.Result.Error("网络连接失败，请检查网络或服务器") }
    }

    // Phase A: transient failure — everything stays queued, link recorded.
    vm.retryPendingTasks()
    var s = vm.state.value.store
    expectEq(s.deletedCloudIds, setOf("RID-17"), "phase A: queued")
    expectEq(s.deletedCloudIdMarkers, mapOf("RID-17" to marker), "phase A: linked")
    expectEq(s.deletedCreateMarkers, setOf(marker), "phase A: marker pending")

    // Phase B: network recovers; plain queue consumption retires the marker.
    HabiticaAPI.deleteOutcome = { HabiticaAPI.Result.Success(true) }
    vm.retryPendingTasks()
    s = vm.state.value.store
    expectEq(s.deletedCloudIds, emptySet(), "phase B: queue drained")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "phase B: link drained")
    expectEq(s.deletedCreateMarkers, emptySet(), "phase B: marker retired via link")
    expect(HabiticaAPI.cloud.none { it.id == "RID-17" }, "phase B: cloud todo gone")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCreateMarkers, emptySet(), "phase B persisted")
    expectEq(disk.deletedCloudIds, emptySet(), "phase B queue drain persisted")
    println("D1-17 OK")
}

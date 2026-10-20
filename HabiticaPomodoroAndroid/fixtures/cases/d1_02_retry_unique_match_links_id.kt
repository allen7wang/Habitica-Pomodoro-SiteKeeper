// D1-02: retryDeletedCreations finds a UNIQUE cloud match -> the remote id is
// enqueued AND the id->marker link is persisted in the same save (the D1 fix),
// so a later marker-less consumption can still retire the marker. A failing
// delete keeps everything queued for retry.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-02")
    seedSettings(dir)
    val today = logicalTodayKey()
    val notes = topThreeNotes("Work", today)
    val marker = "$notes\nt2"
    seedTopThree(dir, ownedStore(history = emptyMap()).copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) {
        HabiticaAPI.cloud += cloudTodo("RID-2", "t2")
        HabiticaAPI.deleteOutcome = { HabiticaAPI.Result.Error("Habitica 请求失败 (HTTP 500)", 500) }
    }
    vm.retryPendingTasks()

    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, setOf("RID-2"), "unique match enqueued")
    expectEq(s.deletedCloudIdMarkers, mapOf("RID-2" to marker), "id->marker link persisted at enqueue (D1)")
    expectEq(s.deletedCreateMarkers, setOf(marker), "marker still pending while delete unconfirmed")
    expect(vm.state.value.topThreeSyncError?.contains("远端删除尚未确认") == true,
        "unconfirmed delete reported, was: ${vm.state.value.topThreeSyncError}")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCloudIdMarkers, mapOf("RID-2" to marker), "link on disk")
    expectEq(disk.deletedCloudIds, setOf("RID-2"), "queue on disk")
    expect(HabiticaAPI.calls.any { it == "deleteTodo:RID-2" }, "delete attempted")
    println("D1-02 OK")
}

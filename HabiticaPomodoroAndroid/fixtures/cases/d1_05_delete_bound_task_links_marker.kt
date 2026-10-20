// D1-05: deleteTask on a task carrying BOTH a remote id and pendingCreate
// fields records the tombstone (queue + origin) AND the id->marker link in the
// same persist, so any consumption path can retire the marker. A failing
// delete keeps the full record for retry.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-05")
    seedSettings(dir)
    val today = logicalTodayKey()
    val notes = topThreeNotes("Work", today)
    val marker = "$notes\nt5"
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-5", title = "t5", remoteId = "RID-5", pendingTitle = "t5", pendingNotes = notes))))))

    val vm = newVm(dir) {
        // The todo must stay VISIBLE in the substitute cloud: a failing DELETE
        // whose read-back 404s is (correctly) treated as "gone" and retires the
        // queue entry. Phase A needs an unconfirmed delete, not a vanished todo.
        HabiticaAPI.cloud += cloudTodo("RID-5", "t5")
        HabiticaAPI.deleteOutcome = { HabiticaAPI.Result.Error("Habitica 请求失败 (HTTP 500)", 500) }
    }
    vm.deleteTask(0, 0)

    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, setOf("RID-5"), "tombstone queued")
    expectEq(s.deletedCloudTaskOrigins, mapOf("RID-5" to "LOCAL-5"), "origin recorded")
    expectEq(s.deletedCloudIdMarkers, mapOf("RID-5" to marker), "deleteTask links id->marker (D1)")
    expectEq(s.deletedCreateMarkers, setOf(marker), "marker queued")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCloudIdMarkers, mapOf("RID-5" to marker), "link persisted atomically with tombstone")
    expect(vm.state.value.topThreeSyncError?.contains("远端删除尚未确认") == true,
        "unconfirmed delete reported, was: ${vm.state.value.topThreeSyncError}")
    println("D1-05 OK")
}

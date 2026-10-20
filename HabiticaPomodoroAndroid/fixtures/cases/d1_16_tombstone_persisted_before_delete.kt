// D1-16: the delete tombstone (queue + origin) is PERSISTED BEFORE the network
// delete is attempted, so a crash mid-delete can never resurrect the todo from
// an inbound refresh. Observed from inside the substitute delete call.
import com.habitica.pomodoro.data.HabiticaAPI

fun main() {
    val dir = newTempDir("d1-16")
    seedSettings(dir)
    val today = logicalTodayKey()
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-16", title = "t16", remoteId = "RID-16"))))))

    var tombstoneSeenAtDeleteTime = false
    val vm = newVm(dir) {
        HabiticaAPI.deleteOutcome = { id ->
            if (id == "RID-16") {
                val diskNow = readTopThreeDisk(dir)
                tombstoneSeenAtDeleteTime = "RID-16" in diskNow.deletedCloudIds &&
                    diskNow.deletedCloudTaskOrigins["RID-16"] == "LOCAL-16"
            }
            HabiticaAPI.Result.Success(true)
        }
    }
    vm.deleteTask(0, 0)

    expect(tombstoneSeenAtDeleteTime, "tombstone was on disk BEFORE the delete call")
    val s = vm.state.value.store
    expectEq(s.deletedCloudIds, emptySet(), "queue drained after confirmed delete")
    expectEq(s.deletedCloudTaskOrigins, emptyMap(), "origin drained")
    expect(s.history[today]?.taskGroups?.get(0)?.isEmpty() == true, "task removed locally")
    expectEq(readTopThreeDisk(dir).deletedCloudIds, emptySet(), "drain persisted")
    println("D1-16 OK")
}

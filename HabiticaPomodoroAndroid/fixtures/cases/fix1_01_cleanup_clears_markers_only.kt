// FIX1(P0): the user-confirmed cleanup entry clears deletedCreateMarkers AND
// deletedCloudIdMarkers for the CURRENT owner partition, persists via the
// normal store save, and refreshes the state counts the settings UI shows.
// HARD INVARIANT: deletedCloudIds / deletedCloudTaskOrigins / history / other
// owners' partitions are never touched.
// RED against gated sources: clearQuarantinedCreateMarkers() does not exist.
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("fix1-01")
    seedSettings(dir)
    val today = logicalTodayKey()
    val m1 = "${topThreeNotes("Work", today)}\norphan1"
    val m2 = "${topThreeNotes("MyOwn", today)}\norphan2"
    val seeded = ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-K", title = "keep me", remoteId = "RID-K"))))).copy(
        deletedCloudIds = setOf("RID-Q"),
        deletedCloudTaskOrigins = mapOf("RID-Q" to "LOCAL-Q"),
        deletedCreateMarkers = setOf(m1, m2),
        deletedCloudIdMarkers = mapOf("RID-Q" to m1))
    seedTopThree(dir, seeded)

    val vm = newVm(dir)
    // counts the settings entry displays come straight from the state store
    expectEq(vm.state.value.store.deletedCreateMarkers.size, 2, "marker count before cleanup")
    expectEq(vm.state.value.store.deletedCloudIds.size, 1, "queue count before cleanup")

    vm.clearQuarantinedCreateMarkers()

    val s = vm.state.value.store
    expectEq(s.deletedCreateMarkers.size, 0, "marker count refreshed after cleanup")
    expectEq(s.deletedCreateMarkers, emptySet(), "quarantine markers cleared")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "id->marker links cleared")
    expectEq(s.deletedCloudIds, setOf("RID-Q"), "SACRED: explicit delete queue untouched")
    expectEq(s.deletedCloudTaskOrigins, mapOf("RID-Q" to "LOCAL-Q"), "SACRED: origins untouched")
    expectEq(s.history, seeded.history, "history untouched")

    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCreateMarkers, emptySet(), "cleanup persisted")
    expectEq(disk.deletedCloudIdMarkers, emptyMap(), "link cleanup persisted")
    expectEq(disk.deletedCloudIds, setOf("RID-Q"), "queue persisted untouched")
    expectEq(disk.deletedCloudTaskOrigins, mapOf("RID-Q" to "LOCAL-Q"), "origins persisted untouched")
    println("FIX1-01 OK")
}

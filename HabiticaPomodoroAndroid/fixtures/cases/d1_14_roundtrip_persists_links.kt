// D1-14: persistence fidelity — all four deletion bookkeeping collections
// (queue, origins, markers, id->marker links) plus other owners' partitions in
// accountStores survive toJson/fromJson AND a full VM load+re-save cycle.
import com.habitica.pomodoro.data.TopThreeStore
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val today = logicalTodayKey()
    val markerA = "${topThreeNotes("Work", today)}\nma"
    val markerB = "${topThreeNotes("MyOwn", today)}\nmb"
    val seeded = ownedStore().copy(
        deletedCloudIds = setOf("RID-14"),
        deletedCloudTaskOrigins = mapOf("RID-14" to "LOCAL-14"),
        deletedCreateMarkers = setOf(markerA),
        deletedCloudIdMarkers = mapOf("RID-14" to markerA),
        accountStores = mapOf(OTHER_OWNER_KEY to ownedStore(OTHER_OWNER_KEY).copy(
            deletedCreateMarkers = setOf(markerB))))

    // pure round-trip
    expectEq(TopThreeStore.fromJson(seeded.toJson()), seeded, "JSON round-trip is lossless")

    // through the real LocalStore + VM lifecycle
    val dir = newTempDir("d1-14")
    seedSettings(dir)
    seedTopThree(dir, seeded)
    val vm = newVm(dir)
    expectEq(vm.state.value.store, seeded, "VM loads every collection intact")
    expectEq(readTopThreeDisk(dir), seeded, "VM re-save keeps every collection intact")
    println("D1-14 OK")
}

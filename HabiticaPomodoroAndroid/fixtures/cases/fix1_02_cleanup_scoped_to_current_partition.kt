// FIX1(P0): cleanup is scoped to the CURRENT owner partition — another owner's
// parked partition inside accountStores keeps its markers, links and queue.
// RED against gated sources: clearQuarantinedCreateMarkers() does not exist.
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("fix1-02")
    seedSettings(dir)
    val today = logicalTodayKey()
    val mA = "${topThreeNotes("Work", today)}\norphanA"
    val mB = "${topThreeNotes("Work", today)}\norphanB"
    val partitionB = ownedStore(OTHER_OWNER_KEY).copy(
        deletedCreateMarkers = setOf(mB),
        deletedCloudIdMarkers = mapOf("RID-B" to mB),
        deletedCloudIds = setOf("RID-B"),
        deletedCloudTaskOrigins = mapOf("RID-B" to "LOCAL-B"))
    seedTopThree(dir, ownedStore().copy(
        deletedCreateMarkers = setOf(mA),
        deletedCloudIdMarkers = mapOf("RID-A" to mA),
        deletedCloudIds = setOf("RID-A"),
        accountStores = mapOf(OTHER_OWNER_KEY to partitionB)))

    val vm = newVm(dir)
    vm.clearQuarantinedCreateMarkers()

    val s = vm.state.value.store
    expectEq(s.deletedCreateMarkers, emptySet(), "current partition markers cleared")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "current partition links cleared")
    expectEq(s.deletedCloudIds, setOf("RID-A"), "current queue untouched")
    val b = s.accountStores.getValue(OTHER_OWNER_KEY)
    expectEq(b.deletedCreateMarkers, setOf(mB), "other owner's markers untouched")
    expectEq(b.deletedCloudIdMarkers, mapOf("RID-B" to mB), "other owner's links untouched")
    expectEq(b.deletedCloudIds, setOf("RID-B"), "other owner's queue untouched")
    expectEq(b.deletedCloudTaskOrigins, mapOf("RID-B" to "LOCAL-B"), "other owner's origins untouched")

    val diskB = readTopThreeDisk(dir).accountStores.getValue(OTHER_OWNER_KEY)
    expectEq(diskB.deletedCreateMarkers, setOf(mB), "other owner's partition persisted untouched")
    println("FIX1-02 OK")
}

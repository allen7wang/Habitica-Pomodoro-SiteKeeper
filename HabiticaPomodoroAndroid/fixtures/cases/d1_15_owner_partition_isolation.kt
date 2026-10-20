// D1-15: owner partition isolation — switching accounts moves the current
// partition into accountStores and loads the target's OWN queues/markers;
// nothing leaks across partitions in either direction. (This is the invariant
// FIX1's cleanup must respect.)
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val today = logicalTodayKey()
    val markerA = "${topThreeNotes("Work", today)}\nma"
    val markerB = "${topThreeNotes("MyOwn", today)}\nmb"
    val partitionB = ownedStore(OTHER_OWNER_KEY).copy(
        deletedCreateMarkers = setOf(markerB), deletedCloudIds = setOf("RID-B"))
    val storeA = ownedStore(OWNER_KEY, history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-A", title = "ta"))))).copy(
        deletedCreateMarkers = setOf(markerA), deletedCloudIds = setOf("RID-A"),
        accountStores = mapOf(OTHER_OWNER_KEY to partitionB))

    expectEq(storeA.forAccount(OWNER_KEY), storeA, "current owner is a no-op")

    val switched = storeA.forAccount(OTHER_OWNER_KEY)
    expectEq(switched.cloudAccount, OTHER_OWNER_KEY, "switched to B")
    expectEq(switched.deletedCreateMarkers, setOf(markerB), "B sees only its own markers")
    expectEq(switched.deletedCloudIds, setOf("RID-B"), "B sees only its own queue")
    val savedA = switched.accountStores.getValue(OWNER_KEY)
    expectEq(savedA.deletedCreateMarkers, setOf(markerA), "A's markers preserved while parked")
    expectEq(savedA.deletedCloudIds, setOf("RID-A"), "A's queue preserved while parked")

    val back = switched.forAccount(OWNER_KEY)
    expectEq(back.deletedCreateMarkers, setOf(markerA), "A restored")
    expectEq(back.deletedCloudIds, setOf("RID-A"), "A queue restored")
    expectEq(back.accountStores.getValue(OTHER_OWNER_KEY).deletedCreateMarkers, setOf(markerB),
        "B parked intact")
    println("D1-15 OK")
}

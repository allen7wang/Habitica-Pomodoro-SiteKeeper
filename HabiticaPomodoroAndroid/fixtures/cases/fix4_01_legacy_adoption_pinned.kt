// FIX4(D3) characterization pin: first owner initialization of a LEGACY store
// (no cloudAccount/ownerInitialized keys, bare string queues) adopts the
// pre-existing deletedCloudIds/origins wholesale and stamps null-owner task
// rows. Evaluated decision (see comment in Models.kt forAccount): legacy rows
// carry no ownership evidence to filter by; server-side auth bounds the risk;
// adoption preserves single-account legacy users' delete intents.
// Green before and after the comment-only change.
import org.json.JSONArray
import org.json.JSONObject

fun main() {
    val dir = newTempDir("fix4-01")
    seedSettings(dir)
    val today = logicalTodayKey()

    // Raw legacy JSON exactly as an old app version would have written it.
    val legacy = JSONObject().apply {
        put("categoryNames", JSONArray(listOf("Work", "MyOwn", "Chores")))
        put("history", JSONObject().apply {
            put(today, dayWith(today, 0, listOf(
                ownedTask(id = "LOC-LEG", title = "legacy", remoteId = "LEG-1", owner = null))).toJson())
        })
        put("deletedCloudIds", JSONArray(listOf("LEG-1", "LEG-2")))
        put("deletedCloudTaskOrigins", JSONObject().apply { put("LEG-1", "LOC-LEG") })
    }
    dataDir(dir).mkdirs()
    java.io.File(dataDir(dir), "habitica_pomodoro_top_three.json").writeText(legacy.toString())

    val vm = newVm(dir)
    val s = vm.state.value.store
    expectEq(s.cloudAccount, OWNER_KEY, "legacy store claimed by first owner")
    expect(s.ownerInitialized, "owner initialization recorded")
    expectEq(s.deletedCloudIds, setOf("LEG-1", "LEG-2"), "legacy queue adopted wholesale (documented decision)")
    expectEq(s.deletedCloudTaskOrigins, mapOf("LEG-1" to "LOC-LEG"), "legacy origins adopted")
    val task = s.history.getValue(today).taskGroups[0].single { it.id == "LOC-LEG" }
    expectEq(task.cloudAccount, OWNER_KEY, "null-owner task rows stamped")
    expectEq(task.habiticaTaskId, "LEG-1", "task binding preserved")

    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCloudIds, s.deletedCloudIds, "adoption persisted")
    expectEq(disk.cloudAccount, OWNER_KEY, "owner persisted")
    println("FIX4-01 OK")
}

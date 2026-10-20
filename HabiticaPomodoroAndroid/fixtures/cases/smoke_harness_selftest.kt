// Harness self-test: the plumbing itself (stubs, seeding, VM construction,
// persistence round-trip, substitute API scriptability). Not a D1/FIX case.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.TopThreeStore

fun main() {
    val dir = newTempDir("smoke")
    seedSettings(dir)
    val today = logicalTodayKey()
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-SMOKE", title = "smoke task", remoteId = "RID-SMOKE"))))))

    val vm = newVm(dir) { HabiticaAPI.cloud += cloudTodo("RID-SMOKE", "smoke task") }

    val state = vm.state.value
    expectEq(state.store.cloudAccount, OWNER_KEY, "owner partition active")
    expect(state.store.ownerInitialized, "owner initialized")
    val task = state.store.history.getValue(today).taskGroups[0].single()
    expectEq(task.id, "LOCAL-SMOKE", "seeded task survives init")
    expectEq(task.habiticaTaskId, "RID-SMOKE", "seeded remote id survives init")

    // substitute API answered the init fetch; nothing else touched the "network"
    expect("fetchTopThreeTodos" in HabiticaAPI.calls, "substitute API was used")

    // persistence round-trip through the REAL LocalStore + REAL org.json
    val disk = readTopThreeDisk(dir)
    expectEq(disk.history.getValue(today).taskGroups[0].single().id, "LOCAL-SMOKE", "disk round-trip")
    expectEq(TopThreeStore.fromJson(disk.toJson()), disk, "store JSON is stable")

    println("SMOKE OK")
}

// D1-01: Deleting a lost-creation task (no remote id, pendingCreate fields set)
// queues ONLY the marker — no id can be linked yet — and the immediate retry
// with an invisible cloud match reports the protected-ambiguity error.
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("d1-01")
    seedSettings(dir)
    val today = logicalTodayKey()
    val notes = topThreeNotes("Work", today)
    val marker = "$notes\nt1"
    seedTopThree(dir, ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-1", title = "t1", pendingTitle = "t1", pendingNotes = notes))))))

    val vm = newVm(dir)
    vm.deleteTask(0, 0)

    val s = vm.state.value.store
    expectEq(s.deletedCreateMarkers, setOf(marker), "marker queued")
    expectEq(s.deletedCloudIds, emptySet(), "no remote id existed, queue untouched")
    expectEq(s.deletedCloudIdMarkers, emptyMap(), "no id to link yet")
    expectEq(s.deletedCloudTaskOrigins, emptyMap(), "no origin recorded")
    expect(s.history[today]?.taskGroups?.get(0)?.none { it.id == "LOCAL-1" } == true, "task removed locally")
    expect(vm.state.value.topThreeSyncError?.contains("云端匹配不唯一或尚不可见") == true,
        "invisible match reports protected ambiguity, was: ${vm.state.value.topThreeSyncError}")
    val disk = readTopThreeDisk(dir)
    expectEq(disk.deletedCreateMarkers, setOf(marker), "marker persisted")
    println("D1-01 OK")
}

// FIX2(P1/D2): once writes succeed again, the persistence error clears on the
// next successful save — it is a live status, not a permanent scar.
// RED against gated sources: UiState.persistenceError does not exist.
fun main() {
    val dir = newTempDir("fix2-02")
    val blocker = java.io.File(dir, ".habitica-pomodoro")
    blocker.writeText("blocker")

    val vm = newVm(dir)
    expect(vm.state.value.persistenceError != null, "failure visible while blocked")

    vm.addTask(0, "lost-while-blocked")
    expect(vm.state.value.persistenceError != null, "still failing while blocked")

    // Repair the storage, then trigger a normal save.
    expect(blocker.delete(), "blocker removed")
    expect(dir.resolve(".habitica-pomodoro").mkdirs(), "data dir restored")
    vm.addTask(0, "saved-after-repair")

    expectEq(vm.state.value.persistenceError, null, "successful save clears the persistence error")
    val disk = readTopThreeDisk(dir)
    val titles = disk.history.values.flatMap { it.taskGroups.flatten() }.map { it.title }
    expect("saved-after-repair" in titles, "post-repair task persisted")
    expect("lost-while-blocked" in titles, "the whole in-memory store persists on the next save")
    println("FIX2-02 OK")
}

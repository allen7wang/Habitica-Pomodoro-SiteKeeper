// FIX2(P1/D2): LocalStore write failures must become user-visible. With the
// data folder blocked (a regular FILE where .habitica-pomodoro should be),
// every store save fails: the VM must surface a persistence error while the
// in-memory state stays advanced (existing semantics).
// RED against gated sources: UiState.persistenceError does not exist.
fun main() {
    val dir = newTempDir("fix2-01")
    // Block the data dir: LocalStore's mkdirs is skipped because "it exists".
    java.io.File(dir, ".habitica-pomodoro").writeText("blocker")

    val vm = newVm(dir) // no settings: defaults, credentials absent
    expect(vm.state.value.persistenceError != null,
        "init store save failure must be visible")
    expect(vm.state.value.persistenceError!!.contains("写入失败"),
        "persistence error mentions 写入失败, was: ${vm.state.value.persistenceError}")

    vm.addTask(0, "t-fix2")
    val s = vm.state.value
    expect(s.store.history.values.flatMap { it.taskGroups.flatten() }.any { it.title == "t-fix2" },
        "in-memory state advances even when the write fails")
    expect(s.persistenceError != null && s.persistenceError!!.contains("写入失败"),
        "Top3 save failure surfaced, was: ${s.persistenceError}")

    // nothing reached the disk
    val dataFile = java.io.File(dir, ".habitica-pomodoro/habitica_pomodoro_top_three.json")
    expect(!dataFile.exists(), "no store file can exist behind the blocked dir")
    println("FIX2-01 OK")
}

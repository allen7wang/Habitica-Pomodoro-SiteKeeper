// FIX3 guard (depends on FIX2): when the successful cycle's merge could not be
// PERSISTED (write failure), the cycle did not complete cleanly — the previous
// sync error must not be cleared, and the persistence failure must be visible.
// RED against gated sources: UiState.persistenceError does not exist.
import com.habitica.pomodoro.data.HabiticaAPI

fun main() {
    val dir = newTempDir("fix3-05")
    seedSettings(dir)
    seedTopThree(dir, ownedStore())

    val vm = newVm(dir)
    HabiticaAPI.fetchFailure = "网络连接失败，请检查网络或服务器"
    vm.refreshTopThreeFromCloud()
    expect(vm.state.value.topThreeSyncError != null, "precondition: stale error set")

    // Recover the network but break storage; the inbound todo forces a merge write.
    HabiticaAPI.fetchFailure = null
    HabiticaAPI.cloud += cloudTodo("RID-W", "w-task")
    val data = dataDir(dir)
    expect(data.deleteRecursively(), "data dir cleared")
    java.io.File(dir, ".habitica-pomodoro").writeText("blocker")

    vm.refreshTopThreeFromCloud()
    expect(vm.state.value.store.history.values.flatMap { it.taskGroups.flatten() }
        .any { it.habiticaTaskId == "RID-W" }, "merge advanced in memory")
    expect(vm.state.value.persistenceError != null, "write failure visible (FIX2)")
    expect(vm.state.value.topThreeSyncError != null,
        "sync error must NOT clear when the cycle's write failed")
    println("FIX3-05 OK")
}

// FIX3 guard: while a quarantine conflict is active in the cycle, the
// successful refresh must KEEP reporting it (set the conflict message), never
// clear it. Green before and after the fix — pins the "don't over-clear" side.
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val dir = newTempDir("fix3-02")
    seedSettings(dir)
    val today = logicalTodayKey()
    val marker = "${topThreeNotes("Work", today)}\nghost"
    seedTopThree(dir, ownedStore().copy(deletedCreateMarkers = setOf(marker)))

    val vm = newVm(dir) { HabiticaAPI.cloud += cloudTodo("RID-G2", "ghost") }
    expect(vm.state.value.topThreeSyncError?.contains("已隔离") == true,
        "precondition: conflict reported, was: ${vm.state.value.topThreeSyncError}")

    vm.refreshTopThreeFromCloud() // successful fetch, conflict still active
    expect(vm.state.value.topThreeSyncError?.contains("已隔离") == true,
        "conflict message must survive/repeat on every successful-but-conflicted cycle, was: ${vm.state.value.topThreeSyncError}")
    println("FIX3-02 OK")
}

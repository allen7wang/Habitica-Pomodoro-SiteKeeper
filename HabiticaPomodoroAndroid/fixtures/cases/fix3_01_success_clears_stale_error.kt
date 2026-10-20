// FIX3(P1/D4) RED case: topThreeSyncError must CLEAR when a subsequent refresh
// cycle completes successfully without any active error condition. Compiles
// against the gated sources and FAILS at runtime there (stale error survives),
// which is the defect.
import com.habitica.pomodoro.data.HabiticaAPI

fun main() {
    val dir = newTempDir("fix3-01")
    seedSettings(dir)
    seedTopThree(dir, ownedStore())

    val vm = newVm(dir) {
        HabiticaAPI.fetchFailure = "网络连接失败，请检查网络或服务器"
    }
    expect(vm.state.value.topThreeSyncError != null, "precondition: stale error displayed")

    // network recovers; clean successful refresh with an empty cloud
    HabiticaAPI.fetchFailure = null
    vm.refreshTopThreeFromCloud()

    expectEq(vm.state.value.topThreeSyncing, false, "cycle finished")
    expectEq(vm.state.value.topThreeSyncError, null,
        "stale error must be cleared by a clean successful cycle")
    println("FIX3-01 OK")
}

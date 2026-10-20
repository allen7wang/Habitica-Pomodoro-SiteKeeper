// FIX2(P1/D2): the settings save path surfaces write failures too — the call
// site (updateSettings) can show it, so the failure must not stay silent.
// RED against gated sources: UiState.persistenceError does not exist.
fun main() {
    val dir = newTempDir("fix2-03")
    java.io.File(dir, ".habitica-pomodoro").writeText("blocker")

    val vm = newVm(dir)
    vm.updateSettings { it.copy(pomoDurationMins = 30) }

    expectEq(vm.state.value.settings.pomoDurationMins, 30, "in-memory setting advances")
    expect(vm.state.value.persistenceError != null && vm.state.value.persistenceError!!.contains("写入失败"),
        "settings save failure surfaced, was: ${vm.state.value.persistenceError}")
    expect(!java.io.File(dir, ".habitica-pomodoro/habitica_pomodoro_settings.json").exists(),
        "nothing persisted behind the blocked dir")
    println("FIX2-03 OK")
}

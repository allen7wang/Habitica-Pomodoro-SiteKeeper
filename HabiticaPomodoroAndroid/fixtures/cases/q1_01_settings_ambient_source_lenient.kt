// QISHI(a): settings JSON without ambientSource decodes leniently to "custom";
// "qishi" round-trips through the settings JSON (Apple-identical key) and the
// existing LocalStore/updateSettings save path.
// RED against gated sources: UserSettings.ambientSource does not exist.
import com.habitica.pomodoro.data.LocalStore
import com.habitica.pomodoro.data.UserSettings
import org.json.JSONObject

fun main() {
    // 1. Legacy JSON without the field decodes to "custom".
    val legacy = UserSettings.fromJson(JSONObject("""{"pomoDurationMins":25}"""))
    expectEq(legacy.ambientSource, "custom", "missing ambientSource decodes to custom")

    // 2. "qishi" round-trips through toJson/fromJson; key name matches Apple schema.
    val qishi = UserSettings(ambientSource = "qishi")
    expectEq(qishi.toJson().optString("ambientSource"), "qishi", "toJson writes the ambientSource key verbatim")
    expectEq(UserSettings.fromJson(qishi.toJson()).ambientSource, "qishi", "qishi JSON round-trip")

    // 3. LocalStore save/load round-trip.
    val dir = newTempDir("q1-01")
    val store = LocalStore(TestApp(dir))
    store.saveSettings(UserSettings(ambientSource = "qishi", ambientSoundVolume = 0.7))
    expectEq(store.loadSettings().ambientSource, "qishi", "LocalStore round-trip keeps qishi")

    // 4. VM level: seeded old-format file loads as custom; updateSettings persists qishi.
    val appDir = newTempDir("q1-01-vm")
    seedSettings(appDir, connect = false) // legacy file: no ambientSource key at all
    val vm = newVm(appDir)
    expectEq(vm.state.value.settings.ambientSource, "custom", "VM loads legacy settings as custom")
    vm.updateSettings { it.copy(ambientSource = "qishi") }
    expectEq(vm.state.value.settings.ambientSource, "qishi", "VM in-memory settings switch to qishi")
    expectEq(readSettingsDisk(appDir).ambientSource, "qishi", "existing settings save path persists qishi")
    println("Q1-01 OK")
}

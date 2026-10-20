// Shared support for fixture cases (default package; compiled once, linked into
// every case). Provides: temp app dirs, seeded settings/store JSON, a TestApp
// (Application stub), stub resets, deterministic today-key computation and
// assertion helpers.
//
// All credentials below are OBVIOUSLY FAKE fixture strings — never real ones.
import android.app.Application
import com.habitica.pomodoro.data.CloudTodo
import com.habitica.pomodoro.data.HabiticaAPI
import com.habitica.pomodoro.data.TopThreeDay
import com.habitica.pomodoro.data.TopThreeStore
import com.habitica.pomodoro.data.TopThreeTask
import com.habitica.pomodoro.data.UserSettings
import com.habitica.pomodoro.data.topThreeNotes
import com.habitica.pomodoro.engine.PomodoroViewModel
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.UUID

val FIXTURE_UID = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f"
val FIXTURE_TOKEN = "fixtu…true"
val OTHER_UID = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e1e"
val OTHER_TOKEN = "fixtu…true"
const val OFFICIAL_ROOT = "https://habitica.com/api/v3/"
val OWNER_KEY = "$FIXTURE_UID|$OFFICIAL_ROOT"
val OTHER_OWNER_KEY = "$OTHER_UID|$OFFICIAL_ROOT"

class TestApp(override val filesDir: File) : Application()

fun expect(cond: Boolean, msg: String) {
    if (!cond) throw AssertionError(msg)
}

fun <T> expectEq(actual: T, expected: T, what: String) {
    if (actual != expected) throw AssertionError("$what: expected <$expected> but was <$actual>")
}

fun newTempDir(prefix: String = "pomo-fixture"): File =
    Files.createTempDirectory(prefix).toFile().also { it.deleteOnExit() }

fun dataDir(appDir: File): File = File(appDir, ".habitica-pomodoro")

fun seedSettings(appDir: File, uid: String = FIXTURE_UID, token: String = FIXTURE_TOKEN, connect: Boolean = true) {
    val dir = dataDir(appDir)
    dir.mkdirs()
    File(dir, "habitica_pomodoro_settings.json").writeText(JSONObject().apply {
        put("uid", uid); put("apiToken", token); put("connectHabitica", connect)
    }.toString())
}

fun seedTopThree(appDir: File, store: TopThreeStore) {
    val dir = dataDir(appDir)
    dir.mkdirs()
    File(dir, "habitica_pomodoro_top_three.json").writeText(store.toJson().toString())
}

fun readTopThreeDisk(appDir: File): TopThreeStore =
    TopThreeStore.fromJson(JSONObject(File(dataDir(appDir), "habitica_pomodoro_top_three.json").readText()))

fun readSettingsDisk(appDir: File): UserSettings =
    UserSettings.fromJson(JSONObject(File(dataDir(appDir), "habitica_pomodoro_settings.json").readText()))

/** Mirrors LocalStore.logicalDateKey with the default 04:00 boundary. */
fun logicalTodayKey(boundaryMinutes: Int = 240): String {
    val cal = Calendar.getInstance()
    val minuteOfDay = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
    if (minuteOfDay < boundaryMinutes) cal.add(Calendar.DAY_OF_YEAR, -1)
    return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)
}

fun cloudTodo(id: String, title: String, category: String = "Work",
              date: String = logicalTodayKey(), completed: Boolean = false,
              tags: List<String> = emptyList()): CloudTodo =
    CloudTodo(id, title, topThreeNotes(category, date), completed, tags)

fun ownedTask(id: String? = null, title: String, remoteId: String? = null,
              pendingTitle: String? = null, pendingNotes: String? = null,
              movedToToday: Boolean = false, completed: Boolean = false,
              syncPending: Boolean = false, owner: String? = OWNER_KEY): TopThreeTask =
    TopThreeTask(id = id ?: UUID.randomUUID().toString().uppercase(), title = title,
        isCompleted = completed, habiticaTaskId = remoteId, movedToToday = movedToToday,
        syncPending = syncPending, pendingCreateTitle = pendingTitle, pendingCreateNotes = pendingNotes,
        cloudAccount = owner)

fun dayWith(date: String, categoryIndex: Int, tasks: List<TopThreeTask>, categories: Int = 3): TopThreeDay =
    TopThreeDay(date, List(categories) { i -> if (i == categoryIndex) tasks else emptyList() })

fun ownedStore(owner: String? = OWNER_KEY,
               history: Map<String, TopThreeDay> = emptyMap()): TopThreeStore =
    TopThreeStore(cloudAccount = owner, ownerInitialized = true, history = history)

/**
 * Builds a VM over a fresh temp dir. ALWAYS resets the substitute API and the
 * service stubs first, then applies `configureStub` BEFORE construction, so the
 * synchronous init cycle (loadAll -> refreshProfile/refreshTopThreeFromCloud/
 * ensureDefaultHabits, all Unconfined) sees the scripted world.
 * Returns the VM; the app dir is `appDir` (seed it before calling).
 */
fun newVm(appDir: File, configureStub: () -> Unit = {}): PomodoroViewModel {
    HabiticaAPI.reset()
    com.habitica.pomodoro.service.PomodoroTimerService.reset()
    com.habitica.pomodoro.service.BlockReminderReceiver.reset()
    configureStub()
    return PomodoroViewModel(TestApp(appDir))
}

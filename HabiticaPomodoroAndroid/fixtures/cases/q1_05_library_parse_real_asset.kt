// QISHI(e): parse the REAL bundled asset qishi_presets.json (read directly from
// the repo path — the harness never touches the device asset pipeline):
// 73 presets; every preset has id+name; every track has file + volume 0..100;
// ids unique; randomPreset exclusion is absolute over the real library.
// RED against gated sources: QishiLibrary does not exist.
import com.habitica.pomodoro.data.QishiLibrary
import org.json.JSONObject
import java.io.File

private fun findAsset(): File {
    val rels = listOf(
        "HabiticaPomodoroAndroid/app/src/main/assets/audio/qishi_presets.json", // run from repo root
        "app/src/main/assets/audio/qishi_presets.json",                          // run from module dir
    )
    var dir: File? = File(System.getProperty("user.dir")).absoluteFile
    while (dir != null) {
        for (rel in rels) {
            val candidate = File(dir, rel)
            if (candidate.isFile) return candidate
        }
        dir = dir.parentFile
    }
    throw AssertionError("qishi_presets.json not found from ${System.getProperty("user.dir")}")
}

fun main() {
    val file = findAsset()
    val library = QishiLibrary.parse(JSONObject(file.readText()))
    expectEq(library.size, 73, "bundled library has 73 presets (file: ${file.path})")
    val ids = library.map { it.id }
    expect(ids.all { it.isNotBlank() }, "every preset has an id")
    expectEq(ids.distinct().size, ids.size, "preset ids are unique")
    expect(library.all { it.name.isNotBlank() }, "every preset has a name")
    for (preset in library) {
        expect(preset.tracks.isNotEmpty(), "preset ${preset.id} has tracks")
        for (track in preset.tracks) {
            expect(track.file.isNotBlank(), "track ${track.id} of ${preset.id} has a file")
            expect(track.volume in 0..100, "track ${track.id} of ${preset.id} volume ${track.volume} within 0..100")
        }
    }
    // Selection helper over the real library: exclusion never repeats while >1 scene.
    val excluded = ids.first()
    repeat(200) {
        val pick = QishiLibrary.randomPreset(library, excluding = excluded)
        expect(pick != null && pick.id != excluded, "randomPreset never repeats the excluded scene")
    }
    expectEq(QishiLibrary.randomPreset(emptyList(), excluding = null), null, "empty library selects nothing")
    // Single-scene library cannot exclude (would leave an empty pool).
    val only = library.take(1)
    expectEq(QishiLibrary.randomPreset(only, excluding = only[0].id), only[0], "single-scene library ignores exclusion")
    println("Q1-05 OK (${file.path})")
}

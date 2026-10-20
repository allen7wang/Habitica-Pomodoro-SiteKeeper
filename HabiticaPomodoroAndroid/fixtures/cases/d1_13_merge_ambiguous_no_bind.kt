// D1-13: pure merge — TWO cloud todos match the same pending signature
// (ambiguous). Nothing may bind; the local task keeps its pending state and
// gets the human-review syncError.
import com.habitica.pomodoro.data.mergeTopThreeTodos
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val today = logicalTodayKey()
    val notes = topThreeNotes("Work", today)
    val local = ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-13", title = "t13", pendingTitle = "t13", pendingNotes = notes)))))

    val merged = mergeTopThreeTodos(local, listOf(
        cloudTodo("RID-13A", "t13"), cloudTodo("RID-13B", "t13")))

    val task = merged.history.getValue(today).taskGroups[0].single()
    expectEq(task.habiticaTaskId, null, "ambiguous match never binds")
    expectEq(task.pendingCreateTitle, "t13", "pending state preserved")
    expect(task.syncError?.contains("创建匹配不唯一") == true,
        "human-review error set, was: ${task.syncError}")
    println("D1-13 OK")
}

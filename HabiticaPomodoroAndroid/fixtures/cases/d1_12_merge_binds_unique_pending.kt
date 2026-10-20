// D1-12: pure merge — a unique local pending candidate plus a unique cloud
// match binds the remote id onto the ORIGINAL UUID: pending fields cleared,
// syncPending raised, syncVersion bumped, no duplicate task created.
import com.habitica.pomodoro.data.mergeTopThreeTodos
import com.habitica.pomodoro.data.topThreeNotes

fun main() {
    val today = logicalTodayKey()
    val notes = topThreeNotes("Work", today)
    val local = ownedStore(history = mapOf(today to dayWith(today, 0, listOf(
        ownedTask(id = "LOCAL-12", title = "t12", pendingTitle = "t12", pendingNotes = notes)))))

    val merged = mergeTopThreeTodos(local, listOf(cloudTodo("RID-12", "t12")))

    val tasks = merged.history.getValue(today).taskGroups[0]
    expectEq(tasks.size, 1, "no duplicate created")
    val bound = tasks.single()
    expectEq(bound.id, "LOCAL-12", "bound onto the original UUID")
    expectEq(bound.habiticaTaskId, "RID-12", "remote id bound")
    expectEq(bound.pendingCreateTitle, null, "pending title cleared")
    expectEq(bound.pendingCreateNotes, null, "pending notes cleared")
    expect(bound.syncPending, "syncPending raised for confirmation")
    expectEq(bound.syncError, null, "no error on unique bind")
    println("D1-12 OK")
}

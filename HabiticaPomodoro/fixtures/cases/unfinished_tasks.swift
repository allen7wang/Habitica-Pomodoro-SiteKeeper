import Foundation

let manager = TopThreeManager.shared
var settings = UserSettings()
settings.connectHabitica = false
settings.uid = "fixture-user"
let owner = HabiticaAPI.shared.cloudAccount(settings: settings)!
let now = Date()
let calendar = Calendar.current

func logicalDay(_ offset: Int) -> String {
    manager.logicalDateKey(settings: settings, date: calendar.date(byAdding: .day, value: offset, to: now)!)
}

let today = logicalDay(0)
let yesterday = logicalDay(-1)
let older = logicalDay(-8)
let tomorrow = logicalDay(1)
let work = TopThreeTask(title: "Backlogged work", habiticaTaskId: "work-remote", cloudAccount: owner)
let chore = TopThreeTask(title: "Yesterday chore")
let deleted = TopThreeTask(title: "Older chore", habiticaTaskId: "delete-remote", cloudAccount: owner)
let complete = TopThreeTask(title: "Completed", isCompleted: true)
var previouslyMoved = work
previouslyMoved.movedToToday = true
let todayWork = (1...3).map { TopThreeTask(title: "Today \($0)") }
manager.store.history = [
    today: TopThreeDay(date: today, taskGroups: [todayWork, [], []]),
    yesterday: TopThreeDay(date: yesterday, taskGroups: [[complete], [], [chore]]),
    older: TopThreeDay(date: older, taskGroups: [[work], [], [deleted, TopThreeTask(title: "  ")]]),
    logicalDay(-9): TopThreeDay(date: logicalDay(-9), taskGroups: [[previouslyMoved]]),
    tomorrow: TopThreeDay(date: tomorrow, taskGroups: [[TopThreeTask(title: "Future")]]),
]

precondition(manager.unfinishedTasks(before: today).map(\.id) == [chore.id, work.id, deleted.id])
precondition(manager.unfinishedTasks(before: yesterday).map(\.id) == [work.id, deleted.id])
print("PASS backlog uses the logical day and retains all older incomplete tasks without archived copies")

precondition(!manager.moveTaskToToday(fromKey: older, category: 0, id: work.id, settings: settings))
precondition(manager.unfinishedTasks(before: today).contains { $0.id == work.id })
manager.removeTask(key: today, category: 0, id: todayWork[0].id, settings: settings)
precondition(manager.moveTaskToToday(fromKey: older, category: 0, id: work.id, settings: settings))
precondition(!manager.moveTaskToToday(fromKey: older, category: 0, id: work.id, settings: settings))
let moved = manager.getTasks(key: today, category: 0).last!
precondition(moved.id == work.id && moved.habiticaTaskId == work.habiticaTaskId && moved.cloudAccount == owner)
precondition(moved.syncPending && !moved.movedToToday && !moved.isCompleted)
precondition(manager.getTasks(key: older, category: 0).first?.movedToToday == true)
precondition(manager.unfinishedTasks(before: today).map(\.id) == [chore.id, deleted.id])
precondition(manager.unfinishedTasks(before: tomorrow).filter { $0.id == work.id }.count == 1)
print("PASS capacity, move from an older day, stable cloud identity, and the next logical day")

manager.removeTask(key: yesterday, category: 0, id: complete.id, settings: settings, fromUnfinished: true)
manager.removeTask(key: older, category: 0, id: work.id, settings: settings, fromUnfinished: true)
manager.removeTask(key: today, category: 0, id: work.id, settings: settings, fromUnfinished: true)
precondition(manager.getTasks(key: yesterday, category: 0).contains { $0.id == complete.id })
precondition(manager.getTasks(key: older, category: 0).contains { $0.id == work.id })
precondition(manager.getTasks(key: today, category: 0).contains { $0.id == work.id })
manager.removeTask(key: older, category: 2, id: deleted.id, settings: settings)
precondition(manager.unfinishedTasks(before: today).contains { $0.id == deleted.id })
manager.removeTask(key: older, category: 2, id: deleted.id, settings: settings, fromUnfinished: true)
manager.reload()
precondition(manager.unfinishedTasks(before: today).map(\.id) == [chore.id])
precondition(manager.store.cloudStates[owner]?.deletedCloudIds.contains("delete-remote") == true)
print("PASS backlog deletion persists and queues remote deletion while stale actions are rejected")

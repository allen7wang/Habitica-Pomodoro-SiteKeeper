import Foundation

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    let api = HabiticaAPI.shared
    let manager = TopThreeManager.shared

    @MainActor
    func scenario(_ name: String) -> (UserSettings, TopThreeTask, String, String) {
        let settings = fixtureAccount(name)
        let owner = api.cloudAccount(settings: settings)!
        let today = manager.todayKey(settings: settings)
        manager.store = TopThreeStore()
        manager.prepareCloudAccount(settings: settings)
        manager.store.categoryTagIds = ["Work": "work-tag"]
        let task = TopThreeTask(title: "Create \(name)", syncPending: true, cloudAccount: owner)
        manager.store.history = [today: .init(date: today, taskGroups: [[task], [], []])]
        return (settings, task, today, owner)
    }

    func successfulServer(_ remote: String) {
        let pending = manager.store.history.compactMap { date, day -> (String, TopThreeTask)? in
            guard let task = day.taskGroups.flatMap({ $0 }).first(where: { $0.syncPending && !$0.movedToToday }) else { return nil }
            return (date, task)
        }.first!
        let created: [String: Any] = ["id": remote, "text": pending.1.title,
            "notes": "From HabiticaPomodoro Top3 · Work · \(pending.0)",
            "tags": ["work-tag"], "completed": false]
        var entries: [[String: Any]] = []
        HabiticaFixtureProtocol.respond { request in
            if request.httpMethod == "POST" {
                entries = [created]
                return .init(status: 201, body: ["data": ["id": remote]])
            }
            return .init(body: ["data": request.url!.query?.contains("completedTodos") == true ? [] : entries])
        }
    }

    func waitForPost() async {
        for _ in 0..<10_000 {
            if HabiticaFixtureProtocol.calls.contains(where: { $0.httpMethod == "POST" }) { return }
            await Task.yield()
        }
        preconditionFailure("expected the delayed create request to start")
    }

    let (rejected, rejectedTask, rejectedDay, _) = scenario("rejected-401")
    HabiticaFixtureProtocol.respond { request in request.httpMethod == "POST" ? .init(status: 401) : .init() }
    await manager.synchronize(settings: rejected)
    let afterRejection = manager.getTasks(key: rejectedDay, category: 0).first!
    checkHabitica(afterRejection.id == rejectedTask.id && afterRejection.syncPending &&
                  afterRejection.habiticaTaskId == nil && afterRejection.cloudCreateAttempt == nil,
                  "a definite authentication rejection clears only the create marker and retains the pending local task")
    manager.reload()
    successfulServer("retried-once")
    await manager.synchronize(settings: rejected)
    checkHabitica(HabiticaFixtureProtocol.calls.filter { $0.httpMethod == "POST" }.count == 1 &&
                  manager.getTasks(key: rejectedDay, category: 0).first?.habiticaTaskId == "retried-once" &&
                  manager.getTasks(key: rejectedDay, category: 0).first?.syncPending == false,
                  "after reload a healthy sync creates the previously rejected task once and verifies it")

    let (limited, _, limitedDay, _) = scenario("rejected-429")
    HabiticaFixtureProtocol.respond { request in
        request.httpMethod == "POST" ? .init(status: 429, headers: ["Retry-After": "0"]) : .init()
    }
    await manager.synchronize(settings: limited)
    checkHabitica(manager.getTasks(key: limitedDay, category: 0).first?.cloudCreateAttempt == nil &&
                  manager.getTasks(key: limitedDay, category: 0).first?.syncPending == true &&
                  api.rateLimitMessage(settings: limited) != nil,
                  "a definite 429 rejection releases the create marker while keeping the shared cooldown")
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    successfulServer("created-after-cooldown")
    await manager.synchronize(settings: limited)
    checkHabitica(HabiticaFixtureProtocol.calls.filter { $0.httpMethod == "POST" }.count == 1 &&
                  manager.getTasks(key: limitedDay, category: 0).first?.habiticaTaskId == "created-after-cooldown",
                  "manual synchronization after the 429 cooldown safely retries creation once")

    let (budgeted, budgetedTask, budgetedDay, _) = scenario("rejected-before-dispatch")
    // Direct per-row pushes, unlike batch sync, can enter with an exhausted budget.
    manager.store.history = [:]
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": ["gp": 1]]) }
    for index in 0..<HabiticaRequestBudget.localLimit {
        _ = await api.scoreHabit(taskId: "budget-\(index)", direction: "up", settings: budgeted)
    }
    manager.addTask(key: budgetedDay, category: 0, title: budgetedTask.title, settings: budgeted)
    for _ in 0..<1_000 { await Task.yield() }
    let neverSent = manager.getTasks(key: budgetedDay, category: 0).first!
    checkHabitica(HabiticaFixtureProtocol.calls.count == HabiticaRequestBudget.localLimit &&
                  neverSent.syncPending && neverSent.cloudCreateAttempt == nil && neverSent.habiticaTaskId == nil,
                  "local budget rejection before dispatch cannot strand a direct per-row create attempt")

    let (cancelled, _, cancelledDay, _) = scenario("cancelled-before-dispatch")
    HabiticaFixtureProtocol.respond { _ in .init() }
    let cancelledSync = Task { @MainActor in await manager.synchronize(settings: cancelled) }
    cancelledSync.cancel()
    await cancelledSync.value
    checkHabitica(HabiticaFixtureProtocol.calls.isEmpty &&
                  manager.getTasks(key: cancelledDay, category: 0).first?.cloudCreateAttempt == nil &&
                  manager.getTasks(key: cancelledDay, category: 0).first?.syncPending == true,
                  "task cancellation before dispatch clears the marker without sending a create request")

    for status in [400, 500, 201] {
        let (uncertain, _, day, _) = scenario("uncertain-\(status)")
        HabiticaFixtureProtocol.respond { request in
            request.httpMethod == "POST" ? .init(status: status) : .init()
        }
        await manager.synchronize(settings: uncertain)
        manager.reload()
        HabiticaFixtureProtocol.respond { _ in .init() }
        await manager.synchronize(settings: uncertain)
        checkHabitica(manager.getTasks(key: day, category: 0).first?.cloudCreateAttempt != nil &&
                      manager.getTasks(key: day, category: 0).first?.syncPending == true &&
                      !HabiticaFixtureProtocol.calls.contains { $0.httpMethod == "POST" },
                      "uncertain create outcome \(status) retains its durable marker and never blindly repeats POST")
    }

    for code in [URLError.Code.timedOut, .networkConnectionLost, .cancelled] {
        let (uncertain, _, day, _) = scenario("transport-error-\(code.rawValue)")
        HabiticaFixtureProtocol.respond { request in
            request.httpMethod == "POST" ? .init(error: URLError(code)) : .init()
        }
        await manager.synchronize(settings: uncertain)
        manager.reload()
        HabiticaFixtureProtocol.respond { _ in .init() }
        await manager.synchronize(settings: uncertain)
        checkHabitica(manager.getTasks(key: day, category: 0).first?.cloudCreateAttempt != nil &&
                      manager.getTasks(key: day, category: 0).first?.syncPending == true &&
                      !HabiticaFixtureProtocol.calls.contains { $0.httpMethod == "POST" },
                      "dispatched URL error \(code.rawValue) preserves the unknown result and never blindly repeats POST")
    }

    let (deleted, removedTask, deletedDay, _) = scenario("removed-during-rejection")
    HabiticaFixtureProtocol.respond { request in
        request.httpMethod == "POST" ? .init(status: 401, delay: 0.1) : .init()
    }
    let deletionSync = Task { @MainActor in await manager.synchronize(settings: deleted) }
    await waitForPost()
    manager.removeTask(key: deletedDay, category: 0, id: removedTask.id, settings: deleted)
    await deletionSync.value
    checkHabitica(manager.getTasks(key: deletedDay, category: 0).isEmpty &&
                  manager.store.deletedCreateAttempts.isEmpty,
                  "deletion during a definitely rejected POST leaves no unresolvable removal marker")
    let replacement = TopThreeTask(title: "Different replacement", syncPending: true,
                                   cloudAccount: api.cloudAccount(settings: deleted))
    manager.store.history[deletedDay] = .init(date: deletedDay, taskGroups: [[replacement], [], []])
    successfulServer("replacement-created")
    await manager.synchronize(settings: deleted)
    checkHabitica(HabiticaFixtureProtocol.calls.filter { $0.httpMethod == "POST" }.count == 1 &&
                  manager.getTasks(key: deletedDay, category: 0).first?.habiticaTaskId == "replacement-created",
                  "a later different task in the same day and category is not blocked by that rejected deletion")

    let (oldSettings, original, oldDay, oldOwner) = scenario("owner-a-during-rejection")
    HabiticaFixtureProtocol.respond { request in
        request.httpMethod == "POST" ? .init(status: 401, delay: 0.1) : .init()
    }
    let oldSync = Task { @MainActor in await manager.synchronize(settings: oldSettings) }
    await waitForPost()
    let originalAttempt = manager.getTasks(key: oldDay, category: 0).first!.cloudCreateAttempt!
    let otherSettings = fixtureAccount("owner-b-during-rejection")
    manager.prepareCloudAccount(settings: otherSettings)
    // Even a coincident UUID/payload in another account must remain untouched.
    manager.store.deletedCreateAttempts = [.init(id: original.id, attempt: originalAttempt)]
    manager.save()
    await oldSync.value
    checkHabitica(manager.store.cloudAccount == api.cloudAccount(settings: otherSettings) &&
                  manager.store.deletedCreateAttempts.count == 1 &&
                  manager.getTasks(key: oldDay, category: 0).first?.cloudAccount == oldOwner &&
                  manager.getTasks(key: oldDay, category: 0).first?.cloudCreateAttempt == nil,
                  "an old-account rejection clears its own row after switching without touching the active owner's intent")

    let (deletedOldSettings, deletedOldTask, deletedOldDay, deletedOldOwner) = scenario("deleted-owner-a")
    HabiticaFixtureProtocol.respond { request in
        request.httpMethod == "POST" ? .init(status: 401, delay: 0.1) : .init()
    }
    let deletedOldSync = Task { @MainActor in await manager.synchronize(settings: deletedOldSettings) }
    await waitForPost()
    let oldAttempt = manager.getTasks(key: deletedOldDay, category: 0).first!.cloudCreateAttempt!
    manager.removeTask(key: deletedOldDay, category: 0, id: deletedOldTask.id, settings: deletedOldSettings)
    let newSettings = fixtureAccount("deleted-owner-b")
    manager.prepareCloudAccount(settings: newSettings)
    let unrelated = DeletedCloudCreateAttempt(id: UUID(), attempt: oldAttempt)
    var savedOldState = manager.store.cloudStates[deletedOldOwner]!
    savedOldState.deletedCreateAttempts.append(unrelated)
    manager.store.cloudStates[deletedOldOwner] = savedOldState
    manager.save()
    await deletedOldSync.value
    manager.reload()
    checkHabitica(manager.store.cloudAccount == api.cloudAccount(settings: newSettings) &&
                  manager.store.cloudStates[deletedOldOwner]?.deletedCreateAttempts == [unrelated],
                  "rejection removes only the matching old-owner UUID/attempt intent and persists unrelated intents")

    let (guarded, guardedTask, guardedDay, _) = scenario("changed-attempt")
    HabiticaFixtureProtocol.respond { request in
        request.httpMethod == "POST" ? .init(status: 401, delay: 0.1) : .init()
    }
    let guardedSync = Task { @MainActor in await manager.synchronize(settings: guarded) }
    await waitForPost()
    let earlierAttempt = manager.getTasks(key: guardedDay, category: 0).first!.cloudCreateAttempt!
    let newerAttempt = CloudCreateAttempt(title: "Newer payload", notes: earlierAttempt.notes, tags: earlierAttempt.tags)
    var changed = guardedTask
    changed.cloudCreateAttempt = newerAttempt
    var differentId = TopThreeTask(title: "Another UUID", syncPending: true, cloudAccount: changed.cloudAccount)
    differentId.cloudCreateAttempt = earlierAttempt
    var alreadyBound = guardedTask
    alreadyBound.habiticaTaskId = "already-bound"
    alreadyBound.cloudCreateAttempt = earlierAttempt
    manager.store.history[guardedDay] = .init(date: guardedDay, taskGroups: [[changed, differentId, alreadyBound], [], []])
    let changedIntent = DeletedCloudCreateAttempt(id: guardedTask.id, attempt: newerAttempt)
    let otherIntent = DeletedCloudCreateAttempt(id: UUID(), attempt: earlierAttempt)
    manager.store.deletedCreateAttempts = [changedIntent, otherIntent]
    await guardedSync.value
    let guardedRows = manager.getTasks(key: guardedDay, category: 0)
    checkHabitica(guardedRows[0].cloudCreateAttempt == newerAttempt &&
                  guardedRows[1].cloudCreateAttempt == earlierAttempt &&
                  guardedRows[2].cloudCreateAttempt == earlierAttempt &&
                  guardedRows[2].habiticaTaskId == "already-bound" &&
                  manager.store.deletedCreateAttempts == [changedIntent, otherIntent],
                  "a late rejection preserves changed attempts, other UUIDs, bound IDs and unmatched removal intents")
}

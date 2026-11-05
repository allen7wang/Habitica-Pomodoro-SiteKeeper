import Foundation

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    let api = HabiticaAPI.shared
    let manager = TopThreeManager.shared
    let settings = fixtureAccount("deletions")
    manager.store = TopThreeStore()
    manager.prepareCloudAccount(settings: settings)
    manager.store.deletedCloudIds = ["gone", "exists", "failed"]
    HabiticaFixtureProtocol.respond { request in
        guard request.httpMethod == "DELETE" else { return .init() }
        return .init(status: request.url!.lastPathComponent == "failed" ? 500 :
            (request.url!.lastPathComponent == "gone" ? 404 : 200))
    }
    await manager.synchronize(settings: settings)
    checkHabitica(Set(manager.store.confirmedDeletedCloudIds) == Set(["gone", "exists"]) &&
                  Set(manager.store.deletedCloudIds) == Set(["gone", "exists", "failed"]),
                  "200/404 retire deletion requests, failed deletions stay pending, and tombstones remain")
    manager.reload()
    checkHabitica(Set(manager.store.confirmedDeletedCloudIds) == Set(["gone", "exists"]),
                  "deletion acknowledgements survive a reload")
    HabiticaFixtureProtocol.respond { _ in .init() }
    await manager.synchronize(settings: settings)
    let deletes = HabiticaFixtureProtocol.calls.filter { $0.httpMethod == "DELETE" }
    checkHabitica(deletes.count == 1 && deletes.first?.url?.lastPathComponent == "failed" &&
                  manager.store.confirmedDeletedCloudIds.count == 3,
                  "the next sync sends only the previously failed deletion")
    HabiticaFixtureProtocol.respond { _ in .init() }
    manager.reload()
    await manager.synchronize(settings: settings)
    checkHabitica(!HabiticaFixtureProtocol.calls.contains { $0.httpMethod == "DELETE" },
                  "later syncs and restarts do not re-delete acknowledged tombstones")
    let owner = api.cloudAccount(settings: settings)!
    _ = manager.mergeOwnedTodos([.init(id: "gone", title: "Stale copy",
        notes: "From HabiticaPomodoro Top3 · Work · 2026-11-05", completed: false, tags: [])], owner: owner)
    checkHabitica(manager.store.history.values.flatMap { $0.taskGroups.flatMap { $0 } }.isEmpty,
                  "a stale remote response cannot resurrect a confirmed deletion")
    let other = fixtureAccount("other-owner")
    manager.prepareCloudAccount(settings: other)
    checkHabitica(manager.store.confirmedDeletedCloudIds.isEmpty, "deletion acknowledgements are scoped to their owner")
    SettingsManager.shared.settings = settings
    manager.prepareCloudAccount(settings: settings)
    checkHabitica(manager.store.confirmedDeletedCloudIds.count == 3, "switching back restores the owner's acknowledgements")

    // Old JSON has tombstones but no acknowledgement field; migration must retry those once.
    let legacy = try! JSONDecoder().decode(TopThreeStore.self,
        from: Data(#"{"deletedCloudIds":["legacy"],"cloudStates":{"legacy-owner":{"deletedCloudIds":["legacy"]}}}"#.utf8))
    checkHabitica(legacy.deletedCloudIds == ["legacy"] && legacy.confirmedDeletedCloudIds.isEmpty &&
                  legacy.cloudStates["legacy-owner"]?.confirmedDeletedCloudIds.isEmpty == true,
                  "legacy stores decode without treating unconfirmed deletions as completed")

    let limited = fixtureAccount("sync-429")
    manager.store = TopThreeStore()
    manager.prepareCloudAccount(settings: limited)
    manager.store.deletedCloudIds = ["first", "second", "third"]
    HabiticaFixtureProtocol.respond { _ in .init(status: 429, headers: ["Retry-After": "60"]) }
    await manager.synchronize(settings: limited)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1 && manager.store.confirmedDeletedCloudIds.isEmpty &&
                  manager.store.deletedCloudIds.count == 3 && manager.syncMessage?.contains("HTTP 429") == true,
                  "a 429 stops the remaining sync batch without dropping deletion intent")
    await manager.synchronize(settings: limited)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1, "refreshing during cooldown sends no more requests")

    for shouldComplete in [false, true] {
        let edit = fixtureAccount(shouldComplete ? "complete-edit" : "text-edit")
        manager.store = TopThreeStore()
        manager.prepareCloudAccount(settings: edit)
        manager.store.categoryTagIds = ["Work": "work-tag"]
        let key = "2026-11-05"
        let task = TopThreeTask(title: "Updated title", isCompleted: shouldComplete,
            habiticaTaskId: "edited", syncPending: true, cloudAccount: api.cloudAccount(settings: edit))
        manager.store.history = [key: .init(date: key, taskGroups: [[task], [], []])]
        var completedRemotely = false
        HabiticaFixtureProtocol.respond { request in
            if request.httpMethod == "POST" { completedRemotely = true; return .init(body: ["data": ["gp": 1]]) }
            if request.httpMethod == "PUT" { return .init() }
            let isCompletedList = request.url!.query?.contains("type=completedTodos") == true
            let include = isCompletedList == completedRemotely
            let entry: [String: Any] = ["id": "edited", "text": "Updated title",
                "notes": "From HabiticaPomodoro Top3 · Work · \(key)", "tags": ["work-tag"],
                "completed": completedRemotely]
            return .init(body: ["data": include ? [entry] : []])
        }
        await manager.synchronize(settings: edit)
        let calls = HabiticaFixtureProtocol.calls
        let reads = calls.filter { ($0.httpMethod ?? "GET") == "GET" }.count
        checkHabitica(reads == (shouldComplete ? 6 : 4) &&
                      calls.filter { $0.httpMethod == "POST" }.count == (shouldComplete ? 1 : 0) &&
                      manager.store.history[key]?.taskGroups[0].first?.syncPending == false,
                      shouldComplete ? "completion is scored once and read back before acknowledging the edit"
                          : "unchanged completion reuses the post-PUT verification instead of fetching twice")
    }

    let exhausted = fixtureAccount("local-sync-limit")
    manager.store = TopThreeStore()
    manager.prepareCloudAccount(settings: exhausted)
    manager.store.deletedCloudIds = (0..<30).map { "obsolete-\($0)" }
    HabiticaFixtureProtocol.respond { _ in .init() }
    await manager.synchronize(settings: exhausted)
    checkHabitica(HabiticaFixtureProtocol.calls.count == HabiticaRequestBudget.localLimit &&
                  manager.store.confirmedDeletedCloudIds.count == HabiticaRequestBudget.localLimit &&
                  manager.store.deletedCloudIds.count == 30 && manager.syncMessage?.contains("秒后重试") == true,
                  "large legacy batches stop at the local allowance and persist progress for the next sync")
}

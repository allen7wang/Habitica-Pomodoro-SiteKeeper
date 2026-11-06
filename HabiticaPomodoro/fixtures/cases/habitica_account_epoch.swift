import Foundation

@MainActor
func checkAccountCycle(_ name: String, changeAwayAndBack: (UserSettings) -> Void) async {
    let api = HabiticaAPI.shared
    let account = fixtureAccount("epoch-\(name)")
    var dispatches = 0
    HabiticaFixtureProtocol.respond { _ in
        dispatches += 1
        return .init(body: ["data": [["id": "task", "text": dispatches == 1 ? "Before switch" : "After switch"]]],
                     delay: dispatches == 1 ? 0.15 : 0.01)
    }
    let oldRead = Task { await api.fetchTaskList(type: "habits", settings: account) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    changeAwayAndBack(account)
    let current = await api.fetchTaskList(type: "habits", settings: account)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 2 && current?.first?.text == "After switch",
                  "\(name) refresh starts a new request instead of joining its retired connection")
    let retired = await oldRead.value
    checkHabitica(retired == nil, "\(name) retired list response cannot be applied after reconnecting")
}

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    let api = HabiticaAPI.shared

    await checkAccountCycle("A-B-A") { original in
        _ = fixtureAccount("temporary-B")
        SettingsManager.shared.settings = original
    }
    await checkAccountCycle("disconnect-reconnect") { original in
        var disabled = original
        disabled.connectHabitica = false
        SettingsManager.shared.settings = disabled
        SettingsManager.shared.settings = original
    }
    await checkAccountCycle("token-away-and-back") { original in
        var rotated = original
        rotated.apiToken = "temporary-synthetic-token"
        SettingsManager.shared.settings = rotated
        SettingsManager.shared.settings = original
    }
    await checkAccountCycle("API-root-away-and-back") { original in
        var alternate = original
        alternate.developerServerUrl = "https://alternate.fixture.invalid/api/v3/"
        SettingsManager.shared.settings = alternate
        SettingsManager.shared.settings = original
    }

    let unchanged = fixtureAccount("epoch-unrelated-setting")
    HabiticaFixtureProtocol.respond { _ in
        .init(body: ["data": [["id": "same", "text": "Shared"]]], delay: 0.1)
    }
    let beforeSetting = Task { await api.fetchTaskList(type: "habits", settings: unchanged) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    var updated = unchanged
    updated.pomoDurationMins += 1
    SettingsManager.shared.settings = updated
    let afterSetting = await api.fetchTaskList(type: "habits", settings: updated)
    let firstSetting = await beforeSetting.value
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1 && firstSetting?.first?.id == "same" &&
                  afterSetting?.first?.id == "same",
                  "an unrelated preference edit keeps same-connection reads coalesced and usable")

    let canonical = fixtureAccount("epoch-equivalent-root")
    HabiticaFixtureProtocol.respond { _ in
        .init(body: ["data": [["id": "canonical", "text": "Shared"]]], delay: 0.1)
    }
    let beforeRoot = Task { await api.fetchTaskList(type: "habits", settings: canonical) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    var equivalent = canonical
    equivalent.developerServerUrl = "https://HABITICA.fixture.invalid:443/api/v3////"
    SettingsManager.shared.settings = equivalent
    let afterRoot = await api.fetchTaskList(type: "habits", settings: equivalent)
    let firstRoot = await beforeRoot.value
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1 && firstRoot?.first?.id == "canonical" &&
                  afterRoot?.first?.id == "canonical",
                  "an equivalent normalized API root keeps same-connection reads coalesced and usable")

    let profileRoot = fixtureAccount("epoch-profile-equivalent-root")
    api.monies = 0
    api.isAuthenticated = false
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": ["stats": ["gp": 12]]], delay: 0.1) }
    let canonicalProfile = Task { await api.fetchUserData(settings: profileRoot) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    var equivalentProfile = profileRoot
    equivalentProfile.developerServerUrl = "https://HABITICA.fixture.invalid:443/api/v3////"
    SettingsManager.shared.settings = equivalentProfile
    await canonicalProfile.value
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1 && api.monies == 12 && api.isAuthenticated,
                  "an equivalent normalized API root does not discard an accepted profile response")

    for oldStatus in [200, 401, 0] {
        let oldOutcome = oldStatus == 0 ? "network error" : "HTTP \(oldStatus)"
        let account = fixtureAccount("epoch-profile-\(oldStatus)")
        api.monies = 0
        api.isAuthenticated = false
        api.lastError = nil
        var dispatches = 0
        HabiticaFixtureProtocol.respond { _ in
            dispatches += 1
            if dispatches == 1 {
                if oldStatus == 0 { return .init(delay: 0.15, error: URLError(.notConnectedToInternet)) }
                return .init(status: oldStatus, body: ["data": ["stats": ["gp": 1]]], delay: 0.15)
            }
            return .init(body: ["data": ["stats": ["gp": 9]]], delay: 0.01)
        }
        let oldProfile = Task { await api.fetchUserData(settings: account) }
        while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
        _ = fixtureAccount("epoch-profile-intermediate-\(oldStatus)")
        SettingsManager.shared.settings = account
        await api.fetchUserData(settings: account)
        checkHabitica(HabiticaFixtureProtocol.calls.count == 2 && api.monies == 9 && api.isAuthenticated,
                      "profile refresh after A-B-A uses a fresh connection before the old \(oldOutcome) completes")
        await oldProfile.value
        checkHabitica(api.monies == 9 && api.isAuthenticated && api.lastError == nil,
                      "retired profile \(oldOutcome) cannot overwrite current stats or authentication")
    }

    let limited = fixtureAccount("epoch-preserves-budget")
    HabiticaFixtureProtocol.respond { _ in .init(status: 429, headers: ["Retry-After": "60"]) }
    _ = await api.fetchTaskList(type: "habits", settings: limited)
    var changed = limited
    changed.connectHabitica = false
    SettingsManager.shared.settings = changed
    changed.connectHabitica = true
    changed.apiToken = "rotated-synthetic-token"
    SettingsManager.shared.settings = changed
    _ = await api.fetchTaskList(type: "dailys", settings: changed)
    SettingsManager.shared.settings = limited
    _ = await api.fetchTaskList(type: "habits", settings: limited)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1 &&
                  api.rateLimitMessage(settings: limited)?.contains("HTTP 429") == true,
                  "connection epochs and token rotation do not reset the same account's cooldown")

    let writing = fixtureAccount("epoch-sent-create")
    HabiticaFixtureProtocol.respond { _ in
        .init(status: 201, body: ["data": ["id": "created-before-switch"]], delay: 0.15)
    }
    let sentCreate = Task { @MainActor in
        await api.createTodo(text: "Create once", notes: "Synthetic fixture", tagIds: [], settings: writing)
    }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    _ = fixtureAccount("epoch-sent-create-other-owner")
    let creationResult = await sentCreate.value
    var createdID: String?
    if case .created(let id) = creationResult { createdID = id }
    checkHabitica(createdID == "created-before-switch" && HabiticaFixtureProtocol.calls.count == 1 &&
                  HabiticaFixtureProtocol.calls.first?.httpMethod == "POST",
                  "a dispatched create returns its real created ID after switching accounts without replaying POST")

    let lateLimit = fixtureAccount("epoch-retired-429")
    var limitedDispatches = 0
    HabiticaFixtureProtocol.respond { _ in
        limitedDispatches += 1
        if limitedDispatches == 1 { return .init(status: 429, headers: ["Retry-After": "60"], delay: 0.15) }
        return .init(body: ["data": ["stats": ["gp": 19]]], delay: 0.01)
    }
    let retiredLimit = Task { await api.fetchTaskList(type: "habits", settings: lateLimit) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    _ = fixtureAccount("epoch-retired-429-intermediate")
    SettingsManager.shared.settings = lateLimit
    await api.fetchUserData(settings: lateLimit)
    let retiredLimitedList = await retiredLimit.value
    checkHabitica(retiredLimitedList == nil && api.monies == 19 && api.isAuthenticated && api.lastError == nil,
                  "a retired 429 cannot replace current profile feedback or authentication")
    let afterLateLimit = await api.fetchTaskList(type: "dailys", settings: lateLimit)
    checkHabitica(afterLateLimit == nil && HabiticaFixtureProtocol.calls.count == 2 &&
                  api.rateLimitMessage(settings: lateLimit)?.contains("HTTP 429") == true,
                  "a retired 429 still updates its UID and API root budget before the next current request")

    let compound = fixtureAccount("epoch-compound-todos")
    var openReads = 0
    var completedReads = 0
    HabiticaFixtureProtocol.respond { request in
        if request.url!.query?.contains("completedTodos") == true {
            completedReads += 1
            return .init(body: ["data": [["id": completedReads == 1 ? "old-complete" : "new-complete",
                                          "text": "Completed", "completed": true]]],
                         delay: completedReads == 1 ? 0.15 : 0.01)
        }
        openReads += 1
        return .init(body: ["data": [["id": openReads == 1 ? "old-open" : "new-open", "text": "Open"]]])
    }
    let retiredTodos = Task { await api.fetchTopThreeTodos(settings: compound) }
    while !HabiticaFixtureProtocol.calls.contains(where: { $0.url!.query?.contains("completedTodos") == true }) {
        await Task.yield()
    }
    _ = fixtureAccount("epoch-compound-intermediate")
    SettingsManager.shared.settings = compound
    let currentTodos = await api.fetchTopThreeTodos(settings: compound)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 4 &&
                  currentTodos?.map({ $0.id }) == ["new-open", "new-complete"],
                  "a composite todo refresh after A-B-A performs both new reads independently of the retired second leg")
    let oldTodos = await retiredTodos.value
    checkHabitica(oldTodos == nil,
                  "a composite todo result is discarded when its second read crosses a connection epoch")
}

import Foundation

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    let api = HabiticaAPI.shared
    var failures: [String] = []

    // Collect independent scenarios before failing, so a RED run identifies every
    // response-order regression instead of stopping at the first late success.
    @MainActor
    func verify(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { failures.append(label); print("FAIL \(label)") }
    }

    @MainActor
    func account(_ name: String) -> UserSettings {
        let settings = fixtureAccount("response-order-\(name)")
        api.lastError = nil
        api.isAuthenticated = true
        return settings
    }

    @MainActor
    func waitForDispatch() async {
        let deadline = Date().addingTimeInterval(2)
        while HabiticaFixtureProtocol.calls.isEmpty && Date() < deadline { await Task.yield() }
        precondition(!HabiticaFixtureProtocol.calls.isEmpty, "expected the slow request to dispatch")
    }

    @MainActor
    func flushErrorPublication() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    let laterFailures: [(String, HabiticaFixtureProtocol.Reply)] = [
        ("HTTP 500", .init(status: 500)),
        ("offline", .init(error: URLError(.notConnectedToInternet)))
    ]
    for (index, entry) in laterFailures.enumerated() {
        let settings = account("profile-\(index)")
        HabiticaFixtureProtocol.respond { request in
            if request.httpMethod == "POST" { return entry.1 }
            return .init(body: ["data": ["stats": ["gp": 11]]], delay: 0.15)
        }
        let slowProfile = Task { await api.fetchUserData(settings: settings) }
        await waitForDispatch()
        _ = await api.scoreTask(taskId: "newer-score", direction: "up", settings: settings)
        let newerError = api.lastError
        await slowProfile.value
        await flushErrorPublication()
        verify(newerError != nil && api.lastError == newerError && HabiticaFixtureProtocol.calls.count == 2,
               "an earlier slow profile success preserves the later score \(entry.0) error")
    }

    for (index, entry) in laterFailures.enumerated() {
        let settings = account("list-\(index)")
        HabiticaFixtureProtocol.respond { request in
            if request.httpMethod == "POST" { return entry.1 }
            return .init(body: ["data": [["id": "kept", "text": "Valid habit"]]], delay: 0.15)
        }
        let slowList = Task { await api.fetchTaskList(type: "habits", settings: settings) }
        await waitForDispatch()
        _ = await api.scoreTask(taskId: "newer-score", direction: "up", settings: settings)
        let newerError = api.lastError
        let items = await slowList.value
        await flushErrorPublication()
        verify(items?.first?.id == "kept" && newerError != nil && api.lastError == newerError &&
               HabiticaFixtureProtocol.calls.count == 2,
               "an earlier slow list success remains usable without clearing the later \(entry.0) error")
    }

    let authentication = account("authentication")
    HabiticaFixtureProtocol.respond { request in
        if request.httpMethod == "POST" { return .init(status: 401) }
        return .init(body: ["data": ["stats": ["gp": 12]]], delay: 0.15)
    }
    let slowAuthenticatedProfile = Task { await api.fetchUserData(settings: authentication) }
    await waitForDispatch()
    _ = await api.scoreTask(taskId: "rejected-score", direction: "up", settings: authentication)
    let authenticationError = api.lastError
    let rejectedAuthentication = !api.isAuthenticated
    await slowAuthenticatedProfile.value
    await flushErrorPublication()
    verify(rejectedAuthentication && !api.isAuthenticated && authenticationError != nil &&
           api.lastError == authenticationError && HabiticaFixtureProtocol.calls.count == 2,
           "an earlier successful profile cannot undo a later 401 authentication failure")

    // A valid older response must also preserve an error discovered while parsing
    // a newer HTTP 200 response, rather than only preserving HTTP/transport errors.
    let parsing = account("profile-versus-parsing")
    HabiticaFixtureProtocol.respond { request in
        if request.url!.query?.contains("type=habits") == true {
            return .init(rawData: Data("<html>invalid task list</html>".utf8))
        }
        return .init(body: ["data": ["stats": ["gp": 13]]], delay: 0.15)
    }
    let profileBeforeParsing = Task { await api.fetchUserData(settings: parsing) }
    await waitForDispatch()
    let malformedList = await api.fetchTaskList(type: "habits", settings: parsing)
    await flushErrorPublication()
    let parsingError = api.lastError
    await profileBeforeParsing.value
    await flushErrorPublication()
    verify(malformedList == nil && parsingError?.contains("响应格式错误") == true &&
           api.lastError == parsingError && HabiticaFixtureProtocol.calls.count == 2,
           "an earlier profile success preserves a newer task-list parsing error")

    let listParsing = account("list-versus-parsing")
    HabiticaFixtureProtocol.respond { request in
        if request.url!.query?.contains("type=habits") == true {
            return .init(body: ["data": [["id": "visible", "text": "Still visible"]]], delay: 0.15)
        }
        return .init(body: ["data": ["unexpected": true]])
    }
    let listBeforeParsing = Task { await api.fetchTaskList(type: "habits", settings: listParsing) }
    await waitForDispatch()
    let malformedTodos = await api.fetchTopThreeTodos(settings: listParsing)
    await flushErrorPublication()
    let todoParsingError = api.lastError
    let validList = await listBeforeParsing.value
    await flushErrorPublication()
    verify(malformedTodos == nil && validList?.first?.id == "visible" &&
           todoParsingError?.contains("todo 响应格式错误") == true && api.lastError == todoParsingError &&
           HabiticaFixtureProtocol.calls.count == 2,
           "an earlier list success preserves a newer todo parsing error")

    let parsingOrder = account("parsing-versus-parsing")
    HabiticaFixtureProtocol.respond { request in
        if request.url!.query?.contains("type=habits") == true {
            return .init(body: ["data": ["unexpected": true]], delay: 0.15)
        }
        return .init(body: ["data": ["unexpected": true]])
    }
    let oldMalformedList = Task { await api.fetchTaskList(type: "habits", settings: parsingOrder) }
    await waitForDispatch()
    _ = await api.fetchTopThreeTodos(settings: parsingOrder)
    await flushErrorPublication()
    let newerParsingError = api.lastError
    _ = await oldMalformedList.value
    await flushErrorPublication()
    verify(newerParsingError?.contains("todo 响应格式错误") == true &&
           api.lastError == newerParsingError && HabiticaFixtureProtocol.calls.count == 2,
           "an older malformed response cannot replace a newer parsing error")

    let refreshed = account("new-refresh")
    HabiticaFixtureProtocol.respond { _ in .init(status: 500) }
    _ = await api.scoreTask(taskId: "failed-score", direction: "up", settings: refreshed)
    let hadRefreshError = api.lastError != nil
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": [["id": "fresh", "text": "Refreshed"]]]) }
    let refreshedItems = await api.fetchTaskList(type: "habits", settings: refreshed)
    await flushErrorPublication()
    verify(hadRefreshError && refreshedItems?.first?.id == "fresh" && api.lastError == nil &&
           HabiticaFixtureProtocol.calls.count == 1,
           "a newly dispatched successful manual list refresh clears an older error")

    let reauthenticated = account("new-profile-refresh")
    HabiticaFixtureProtocol.respond { _ in .init(status: 401) }
    _ = await api.scoreTask(taskId: "failed-authentication", direction: "up", settings: reauthenticated)
    let hadAuthenticationError = !api.isAuthenticated && api.lastError != nil
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": ["stats": ["gp": 14]]]) }
    await api.fetchUserData(settings: reauthenticated)
    await flushErrorPublication()
    verify(hadAuthenticationError && api.isAuthenticated && api.monies == 14 && api.lastError == nil &&
           HabiticaFixtureProtocol.calls.count == 1,
           "a newly dispatched successful profile refresh can restore authentication and clear the older error")

    precondition(failures.isEmpty, "response-order failures: \(failures.joined(separator: "; "))")
}

import Foundation

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    let api = HabiticaAPI.shared

    let valid = fixtureAccount("task-list-valid")
    HabiticaFixtureProtocol.respond { _ in
        .init(body: ["data": [["id": "habit", "text": "Read", "notes": "One chapter", "value": -2.5,
                                "completed": true, "up": false, "down": true, "isDue": false]]])
    }
    let habits = await api.fetchTaskList(type: "dailys", settings: valid)
    checkHabitica(habits?.count == 1 && habits?.first?.id == "habit" && habits?.first?.text == "Read" &&
                  habits?.first?.notes == "One chapter" && habits?.first?.value == -2.5 &&
                  habits?.first?.completed == true && habits?.first?.canUp == false &&
                  habits?.first?.canDown == true && habits?.first?.isDue == false,
                  "a valid task list preserves the task and its optional fields")

    let empty = fixtureAccount("task-list-empty")
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": []]) }
    let emptyList = await api.fetchTaskList(type: "dailys", settings: empty)
    checkHabitica(emptyList != nil && emptyList!.isEmpty,
                  "a legitimate empty task list is a successful result")

    for (index, reply) in [
        HabiticaFixtureProtocol.Reply(body: ["data": ["unexpected": true]]),
        .init(body: ["success": true]),
        .init(rawData: Data("[]".utf8)),
        .init(rawData: Data("<html>temporarily unavailable</html>".utf8)),
        .init(body: ["data": [["text": "Missing ID"]]]),
        .init(body: ["data": [["id": "", "text": "Empty ID"]]]),
        .init(body: ["data": [["id": "missing-text"]]]),
        .init(body: ["data": [["id": "duplicate", "text": "First"], ["id": "duplicate", "text": "Second"]]]),
        .init(body: ["data": [["id": "valid", "text": "Valid"], ["id": "invalid"]]])
    ].enumerated() {
        let account = fixtureAccount("task-list-malformed-\(index)")
        HabiticaFixtureProtocol.respond { _ in reply }
        let result = await api.fetchTaskList(type: "habits", settings: account)
        checkHabitica(result == nil,
                      "malformed task-list response \(index) is a failure rather than a successful empty or partial list")
    }

    for status in [401, 500] {
        let account = fixtureAccount("task-list-http-\(status)")
        HabiticaFixtureProtocol.respond { _ in .init(status: status) }
        let result = await api.fetchTaskList(type: "dailys", settings: account)
        checkHabitica(result == nil, "HTTP \(status) returns a failed task-list result")
    }

    let offline = fixtureAccount("task-list-offline")
    HabiticaFixtureProtocol.respond { _ in .init(error: URLError(.notConnectedToInternet)) }
    let offlineList = await api.fetchTaskList(type: "habits", settings: offline)
    checkHabitica(offlineList == nil && api.lastError?.contains("网络错误") == true,
                  "an offline transport failure returns a failed task-list result")

    let concurrent = fixtureAccount("task-list-unrelated-error")
    HabiticaFixtureProtocol.respond { request in
        if request.httpMethod == "POST" { return .init(status: 429, headers: ["Retry-After": "60"]) }
        return .init(body: ["data": [["id": "available", "text": "Already loaded"]]], delay: 0.1)
    }
    let loading = Task { await api.fetchTaskList(type: "habits", settings: concurrent) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    _ = await api.scoreTask(taskId: "other-task", direction: "up", settings: concurrent)
    let successfulList = await loading.value
    checkHabitica(successfulList?.first?.id == "available" && api.lastError?.contains("HTTP 429") == true,
                  "a successful list remains usable while an unrelated request has a shared error")
}

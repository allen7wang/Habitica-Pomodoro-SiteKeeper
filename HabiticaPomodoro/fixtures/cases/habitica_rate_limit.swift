import Foundation

func response(_ status: Int = 200, _ headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://habitica.fixture.invalid/api/v3/user")!,
                    statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}
let serverDate = "Thu, 05 Nov 2026 08:00:00 GMT"
let wallDate = ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z")!
var local = HabiticaRequestBudget()
for _ in 0..<HabiticaRequestBudget.localLimit { precondition(local.reserve(at: 100) == 0) }
checkHabitica(local.reserve(at: 100) == 60 && local.reserve(at: 159) == 1 && local.reserve(at: 160) == 0,
              "rolling budget rejects excess requests and reopens after 60 seconds")

var remote = HabiticaRequestBudget()
remote.observe(response(200, ["Date": serverDate, "X-RateLimit-Remaining": "1",
    "X-RateLimit-Reset": "Thu Nov 05 2026 08:01:00 GMT+0000 (Coordinated Universal Time)"]),
    at: 100, date: wallDate.addingTimeInterval(86400))
checkHabitica(remote.reserve(at: 100) == 0 && remote.reserve(at: 100) == 61 && remote.reserve(at: 161) == 0,
              "server allowance and JavaScript reset dates work despite local clock skew")

var fractional = HabiticaRequestBudget()
fractional.observe(response(429, ["Retry-After": "2.5"]), at: 100, date: wallDate)
checkHabitica(fractional.reserve(at: 100) == 3.5 && fractional.received429 && fractional.reserve(at: 104) == 0,
              "fractional Retry-After blocks dispatch and expires without replay")
var dated = HabiticaRequestBudget()
dated.observe(response(429, ["Date": serverDate, "Retry-After": "Thu, 05 Nov 2026 08:00:10 GMT"]),
              at: 100, date: wallDate.addingTimeInterval(-86400))
checkHabitica(dated.reserve(at: 100) == 11, "HTTP-date Retry-After uses server time")
var epoch = HabiticaRequestBudget()
epoch.observe(response(429, ["X-RateLimit-Reset": String(wallDate.timeIntervalSince1970 + 10)]), at: 100, date: wallDate)
checkHabitica(epoch.reserve(at: 100) == 11, "epoch reset is honored when Retry-After is absent")
var fallback = HabiticaRequestBudget()
fallback.observe(response(429, ["Retry-After": "garbage", "X-RateLimit-Reset": "garbage"]), at: 100, date: wallDate)
checkHabitica(fallback.reserve(at: 100) == 61, "malformed or missing cooldown headers use a one-minute fallback")
var reordered = HabiticaRequestBudget()
reordered.observe(response(200, ["X-RateLimit-Remaining": "2"]), at: 100, date: wallDate)
reordered.observe(response(200, ["X-RateLimit-Remaining": "29"]), at: 100, date: wallDate)
precondition(reordered.reserve(at: 100) == 0 && reordered.reserve(at: 100) == 0)
checkHabitica(reordered.reserve(at: 100) > 0, "out-of-order responses cannot replenish a window")

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    let api = HabiticaAPI.shared
    let limited = fixtureAccount("429")
    api.isAuthenticated = true
    HabiticaFixtureProtocol.respond { _ in .init(status: 429, headers: ["Retry-After": "60"]) }
    await api.fetchUserData(settings: limited)
    checkHabitica(api.isAuthenticated && api.lastError?.contains("HTTP 429") == true &&
                  api.lastError?.contains("Network error") == false,
                  "HTTP 429 preserves authentication and its actionable cooldown message")
    _ = await api.fetchTasks(type: "habits", settings: limited)
    let blockedScore = await api.scoreTask(taskId: "score", direction: "up", settings: limited)
    await api.fetchUserData(settings: limited)
    checkHabitica(blockedScore == nil && HabiticaFixtureProtocol.calls.count == 1,
                  "all features share cooldown and scoring is never queued or replayed")
    var rotated = limited
    rotated.apiToken = "rotated-synthetic-token"
    SettingsManager.shared.settings = rotated
    _ = await api.fetchTasks(type: "dailys", settings: rotated)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1, "token rotation does not bypass the same account budget")

    for (index, headers) in [
        ["Retry-After": "1e30"],
        ["Retry-After": String(Double(Int.max))],
        ["Retry-After": String(Double.greatestFiniteMagnitude)],
        ["X-RateLimit-Reset": "1e30"]
    ].enumerated() {
        let excessive = fixtureAccount("excessive-delay-\(index)")
        HabiticaFixtureProtocol.respond { _ in .init(status: 429, headers: headers) }
        await api.fetchUserData(settings: excessive)
        _ = await api.fetchTasks(type: "habits", settings: excessive)
        // The uptime addition/subtraction can round the Int.max boundary down into
        // Int's representable range. Both a finite countdown and the fallback are safe.
        let safeMessage = api.lastError?.contains("等待时间过长") == true ||
            (index == 1 && api.lastError?.contains("秒后重试") == true)
        checkHabitica(HabiticaFixtureProtocol.calls.count == 1 &&
                      api.lastError?.contains("HTTP 429") == true &&
                      safeMessage,
                      "oversized cooldown header \(index) remains enforced and displays without integer overflow")
    }

    let concurrent = fixtureAccount("late-success")
    api.monies = 0
    api.isAuthenticated = false
    HabiticaFixtureProtocol.respond { request in
        if request.url!.path == "/api/v3/user" || request.url!.path == "/api/v3/user/" {
            return .init(body: ["data": ["stats": ["gp": 2]]], delay: 0.1)
        }
        return .init(status: 429, headers: ["Retry-After": "60"])
    }
    let slowProfile = Task { await api.fetchUserData(settings: concurrent) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    _ = await api.fetchTasks(type: "habits", settings: concurrent)
    await slowProfile.value
    checkHabitica(api.isAuthenticated && api.monies == 2 && api.lastError?.contains("HTTP 429") == true,
                  "a late successful profile cannot erase a newer shared cooldown error")

    let allowance = fixtureAccount("remaining")
    HabiticaFixtureProtocol.respond { _ in .init(headers: ["X-RateLimit-Remaining": "0"]) }
    _ = await api.fetchTasks(type: "habits", settings: allowance)
    _ = await api.scoreHabit(taskId: "blocked", direction: "up", settings: allowance)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1,
                  "a server allowance of zero blocks the next feature before a 429 occurs")

    let reads = fixtureAccount("coalesced")
    HabiticaFixtureProtocol.respond { _ in .init(delay: 0.05) }
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 { group.addTask { _ = await api.fetchTasks(type: "habits", settings: reads) } }
    }
    checkHabitica(HabiticaFixtureProtocol.calls.count == 1 && api.lastError == nil,
                  "concurrent identical reads share one HTTP request and another account is independent")
    let mutations = fixtureAccount("mutations")
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": ["gp": 1]]) }
    async let first = api.scoreHabit(taskId: "same", direction: "up", settings: mutations)
    async let second = api.scoreHabit(taskId: "same", direction: "up", settings: mutations)
    _ = await (first, second)
    checkHabitica(HabiticaFixtureProtocol.calls.count == 2, "distinct scoring actions are not coalesced")

    let fresh = fixtureAccount("read-after-write")
    var version = "before"
    HabiticaFixtureProtocol.respond { request in
        if request.httpMethod == "POST" { version = "after"; return .init(body: ["data": ["gp": 1]]) }
        return .init(body: ["data": [["id": "item", "text": version]]], delay: 0.1)
    }
    let oldRead = Task { await api.fetchTasks(type: "habits", settings: fresh) }
    while HabiticaFixtureProtocol.calls.isEmpty { await Task.yield() }
    _ = await api.scoreHabit(taskId: "item", direction: "up", settings: fresh)
    let verified = await api.fetchTasks(type: "habits", settings: fresh)
    let old = await oldRead.value
    checkHabitica(old.first?.text == "before" && verified.first?.text == "after" &&
                  HabiticaFixtureProtocol.calls.count == 3,
                  "post-write verification never coalesces with a pre-write read")

    let burst = fixtureAccount("burst")
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": ["gp": 1]]) }
    for index in 0..<HabiticaRequestBudget.localLimit {
        _ = await api.scoreHabit(taskId: "\(index)", direction: "up", settings: burst)
    }
    let overflow = await api.scoreHabit(taskId: "overflow", direction: "up", settings: burst)
    checkHabitica(overflow == nil && HabiticaFixtureProtocol.calls.count == HabiticaRequestBudget.localLimit &&
                  api.lastError?.contains("秒后重试") == true, "production transport enforces the shared rolling ceiling")

    let cancellation = fixtureAccount("cancelled")
    HabiticaFixtureProtocol.respond { _ in .init() }
    let cancelled = Task { @MainActor in await api.scoreHabit(taskId: "cancelled", direction: "up", settings: cancellation) }
    cancelled.cancel()
    _ = await cancelled.value
    _ = fixtureAccount("different-owner")
    _ = await api.scoreHabit(taskId: "stale", direction: "up", settings: cancellation)
    checkHabitica(HabiticaFixtureProtocol.calls.isEmpty, "cancelled and stale-account writes never dispatch")

    let missing = fixtureAccount("404")
    HabiticaFixtureProtocol.respond { _ in .init(status: 404) }
    let removed = await api.deleteTodo(taskId: "already-gone", settings: missing)
    checkHabitica(removed && api.lastError == nil, "DELETE 404 acknowledges an already absent task")
    await api.fetchUserData(settings: missing)
    checkHabitica(api.lastError?.contains("HTTP 404") == true, "GET 404 remains an HTTP error rather than a network error")
    let unauthorized = fixtureAccount("401")
    api.isAuthenticated = true
    HabiticaFixtureProtocol.respond { _ in .init(status: 401) }
    await api.fetchUserData(settings: unauthorized)
    checkHabitica(!api.isAuthenticated && api.lastError?.contains("认证失败") == true,
                  "a real 401 still invalidates authentication")
}

import Foundation
import Combine

@MainActor
func checkDispatchReentry(_ name: String, createsTask: Bool, clearsUser: Bool) async {
    let api = HabiticaAPI.shared
    let original = fixtureAccount("dispatch-reentry-\(name)")
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": [["id": "current", "text": "Current account"]]]) }
    var reentered = false
    let subscription = api.$lastError.dropFirst().sink { _ in
        guard !reentered else { return }
        reentered = true
        var replacement = original
        replacement.uid = clearsUser ? "" : original.uid + "-B"
        SettingsManager.shared.settings = replacement
    }

    let rejected: Bool
    if createsTask {
        let result = await api.createTodo(text: "Must not dispatch", notes: "Synthetic", tagIds: [], settings: original)
        if case .notCreated = result { rejected = true } else { rejected = false }
    } else {
        rejected = await api.fetchTaskList(type: "habits", settings: original) == nil
    }
    subscription.cancel()
    checkHabitica(reentered && rejected && HabiticaFixtureProtocol.calls.isEmpty &&
                  SettingsManager.shared.settings.uid != original.uid,
                  "\(name) feedback subscriber changes identity synchronously and prevents the retired request from dispatching")

    var current = SettingsManager.shared.settings
    if current.uid.isEmpty { current.uid = original.uid + "-reconfigured" }
    SettingsManager.shared.settings = current
    let recovered = await api.fetchTaskList(type: "habits", settings: current)
    checkHabitica(recovered?.first?.id == "current" && HabiticaFixtureProtocol.calls.count == 1 &&
                  HabiticaFixtureProtocol.calls.first?.value(forHTTPHeaderField: "x-api-user") == current.uid,
                  "\(name) current credentials can dispatch normally after the reentrant subscriber is removed")
}

@MainActor
func checkProfilePublicationReentry(_ field: String) async {
    let api = HabiticaAPI.shared
    let original = fixtureAccount("profile-publication-reentry-\(field)")
    api.monies = 0
    api.exp = 0
    api.hp = 0
    api.isAuthenticated = false
    HabiticaFixtureProtocol.respond { _ in .init(body: ["data": ["stats": ["gp": 11, "exp": 22, "hp": 33]]]) }

    let publication: AnyPublisher<Bool, Never>
    switch field {
    case "monies": publication = api.$monies.map { $0 == 11 }.eraseToAnyPublisher()
    case "exp": publication = api.$exp.map { $0 == 22 }.eraseToAnyPublisher()
    case "hp": publication = api.$hp.map { $0 == 33 }.eraseToAnyPublisher()
    case "isAuthenticated": publication = api.$isAuthenticated.eraseToAnyPublisher()
    default: preconditionFailure("unknown profile publication field")
    }
    var reentered = false
    let subscription = publication.dropFirst().sink { accepted in
        guard accepted, !reentered else { return }
        reentered = true
        var replacement = original
        replacement.uid += "-B"
        SettingsManager.shared.settings = replacement
    }
    await api.fetchUserData(settings: original)
    subscription.cancel()
    checkHabitica(reentered && SettingsManager.shared.settings.uid != original.uid &&
                  api.monies == 0 && api.exp == 0 && api.hp == 0 && !api.isAuthenticated &&
                  HabiticaFixtureProtocol.calls.count == 1,
                  "reentry during \(field) publication cannot leave retired profile stats or authentication in the new account")

    let current = SettingsManager.shared.settings
    await api.fetchUserData(settings: current)
    checkHabitica(api.monies == 11 && api.exp == 22 && api.hp == 33 && api.isAuthenticated &&
                  HabiticaFixtureProtocol.calls.count == 2 &&
                  HabiticaFixtureProtocol.calls.last?.value(forHTTPHeaderField: "x-api-user") == current.uid,
                  "after \(field) reentry the current account can refresh its own complete profile normally")
}

@MainActor
func checkErrorPublicationReentry() async {
    let api = HabiticaAPI.shared
    let original = fixtureAccount("error-publication-reentry")
    api.lastError = nil
    HabiticaFixtureProtocol.respond { request in
        request.httpMethod == "POST" ? .init(status: 500)
            : .init(body: ["data": ["stats": ["gp": 7, "exp": 8, "hp": 9]]])
    }
    var reentered = false
    let subscription = api.$lastError.dropFirst().sink { message in
        guard message?.contains("500") == true, !reentered else { return }
        reentered = true
        var replacement = original
        replacement.uid += "-B"
        SettingsManager.shared.settings = replacement
    }
    _ = await api.scoreHabit(taskId: "rejected-old-account-score", direction: "up", settings: original)
    subscription.cancel()
    checkHabitica(reentered && SettingsManager.shared.settings.uid != original.uid &&
                  api.lastError == nil && HabiticaFixtureProtocol.calls.count == 1,
                  "an account switch inside error publication cannot leave the retired request's error in the new account")

    let current = SettingsManager.shared.settings
    await api.fetchUserData(settings: current)
    checkHabitica(api.lastError == nil && api.isAuthenticated && api.monies == 7 &&
                  HabiticaFixtureProtocol.calls.count == 2 &&
                  HabiticaFixtureProtocol.calls.last?.value(forHTTPHeaderField: "x-api-user") == current.uid,
                  "the current account can refresh normally after the error subscriber is removed")
}

HabiticaAPI.isolatedURLProtocols = [HabiticaFixtureProtocol.self]
runHabiticaFixture {
    await checkDispatchReentry("GET switches account", createsTask: false, clearsUser: false)
    await checkDispatchReentry("GET clears User ID", createsTask: false, clearsUser: true)
    await checkDispatchReentry("POST switches account", createsTask: true, clearsUser: false)
    await checkDispatchReentry("POST clears User ID", createsTask: true, clearsUser: true)
    for field in ["monies", "exp", "hp", "isAuthenticated"] {
        await checkProfilePublicationReentry(field)
    }
    await checkErrorPublicationReentry()
}

import Foundation

// Every URL is intercepted, including an unexpected one. No real account or server is used.
final class HabiticaFixtureProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: [String: Any] = ["success": true, "data": []]
        var delay: TimeInterval = 0
    }
    private static let lock = NSLock()
    private static var handler: (URLRequest) -> Reply = { _ in Reply() }
    private static var recorded: [URLRequest] = []
    private let deliveryLock = NSRecursiveLock()
    private var stopped = false

    static var calls: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    static func respond(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        recorded = []
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let reply = Self.handler(request)
        Self.lock.unlock()
        let deliver = {
            self.deliveryLock.lock(); defer { self.deliveryLock.unlock() }
            guard !self.stopped else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: reply.body))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver) }
        else { deliver() }
    }
    override func stopLoading() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        stopped = true
    }
}

@MainActor
func fixtureAccount(_ name: String) -> UserSettings {
    var settings = UserSettings()
    settings.connectHabitica = true
    settings.uid = "fixture-\(name)"
    settings.apiToken = "synthetic-token"
    settings.developerServerUrl = "https://habitica.fixture.invalid/api/v3/"
    SettingsManager.shared.settings = settings
    return settings
}

func checkHabitica(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS \(label)")
}

func runHabiticaFixture(_ body: @escaping @MainActor () async -> Void) {
    var finished = false
    Task { @MainActor in
        await body()
        finished = true
    }
    let deadline = Date().addingTimeInterval(20)
    while !finished && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(finished, "async fixture timed out")
}

import Foundation
import UserNotifications

// Fixture compilation ONLY: retain real request/content value objects but shadow
// the delivery transport. No OS permission, scheduling, or notification delivery.
final class UNUserNotificationCenter {
    private static let transport = UNUserNotificationCenter()
    private(set) var requests: [UNNotificationRequest] = []
    static func current() -> UNUserNotificationCenter { transport }
    func add(_ request: UNNotificationRequest, withCompletionHandler completion: ((Error?) -> Void)? = nil) {
        requests.append(request)
        completion?(nil)
    }
}

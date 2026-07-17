import UserNotifications

@MainActor
protocol UserNotificationCenterClient: AnyObject {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func deliveredRequestIdentifiers() async -> Set<String>
    func removePendingRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
final class SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredRequestIdentifiers() async -> Set<String> {
        let notifications = await center.deliveredNotifications()
        return Set(notifications.map(\.request.identifier))
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
final class DisabledUserNotificationCenterClient: UserNotificationCenterClient {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func setCategories(_ categories: Set<UNNotificationCategory>) {}
    func add(_ request: UNNotificationRequest) async throws {}
    func pendingRequests() async -> [UNNotificationRequest] { [] }
    func deliveredRequestIdentifiers() async -> Set<String> { [] }
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
}

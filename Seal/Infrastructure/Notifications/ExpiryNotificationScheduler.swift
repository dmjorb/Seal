import Foundation
import UserNotifications

@MainActor
final class ExpiryNotificationScheduler {
    private let center: UNUserNotificationCenter
    private let planner: ExpiryNotificationPlanner
    private let identifierPrefix = "com.mjorb.seal.expiry."

    init(
        center: UNUserNotificationCenter = .current(),
        planner: ExpiryNotificationPlanner = ExpiryNotificationPlanner()
    ) {
        self.center = center
        self.planner = planner
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func reschedule(
        apps: [AppRecord],
        enabled: Bool,
        leadHours: Int
    ) async throws {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        guard enabled else { return }

        for plan in planner.plans(for: apps, leadHours: leadHours) {
            let content = UNMutableNotificationContent()
            content.title = "到期"
            content.body = "\(plan.appName) 到期"
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: plan.fireDate
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + plan.appID.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
            )
            try await center.add(request)
        }
    }
}

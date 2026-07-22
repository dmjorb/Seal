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
        leadHours: Int = NotificationPreferences.fixedLeadHours
    ) async throws {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        guard enabled else { return }

        for plan in planner.plans(for: apps, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = "\(plan.appName) 即将到期"
            let time = Self.timeFormatter.string(from: plan.expiryDate)
            content.body = plan.isSeal
                ? "明天 \(time) 到期，请及时续签。"
                : "明天 \(time) 到期，打开 Seal 续签。"
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

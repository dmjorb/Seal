import Foundation
@preconcurrency import UserNotifications

protocol ExpiryNotificationCenter: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func add(_ request: UNNotificationRequest) async throws
}

final class SystemExpiryNotificationCenter: ExpiryNotificationCenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}

enum ExpiryNotificationSchedulingResult: Equatable, Sendable {
    case applied
    case denied
    case superseded
}

enum ExpiryNotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

struct ExpiryNotificationStatusSnapshot: Equatable, Sendable {
    let authorization: ExpiryNotificationAuthorizationState
    let pendingCount: Int
    let nextFireDate: Date?

    static let unknown = ExpiryNotificationStatusSnapshot(
        authorization: .unknown,
        pendingCount: 0,
        nextFireDate: nil
    )
}

@MainActor
protocol ExpiryNotificationScheduling: AnyObject {
    func setEnabled(
        _ enabled: Bool,
        apps: [AppRecord],
        leadHours: Int
    ) async throws -> ExpiryNotificationSchedulingResult

    func reschedule(
        apps: [AppRecord],
        enabled: Bool,
        leadHours: Int
    ) async throws

    func statusSnapshot() async -> ExpiryNotificationStatusSnapshot
}

extension ExpiryNotificationScheduling {
    func statusSnapshot() async -> ExpiryNotificationStatusSnapshot { .unknown }
}

@MainActor
final class ExpiryNotificationScheduler: ExpiryNotificationScheduling {
    private let center: any ExpiryNotificationCenter
    private let planner: ExpiryNotificationPlanner
    private let identifierPrefix = "com.mjorb.seal.expiry."
    private var generation = 0

    init(
        center: any ExpiryNotificationCenter = SystemExpiryNotificationCenter(),
        planner: ExpiryNotificationPlanner = ExpiryNotificationPlanner()
    ) {
        self.center = center
        self.planner = planner
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func statusSnapshot() async -> ExpiryNotificationStatusSnapshot {
        let authorization = Self.authorizationState(from: await center.authorizationStatus())
        let requests = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
        let nextFireDate = requests
            .compactMap { request in
                (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            }
            .min()
        return ExpiryNotificationStatusSnapshot(
            authorization: authorization,
            pendingCount: requests.count,
            nextFireDate: nextFireDate
        )
    }
    func setEnabled(
        _ enabled: Bool,
        apps: [AppRecord],
        leadHours: Int = NotificationPreferences.fixedLeadHours
    ) async throws -> ExpiryNotificationSchedulingResult {
        generation += 1
        let requestGeneration = generation

        if enabled {
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                guard isCurrent(requestGeneration) else { return .superseded }
                throw error
            }
            guard isCurrent(requestGeneration) else { return .superseded }
            if granted == false {
                let applied = try await replaceRequests(
                    apps: [],
                    enabled: false,
                    leadHours: leadHours,
                    requestGeneration: requestGeneration
                )
                guard isCurrent(requestGeneration) else { return .superseded }
                return applied ? .denied : .superseded
            }
        }

        let applied = try await replaceRequests(
            apps: apps,
            enabled: enabled,
            leadHours: leadHours,
            requestGeneration: requestGeneration
        )
        guard isCurrent(requestGeneration) else { return .superseded }
        return applied ? .applied : .superseded
    }

    func reschedule(
        apps: [AppRecord],
        enabled: Bool,
        leadHours: Int = NotificationPreferences.fixedLeadHours
    ) async throws {
        generation += 1
        let requestGeneration = generation
        _ = try await replaceRequests(
            apps: apps,
            enabled: enabled,
            leadHours: leadHours,
            requestGeneration: requestGeneration
        )
        guard isCurrent(requestGeneration) else { return }
    }

    private func replaceRequests(
        apps: [AppRecord],
        enabled: Bool,
        leadHours: Int,
        requestGeneration: Int
    ) async throws -> Bool {
        guard isCurrent(requestGeneration) else { return false }
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        guard isCurrent(requestGeneration) else { return false }

        await center.removePendingNotificationRequests(withIdentifiers: existing)
        guard isCurrent(requestGeneration) else { return false }
        guard enabled else { return true }

        var addedIdentifiers: [String] = []
        for plan in planner.plans(for: apps, leadHours: leadHours, now: Date()) {
            guard isCurrent(requestGeneration) else { return false }
            let request = makeRequest(for: plan, requestGeneration: requestGeneration)
            do {
                try await center.add(request)
            } catch {
                guard isCurrent(requestGeneration) else {
                    await center.removePendingNotificationRequests(
                        withIdentifiers: addedIdentifiers + [request.identifier]
                    )
                    guard isCurrent(requestGeneration) else { return false }
                    return false
                }
                await center.removePendingNotificationRequests(withIdentifiers: addedIdentifiers)
                guard isCurrent(requestGeneration) else { return false }
                throw error
            }
            guard isCurrent(requestGeneration) else {
                await center.removePendingNotificationRequests(
                    withIdentifiers: addedIdentifiers + [request.identifier]
                )
                guard isCurrent(requestGeneration) else { return false }
                return false
            }
            addedIdentifiers.append(request.identifier)
        }
        return true
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        requestGeneration == generation && Task.isCancelled == false
    }

    private func makeRequest(
        for plan: ExpiryNotificationPlan,
        requestGeneration: Int
    ) -> UNNotificationRequest {
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
        return UNNotificationRequest(
            identifier: identifierPrefix
                + "\(requestGeneration)."
                + plan.appID.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )
    }

    private static func authorizationState(
        from status: UNAuthorizationStatus
    ) -> ExpiryNotificationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

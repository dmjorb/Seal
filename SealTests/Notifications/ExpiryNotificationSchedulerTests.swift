import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import Seal

@MainActor
struct ExpiryNotificationSchedulerTests {
    @Test
    func olderEnableCannotAddAfterNewerDisableWhileAuthorizationWaits() async throws {
        let center = ControllableNotificationCenter()
        await center.holdAuthorization()
        let scheduler = ExpiryNotificationScheduler(center: center)
        let app = makeApp()

        let enable = Task {
            try await scheduler.setEnabled(true, apps: [app])
        }
        await center.waitUntilAuthorizationRequested()

        _ = try await scheduler.setEnabled(false, apps: [app])
        await center.resolveAuthorization(granted: true)
        _ = try await enable.value
        let identifiers = await center.pendingIdentifiers()

        #expect(identifiers.isEmpty)
    }

    @Test
    func staleAddThatFinishesAfterDisableIsRemoved() async throws {
        let center = ControllableNotificationCenter()
        await center.allowAuthorization(granted: true)
        await center.holdAdds()
        let scheduler = ExpiryNotificationScheduler(center: center)
        let app = makeApp()

        let enable = Task {
            try await scheduler.setEnabled(true, apps: [app])
        }
        await center.waitUntilAddStarted()

        _ = try await scheduler.setEnabled(false, apps: [app])
        await center.releaseAdds()
        _ = try await enable.value
        let identifiers = await center.pendingIdentifiers()

        #expect(identifiers.isEmpty)
    }

    private func makeApp() -> AppRecord {
        let now = Date()
        return AppRecord(
            originalBundleIdentifier: "com.example.notification-race",
            name: "Notification Race",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: now.addingTimeInterval(48 * 3_600),
            ipaRelativePath: "Apps/notification-race/Original.ipa",
            importedAt: now
        )
    }
}

private actor ControllableNotificationCenter: ExpiryNotificationCenter {
    private var requests: [String: UNNotificationRequest] = [:]
    private var authorizationResult: Bool?
    private var authorizationContinuation: CheckedContinuation<Bool, Error>?
    private var authorizationRequested = false
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldAdds = false
    private var addContinuations: [CheckedContinuation<Void, Never>] = []
    private var addStarted = false
    private var addWaiters: [CheckedContinuation<Void, Never>] = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationResult == true ? .authorized : .notDetermined
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequested = true
        authorizationWaiters.forEach { $0.resume() }
        authorizationWaiters.removeAll()
        if let authorizationResult { return authorizationResult }
        return try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        Array(requests.values)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        identifiers.forEach { requests.removeValue(forKey: $0) }
    }

    func add(_ request: UNNotificationRequest) async throws {
        addStarted = true
        addWaiters.forEach { $0.resume() }
        addWaiters.removeAll()
        if shouldHoldAdds {
            await withCheckedContinuation { continuation in
                addContinuations.append(continuation)
            }
        }
        requests[request.identifier] = request
    }

    func holdAuthorization() {
        authorizationResult = nil
    }

    func allowAuthorization(granted: Bool) {
        authorizationResult = granted
    }

    func resolveAuthorization(granted: Bool) {
        authorizationResult = granted
        authorizationContinuation?.resume(returning: granted)
        authorizationContinuation = nil
    }

    func waitUntilAuthorizationRequested() async {
        guard authorizationRequested == false else { return }
        await withCheckedContinuation { authorizationWaiters.append($0) }
    }

    func holdAdds() {
        shouldHoldAdds = true
    }

    func waitUntilAddStarted() async {
        guard addStarted == false else { return }
        await withCheckedContinuation { addWaiters.append($0) }
    }

    func releaseAdds() {
        shouldHoldAdds = false
        addContinuations.forEach { $0.resume() }
        addContinuations.removeAll()
    }

    func pendingIdentifiers() -> [String] {
        Array(requests.keys).sorted()
    }
}

import Foundation
import Testing
@testable import Seal

@MainActor
struct SettingsNotificationFlowTests {
    @Test
    func newerToggleIntentCancelsTrackedWorkAndOwnsBusyState() async {
        let scheduler = ControllableSettingsNotificationScheduler()
        let defaults = UserDefaults(
            suiteName: "SettingsNotificationFlowTests.\(UUID().uuidString)"
        )!
        let preferences = NotificationPreferences(defaults: defaults)
        let viewModel = SettingsViewModel(
            notificationScheduler: scheduler,
            notificationPreferences: preferences,
            appStore: NotificationSettingsAppStore()
        )

        viewModel.submitNotificationsEnabled(true)
        await scheduler.waitUntilEnableStarted()
        #expect(viewModel.isNotificationOperationRunning)

        viewModel.submitNotificationsEnabled(false)
        await viewModel.waitForNotificationOperation()

        #expect(viewModel.notificationsEnabled == false)
        #expect(preferences.isEnabled == false)
        #expect(viewModel.isNotificationOperationRunning == false)

        scheduler.releaseEnable()
        await Task.yield()
        #expect(viewModel.notificationsEnabled == false)
    }
}

@MainActor
private final class ControllableSettingsNotificationScheduler: ExpiryNotificationScheduling {
    private var enableStarted = false
    private var enableStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var enableContinuation: CheckedContinuation<Void, Never>?

    func setEnabled(
        _ enabled: Bool,
        apps: [AppRecord],
        leadHours: Int
    ) async throws -> ExpiryNotificationSchedulingResult {
        guard enabled else { return .applied }
        enableStarted = true
        enableStartWaiters.forEach { $0.resume() }
        enableStartWaiters.removeAll()
        await withCheckedContinuation { enableContinuation = $0 }
        return .applied
    }

    func reschedule(apps: [AppRecord], enabled: Bool, leadHours: Int) async throws {}

    func waitUntilEnableStarted() async {
        guard enableStarted == false else { return }
        await withCheckedContinuation { enableStartWaiters.append($0) }
    }

    func releaseEnable() {
        enableContinuation?.resume()
        enableContinuation = nil
    }
}

private actor NotificationSettingsAppStore: AppStore {
    func fetchAll() -> [AppRecord] { [] }
    func save(_ record: AppRecord) {}
    func replaceImportedApp(_ record: AppRecord) -> [AppRecord] { [] }
    func delete(id: UUID) {}
}

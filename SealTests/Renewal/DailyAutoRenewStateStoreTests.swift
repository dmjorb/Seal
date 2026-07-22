import Foundation
import Testing
@testable import Seal

@MainActor
struct DailyAutoRenewStateStoreTests {
    @Test
    func runsOncePerLocalCalendarDay() {
        let defaults = makeDefaults()
        let store = DailyAutoRenewStateStore(defaults: defaults)
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 2_000_000_000)
        let key = store.dayKey(for: day, calendar: calendar)

        #expect(store.shouldRun(on: day, calendar: calendar))
        store.markCompleted(dayKey: key)
        #expect(store.shouldRun(on: day, calendar: calendar) == false)
        #expect(store.shouldRun(on: day.addingTimeInterval(86_400), calendar: calendar))
    }

    @Test
    func confirmsPendingSelfRenewalOnlyAfterEmbeddedExpiryAdvances() {
        let defaults = makeDefaults()
        let store = DailyAutoRenewStateStore(defaults: defaults)
        let appID = UUID()
        let oldExpiry = Date(timeIntervalSince1970: 2_000_100_000)
        store.markPendingSelfRenewal(
            dayKey: "2033-05-18",
            appID: appID,
            previousExpiry: oldExpiry
        )

        #expect(store.reconcilePendingSelfRenewal(currentExpiry: oldExpiry) == nil)
        #expect(store.shouldRun(on: Date(timeIntervalSince1970: 2_000_000_000)))

        let reconciliation = store.reconcilePendingSelfRenewal(
            currentExpiry: oldExpiry.addingTimeInterval(1)
        )
        #expect(
            reconciliation == DailyAutoRenewSelfReconciliation(
                dayKey: "2033-05-18",
                appID: appID,
                evidence: .embeddedExpiryAdvanced
            )
        )
        #expect(defaults.string(forKey: "lastAutoRenewDate") == nil)
        #expect(store.reconcilePendingSelfRenewal(currentExpiry: oldExpiry.addingTimeInterval(2)) == nil)
    }

    @Test
    func preinstallMetadataNeverConfirmsSelfReplacement() {
        let defaults = makeDefaults()
        let pendingAt = Date(timeIntervalSince1970: 2_000_000_000)
        let oldExpiry = pendingAt.addingTimeInterval(86_400)
        let newSignedExpiry = pendingAt.addingTimeInterval(7 * 86_400)
        let appID = UUID()
        let store = DailyAutoRenewStateStore(defaults: defaults)
        store.markPendingSelfRenewal(
            dayKey: "2033-05-18",
            appID: appID,
            previousExpiry: oldExpiry,
            previousProvisioningExpiry: oldExpiry,
            previousLastSignedAt: pendingAt.addingTimeInterval(-10),
            previousLastInstalledAt: pendingAt.addingTimeInterval(-10),
            pendingAt: pendingAt
        )

        let reconciliation = store.reconcilePendingSelfRenewal(
            currentExpiry: oldExpiry,
            currentProvisioningExpiry: newSignedExpiry,
            currentLastSignedAt: pendingAt.addingTimeInterval(1),
            currentLastInstalledAt: pendingAt.addingTimeInterval(2)
        )

        #expect(reconciliation == nil)
    }

    @Test
    func nilPreviousExpiryRequiresCurrentEmbeddedProfileToMatchSignedProfile() {
        let defaults = makeDefaults()
        let pendingAt = Date(timeIntervalSince1970: 2_000_000_000)
        let signedExpiry = pendingAt.addingTimeInterval(7 * 86_400)
        let appID = UUID()
        let store = DailyAutoRenewStateStore(defaults: defaults)
        store.markPendingSelfRenewal(
            dayKey: "2033-05-19",
            appID: appID,
            previousExpiry: nil,
            previousProvisioningExpiry: nil,
            pendingAt: pendingAt
        )

        #expect(
            store.reconcilePendingSelfRenewal(
                currentExpiry: signedExpiry.addingTimeInterval(-1),
                currentProvisioningExpiry: signedExpiry
            ) == nil
        )
        let reconciliation = store.reconcilePendingSelfRenewal(
            currentExpiry: signedExpiry,
            currentProvisioningExpiry: signedExpiry
        )
        #expect(reconciliation?.evidence == .embeddedExpiryAdvanced)
    }

    @Test
    func repeatedAttemptOnSameDayRefreshesPendingBaseline() {
        let defaults = makeDefaults()
        let store = DailyAutoRenewStateStore(defaults: defaults)
        let appID = UUID()
        let firstExpiry = Date(timeIntervalSince1970: 2_000_100_000)
        let secondExpiry = firstExpiry.addingTimeInterval(100)

        store.markPendingSelfRenewal(
            dayKey: "2033-05-19",
            appID: appID,
            previousExpiry: firstExpiry
        )
        store.markPendingSelfRenewal(
            dayKey: "2033-05-19",
            appID: appID,
            previousExpiry: secondExpiry
        )

        #expect(
            store.reconcilePendingSelfRenewal(
                currentExpiry: firstExpiry.addingTimeInterval(50)
            ) == nil
        )
        #expect(
            store.reconcilePendingSelfRenewal(
                currentExpiry: secondExpiry.addingTimeInterval(1)
            )?.evidence == .embeddedExpiryAdvanced
        )
    }

    @Test
    func selfReconciliationRetriesOnlyOtherUnfinishedAppAcrossRestart() async throws {
        let defaults = makeDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queueURL = directory.appending(path: "RefreshQueue.json")
        let dayKey = "2033-05-20"
        let accountID = UUID()
        let selfApp = makeInstalledApp(name: "Seal", accountID: accountID, isSeal: true)
        let otherApp = makeInstalledApp(name: "Other", accountID: accountID)
        let initialQueue = RefreshQueueStore(
            fileURL: queueURL,
            fileProtector: MarkerFileProtector()
        )
        _ = try await initialQueue.prepare(
            with: [
                RefreshQueueItem(appID: selfApp.id, accountID: accountID),
                RefreshQueueItem(appID: otherApp.id, accountID: accountID)
            ],
            sessionID: dayKey
        )
        try await initialQueue.markRunning(appID: selfApp.id)
        try await initialQueue.markFailed(appID: otherApp.id, errorCode: "SEAL-RENEW-500")

        let pendingAt = Date(timeIntervalSince1970: 2_000_000_000)
        let stateStore = DailyAutoRenewStateStore(defaults: defaults)
        let previousExpiry = pendingAt.addingTimeInterval(86_400)
        stateStore.markPendingSelfRenewal(
            dayKey: dayKey,
            appID: selfApp.id,
            previousExpiry: previousExpiry,
            pendingAt: pendingAt
        )
        let reconciliation = try #require(
            stateStore.reconcilePendingSelfRenewal(
                currentExpiry: previousExpiry.addingTimeInterval(1)
            )
        )

        let restartedQueue = RefreshQueueStore(
            fileURL: queueURL,
            fileProtector: MarkerFileProtector()
        )
        let appStore = DailyRenewalAppStore(records: [selfApp, otherApp])
        let signer = RecordingDailyRenewalSigner(records: [selfApp, otherApp])
        let coordinator = RenewalCoordinator(
            appStore: appStore,
            signingCoordinator: signer,
            queueStore: restartedQueue
        )

        let completedAfterSelf = try await coordinator.reconcilePendingSelfRenewal(reconciliation)
        #expect(completedAfterSelf == false)
        #expect(defaults.string(forKey: "lastAutoRenewDate") == nil)

        let result = try await coordinator.refreshAll(sessionID: dayKey) { _ in }
        let attemptedAppIDs = await signer.attemptedAppIDs()
        let completedAfterOther = try await coordinator.isBatchCompleted(sessionID: dayKey)
        #expect(result == BatchRefreshResult(total: 1, succeeded: 1, failed: 0))
        #expect(attemptedAppIDs == [otherApp.id])
        #expect(completedAfterOther)

        stateStore.markCompleted(dayKey: dayKey)
        #expect(defaults.string(forKey: "lastAutoRenewDate") == dayKey)
    }

    private func makeInstalledApp(
        name: String,
        accountID: UUID,
        isSeal: Bool = false
    ) -> AppRecord {
        AppRecord(
            originalBundleIdentifier: "com.example.\(name.lowercased())",
            name: name,
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: Date(timeIntervalSince1970: 2_000_100_000),
            accountID: accountID,
            ipaRelativePath: "Apps/\(name)/Original.ipa",
            isSeal: isSeal,
            importedAt: Date(timeIntervalSince1970: 1_999_000_000)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "DailyAutoRenewStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private actor DailyRenewalAppStore: AppStore {
    private var records: [AppRecord]

    init(records: [AppRecord]) {
        self.records = records
    }

    func fetchAll() -> [AppRecord] { records }

    func save(_ record: AppRecord) {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func replaceImportedApp(_ record: AppRecord) -> [AppRecord] { [] }
    func delete(id: UUID) { records.removeAll { $0.id == id } }
}

private actor RecordingDailyRenewalSigner: SigningCoordinating {
    private let records: [UUID: AppRecord]
    private var attempted: [UUID] = []

    init(records: [AppRecord]) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    func signAndInstall(
        appID: UUID,
        accountID: UUID,
        requestedBundleIdentifier: String?,
        selectedCertificateSerialNumber: String?,
        allowDroppingExtensions: Bool,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord {
        attempted.append(appID)
        return records[appID]!
    }

    func attemptedAppIDs() -> [UUID] { attempted }
}

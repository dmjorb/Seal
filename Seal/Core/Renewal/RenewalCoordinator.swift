import Foundation

struct BatchRefreshResult: Equatable, Sendable {
    let total: Int
    let succeeded: Int
    let failed: Int
}

enum BatchRefreshEvent: Sendable {
    case started(total: Int)
    case appProgress(index: Int, total: Int, app: AppRecord, stage: SigningStage)
    case appSucceeded(index: Int, total: Int, app: AppRecord)
    case appFailed(index: Int, total: Int, app: AppRecord, failure: ImportFailure)
}

actor RenewalCoordinator {
    private let appStore: any AppStore
    private let signingCoordinator: SigningCoordinator
    private let queueStore: RefreshQueueStore
    private let planner: RefreshPlanner

    init(
        appStore: any AppStore,
        signingCoordinator: SigningCoordinator,
        queueStore: RefreshQueueStore,
        planner: RefreshPlanner = RefreshPlanner()
    ) {
        self.appStore = appStore
        self.signingCoordinator = signingCoordinator
        self.queueStore = queueStore
        self.planner = planner
    }

    func pendingCount() async throws -> Int {
        try await queueStore.load().filter { $0.state != .completed }.count
    }

    func refreshAll(
        progress: @Sendable (BatchRefreshEvent) async -> Void
    ) async throws -> BatchRefreshResult {
        let apps = try await appStore.fetchAll()
        let queue = planner.makeQueue(apps: apps)
        try await queueStore.replace(with: queue)
        return try await process(queue: queue, progress: progress)
    }

    func resume(
        progress: @Sendable (BatchRefreshEvent) async -> Void
    ) async throws -> BatchRefreshResult {
        let queue = try await queueStore.load().filter { $0.state != .completed }
        return try await process(queue: queue, progress: progress)
    }

    func refreshDue(
        leadHours: Int,
        enforceCooldown: Bool = false,
        progress: @Sendable (BatchRefreshEvent) async -> Void
    ) async throws -> BatchRefreshResult {
        let apps = try await appStore.fetchAll()
        let now = Date()
        let cutoff = now.addingTimeInterval(TimeInterval(max(1, leadHours)) * 3_600)
        let queue = apps
            .filter { app in
                guard app.state == .installed,
                      app.accountID != nil,
                      let expiryDate = app.expiryDate else { return false }
                return expiryDate <= cutoff
            }
            .filter { app in
                enforceCooldown == false || shouldAttemptAutomaticRenewal(for: app, now: now)
            }
            .sorted { lhs, rhs in
                let lhsExpiry = lhs.expiryDate ?? .distantPast
                let rhsExpiry = rhs.expiryDate ?? .distantPast
                if lhs.isSeal != rhs.isSeal { return lhs.isSeal }
                if lhsExpiry != rhsExpiry { return lhsExpiry < rhsExpiry }
                return lhs.importedAt < rhs.importedAt
            }
            .compactMap { app -> RefreshQueueItem? in
                guard let accountID = app.accountID else { return nil }
                return RefreshQueueItem(appID: app.id, accountID: accountID)
            }
        if enforceCooldown {
            markAutomaticRenewalAttempts(queue.map(\.appID), at: now)
        }
        try await queueStore.replace(with: queue)
        return try await process(
            queue: queue,
            isAutomaticRenewal: enforceCooldown,
            progress: progress
        )
    }


    private func process(
        queue: [RefreshQueueItem],
        isAutomaticRenewal: Bool = false,
        progress: @Sendable (BatchRefreshEvent) async -> Void
    ) async throws -> BatchRefreshResult {
        await progress(.started(total: queue.count))
        var succeeded = 0
        var failed = 0

        for (offset, item) in queue.enumerated() {
            do {
                try Task.checkCancellation()
                let apps = try await appStore.fetchAll()
                guard let app = apps.first(where: { $0.id == item.appID }) else {
                    throw ImportFailure(
                        title: "无法刷新应用",
                        reason: "应用记录不存在",
                        recovery: "重新导入 IPA",
                        code: "SEAL-RENEW-404"
                    )
                }
                try await queueStore.markRunning(appID: item.appID)
                let updated = try await signingCoordinator.signAndInstall(
                    appID: item.appID,
                    accountID: item.accountID,
                    requestedBundleIdentifier: app.preferredBundleIdentifier ?? app.mappedBundleIdentifier,
                    selectedCertificateSerialNumber: nil,
                    progress: { stage in
                        await progress(
                            .appProgress(
                                index: offset + 1,
                                total: queue.count,
                                app: app,
                                stage: stage
                            )
                        )
                    }
                )
                try await queueStore.markCompleted(appID: item.appID)
                succeeded += 1
                await progress(
                    .appSucceeded(
                        index: offset + 1,
                        total: queue.count,
                        app: updated
                    )
                )
            } catch is CancellationError {
                try? await queueStore.markPending(appID: item.appID)
                throw CancellationError()
            } catch let failure as ImportFailure {
                if isAutomaticRenewal {
                    markAutomaticRenewalFailure(appID: item.appID, at: Date())
                }
                try? await queueStore.markFailed(
                    appID: item.appID,
                    errorCode: failure.code
                )
                failed += 1
                let currentApps = try? await appStore.fetchAll()
                if let app = currentApps?.first(where: { $0.id == item.appID }) {
                    await progress(
                        .appFailed(
                            index: offset + 1,
                            total: queue.count,
                            app: app,
                            failure: failure
                        )
                    )
                }
            } catch {
                if isAutomaticRenewal {
                    markAutomaticRenewalFailure(appID: item.appID, at: Date())
                }
                let failure = ImportFailure(
                    title: "无法刷新应用",
                    reason: "签名或安装失败",
                    recovery: "重试",
                    code: "SEAL-RENEW-500"
                )
                try? await queueStore.markFailed(
                    appID: item.appID,
                    errorCode: failure.code
                )
                failed += 1
                let currentApps = try? await appStore.fetchAll()
                if let app = currentApps?.first(where: { $0.id == item.appID }) {
                    await progress(
                        .appFailed(
                            index: offset + 1,
                            total: queue.count,
                            app: app,
                            failure: failure
                        )
                    )
                }
            }
        }

        try? await queueStore.removeCompleted()
        return BatchRefreshResult(
            total: queue.count,
            succeeded: succeeded,
            failed: failed
        )
    }

    private func shouldAttemptAutomaticRenewal(for app: AppRecord, now: Date) -> Bool {
        let defaults = UserDefaults.standard
        let attemptKey = automaticRenewalAttemptKey(app.id)
        let failureKey = automaticRenewalFailureKey(app.id)
        let lastAttempt = defaults.double(forKey: attemptKey)
        if lastAttempt > 0, now.timeIntervalSince1970 - lastAttempt < 21_600 {
            return false
        }
        let lastFailure = defaults.double(forKey: failureKey)
        if lastFailure > 0, now.timeIntervalSince1970 - lastFailure < 86_400 {
            return false
        }
        return true
    }

    private func markAutomaticRenewalAttempts(_ appIDs: [UUID], at date: Date) {
        for appID in appIDs {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: automaticRenewalAttemptKey(appID))
        }
    }

    private func markAutomaticRenewalFailure(appID: UUID, at date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: automaticRenewalFailureKey(appID))
    }

    private func automaticRenewalAttemptKey(_ appID: UUID) -> String {
        "behavior.autoRenew.app.\(appID.uuidString).lastAttemptAt"
    }

    private func automaticRenewalFailureKey(_ appID: UUID) -> String {
        "behavior.autoRenew.app.\(appID.uuidString).lastFailureAt"
    }
}

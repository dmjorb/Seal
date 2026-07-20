import Foundation

struct RefreshPlanner: Sendable {
    func makeQueue(
        apps: [AppRecord],
        now: Date = Date()
    ) -> [RefreshQueueItem] {
        apps
            .filter { $0.state == .installed && $0.accountID != nil }
            .sorted { lhs, rhs in
                priority(for: lhs, now: now) < priority(for: rhs, now: now)
            }
            .compactMap { app in
                guard let accountID = app.accountID else { return nil }
                return RefreshQueueItem(appID: app.id, accountID: accountID)
            }
    }

    private func priority(for app: AppRecord, now: Date) -> Priority {
        let expiry = app.expiryDate ?? .distantPast
        let isUrgent = expiry.timeIntervalSince(now) < 86_400
        return Priority(
            group: app.isSeal ? 0 : (isUrgent ? 1 : 2),
            expiry: expiry,
            importedAt: app.importedAt
        )
    }
}

private struct Priority: Comparable {
    let group: Int
    let expiry: Date
    let importedAt: Date

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        if lhs.group != rhs.group { return lhs.group < rhs.group }
        if lhs.expiry != rhs.expiry { return lhs.expiry < rhs.expiry }
        return lhs.importedAt < rhs.importedAt
    }
}

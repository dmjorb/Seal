import Foundation

struct ExpiryNotificationPlan: Equatable, Sendable {
    let appID: UUID
    let appName: String
    let isSeal: Bool
    let fireDate: Date
    let expiryDate: Date
}

struct ExpiryNotificationPlanner: Sendable {
    func plans(
        for apps: [AppRecord],
        leadHours: Int = 24,
        now: Date = Date()
    ) -> [ExpiryNotificationPlan] {
        apps.compactMap { app in
            guard (app.state == .installed || app.isSeal),
                  let expiryDate = app.expiryDate,
                  expiryDate > now else { return nil }
            let requestedFireDate = expiryDate.addingTimeInterval(-24 * 3_600)
            guard requestedFireDate > now else { return nil }
            return ExpiryNotificationPlan(
                appID: app.id,
                appName: app.name,
                isSeal: app.isSeal,
                fireDate: requestedFireDate,
                expiryDate: expiryDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.isSeal != rhs.isSeal { return lhs.isSeal }
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
    }
}

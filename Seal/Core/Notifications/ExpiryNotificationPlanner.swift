import Foundation

struct ExpiryNotificationPlan: Equatable, Sendable {
    let appID: UUID
    let appName: String
    let fireDate: Date
    let expiryDate: Date
}

struct ExpiryNotificationPlanner: Sendable {
    func plans(
        for apps: [AppRecord],
        leadHours: Int,
        now: Date = Date()
    ) -> [ExpiryNotificationPlan] {
        apps.compactMap { app in
            guard app.state == .installed,
                  let expiryDate = app.expiryDate,
                  expiryDate > now else { return nil }
            let requestedFireDate = expiryDate.addingTimeInterval(
                -Double(max(1, leadHours)) * 3_600
            )
            return ExpiryNotificationPlan(
                appID: app.id,
                appName: app.name,
                fireDate: max(requestedFireDate, now.addingTimeInterval(60)),
                expiryDate: expiryDate
            )
        }
    }
}

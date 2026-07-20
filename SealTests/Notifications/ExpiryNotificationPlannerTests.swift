import Foundation
import Testing
@testable import Seal

struct ExpiryNotificationPlannerTests {
    @Test
    func schedulesInstalledAppsBeforeExpiration() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expiry = now.addingTimeInterval(48 * 3_600)
        let app = AppRecord(
            originalBundleIdentifier: "com.example.demo",
            name: "Demo",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: expiry,
            ipaRelativePath: "Apps/demo/Original.ipa",
            importedAt: now
        )

        let plans = ExpiryNotificationPlanner().plans(
            for: [app],
            leadHours: 24,
            now: now
        )

        #expect(plans.count == 1)
        #expect(plans[0].fireDate == now.addingTimeInterval(24 * 3_600))
    }

    @Test
    func skipsExpiredAndUnsignedApps() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = AppRecord(
            originalBundleIdentifier: "com.example.expired",
            name: "Expired",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: now.addingTimeInterval(-1),
            ipaRelativePath: "Apps/expired/Original.ipa",
            importedAt: now
        )
        var unsigned = expired
        unsigned.state = .preflightPassed
        unsigned.expiryDate = now.addingTimeInterval(86_400)

        #expect(
            ExpiryNotificationPlanner().plans(
                for: [expired, unsigned],
                leadHours: 24,
                now: now
            ).isEmpty
        )
    }
}

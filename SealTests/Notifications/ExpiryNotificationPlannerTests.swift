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
            leadHours: 144,
            now: now
        )

        #expect(plans.count == 1)
        #expect(plans[0].fireDate == now.addingTimeInterval(24 * 3_600))
        #expect(plans[0].isSeal == false)
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


    @Test
    func doesNotShiftA24HourReminderToAnotherTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let app = AppRecord(
            originalBundleIdentifier: "com.example.soon",
            name: "Soon",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: now.addingTimeInterval(12 * 3_600),
            ipaRelativePath: "Apps/soon/Original.ipa",
            importedAt: now
        )

        #expect(ExpiryNotificationPlanner().plans(for: [app], now: now).isEmpty)
    }

    @Test
    func putsSealReminderFirst() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expiry = now.addingTimeInterval(48 * 3_600)
        let regular = AppRecord(
            originalBundleIdentifier: "com.example.regular",
            name: "Regular",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: expiry.addingTimeInterval(-3_600),
            ipaRelativePath: "Apps/regular/Original.ipa",
            importedAt: now
        )
        let seal = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.signed",
            name: "Seal",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: expiry,
            ipaRelativePath: "Apps/seal/Original.ipa",
            isSeal: true,
            importedAt: now
        )

        let plans = ExpiryNotificationPlanner().plans(for: [regular, seal], now: now)

        #expect(plans.map(\.appID) == [seal.id, regular.id])
    }
}

import Foundation
import Testing
@testable import Seal

struct RefreshPlannerTests {
    @Test
    func placesSealBeforeUrgentAndRegularApps() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let accountID = UUID()
        let regular = app(
            name: "Regular",
            expiry: now.addingTimeInterval(5 * 86_400),
            accountID: accountID
        )
        let urgent = app(
            name: "Urgent",
            expiry: now.addingTimeInterval(3_600),
            accountID: accountID
        )
        let seal = app(
            name: "Seal",
            expiry: now.addingTimeInterval(6 * 86_400),
            accountID: accountID,
            isSeal: true
        )

        let queue = RefreshPlanner().makeQueue(
            apps: [regular, urgent, seal],
            now: now
        )

        #expect(queue.map(\.appID) == [seal.id, urgent.id, regular.id])
    }

    @Test
    func skipsAppsWithoutBoundAccounts() {
        let app = app(name: "Unsigned", expiry: nil, accountID: nil)

        #expect(RefreshPlanner().makeQueue(apps: [app]).isEmpty)
    }

    private func app(
        name: String,
        expiry: Date?,
        accountID: UUID?,
        isSeal: Bool = false
    ) -> AppRecord {
        AppRecord(
            originalBundleIdentifier: "com.example.\(name.lowercased())",
            name: name,
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: expiry,
            accountID: accountID,
            ipaRelativePath: "Apps/\(UUID().uuidString)/Original.ipa",
            isSeal: isSeal,
            importedAt: Date()
        )
    }
}

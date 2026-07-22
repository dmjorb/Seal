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
        let oldExpiry = Date(timeIntervalSince1970: 2_000_100_000)
        store.markPendingSelfRenewal(dayKey: "2033-05-18", previousExpiry: oldExpiry)

        store.reconcilePendingSelfRenewal(currentExpiry: oldExpiry)
        #expect(store.shouldRun(on: Date(timeIntervalSince1970: 2_000_000_000)))

        store.reconcilePendingSelfRenewal(currentExpiry: oldExpiry.addingTimeInterval(1))
        #expect(defaults.string(forKey: "lastAutoRenewDate") == "2033-05-18")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "DailyAutoRenewStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

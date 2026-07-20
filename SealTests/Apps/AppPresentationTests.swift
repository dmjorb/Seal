import Foundation
import Testing
@testable import Seal

struct AppPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    @Test
    func pendingAppsUseSigningPresentation() {
        let app = makeApp(state: .preflightPassed, expiryDate: nil)

        #expect(AppOperationPresentation(app: app, now: now).kind == .signing)
        #expect(AppOperationPresentation(app: app, now: now).sheetTitle == "签名应用")
        #expect(AppOperationPresentation(app: app, now: now).primaryAction == "签名并安装")
    }

    @Test
    func installedAppsUseNeutralRemainingDayPresentation() {
        let app = makeApp(
            state: .installed,
            expiryDate: now.addingTimeInterval(6 * 86_400 + 3_600)
        )
        let presentation = AppOperationPresentation(app: app, now: now)

        #expect(presentation.kind == .renewal)
        #expect(presentation.validity?.text == "剩余 6 天")
        #expect(presentation.validity?.tone == .neutral)
    }

    @Test
    func oneDayRemainingIsUrgentAndOrange() {
        let app = makeApp(
            state: .installed,
            expiryDate: now.addingTimeInterval(30 * 3_600)
        )
        let presentation = AppOperationPresentation(app: app, now: now)

        #expect(presentation.kind == .urgentRenewal)
        #expect(presentation.validity?.text == "剩余 1 天")
        #expect(presentation.validity?.tone == .warning)
        #expect(presentation.primaryAction == "立即续签")
    }

    @Test
    func expiredAppsRequireReinstallation() {
        let app = makeApp(
            state: .installed,
            expiryDate: now.addingTimeInterval(-60)
        )
        let presentation = AppOperationPresentation(app: app, now: now)

        #expect(presentation.kind == .expiredRenewal)
        #expect(presentation.validity?.text == "已过期")
        #expect(presentation.validity?.tone == .danger)
        #expect(presentation.primaryAction == "续签并重新安装")
    }

    @Test
    func importTimeUsesTodayAndYesterdayLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 18, hour: 12)
        )!
        let today = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 18, hour: 10, minute: 28)
        )!
        let yesterday = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 17, hour: 18, minute: 42)
        )!

        #expect(AppImportTimeFormatter.string(from: today, now: reference, calendar: calendar) == "今天 10:28")
        #expect(AppImportTimeFormatter.string(from: yesterday, now: reference, calendar: calendar) == "昨天 18:42")
    }

    private func makeApp(state: AppState, expiryDate: Date?) -> AppRecord {
        AppRecord(
            originalBundleIdentifier: "com.seal.example",
            name: "示例应用",
            version: "1.0.0",
            buildNumber: "1",
            size: 82_400_000,
            state: state,
            expiryDate: expiryDate,
            ipaRelativePath: "Apps/Example.ipa",
            importedAt: now
        )
    }
}

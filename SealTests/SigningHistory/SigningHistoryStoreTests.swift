import Foundation
import Testing
@testable import Seal

struct SigningHistoryStoreTests {
    @Test
    func storesNewestRecordsFirstAndFiltersByAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SigningHistoryStore(
            fileURL: directory.appending(path: "History.json"),
            maximumEntries: 10,
            fileProtector: MarkerFileProtector()
        )
        let accountA = UUID()
        let accountB = UUID()
        let older = SigningHistoryRecord(
            accountID: accountA,
            appID: UUID(),
            appName: "Old App",
            originalBundleIdentifier: "com.example.old",
            signedBundleIdentifier: nil,
            version: "1.0",
            buildNumber: "1",
            iconRelativePath: nil,
            accountDisplayName: "dev***er@icloud.com",
            teamID: "TEAM1",
            teamName: "Personal Team",
            certificateSerialNumber: nil,
            action: .sign,
            result: .success,
            signedAt: Date(timeIntervalSince1970: 100),
            expiryDate: Date(timeIntervalSince1970: 700),
            errorCode: nil,
            errorReason: nil
        )
        let newer = SigningHistoryRecord(
            accountID: accountB,
            appID: UUID(),
            appName: "New App",
            originalBundleIdentifier: "com.example.new",
            signedBundleIdentifier: nil,
            version: "2.0",
            buildNumber: "2",
            iconRelativePath: nil,
            accountDisplayName: "138****5678",
            teamID: "TEAM2",
            teamName: "Developer Team",
            certificateSerialNumber: "CERT",
            action: .renew,
            result: .failed,
            signedAt: Date(timeIntervalSince1970: 200),
            expiryDate: nil,
            errorCode: "SEAL-SIGN-500",
            errorReason: "签名失败"
        )

        try await store.append(older)
        try await store.append(newer)

        #expect((try await store.records()).map(\.appName) == ["New App", "Old App"])
        #expect((try await store.records(accountID: accountA)).map(\.appName) == ["Old App"])
    }

    @Test
    func summaryCountsValidExpiredAndFailedRecords() {
        let now = Date(timeIntervalSince1970: 1_000)
        let accountID = UUID()
        let records = [
            makeRecord(accountID: accountID, result: .success, expiryDate: Date(timeIntervalSince1970: 1_500)),
            makeRecord(accountID: accountID, result: .success, expiryDate: Date(timeIntervalSince1970: 900)),
            makeRecord(accountID: accountID, result: .failed, expiryDate: nil)
        ]

        let summary = SigningHistorySummary(records: records, now: now)

        #expect(summary.total == 3)
        #expect(summary.succeeded == 2)
        #expect(summary.failed == 1)
        #expect(summary.valid == 1)
        #expect(summary.expired == 1)
    }

    private func makeRecord(
        accountID: UUID,
        result: SigningHistoryRecord.Result,
        expiryDate: Date?
    ) -> SigningHistoryRecord {
        SigningHistoryRecord(
            accountID: accountID,
            appID: UUID(),
            appName: "Demo",
            originalBundleIdentifier: "com.example.demo",
            signedBundleIdentifier: nil,
            version: "1.0",
            buildNumber: "1",
            iconRelativePath: nil,
            accountDisplayName: "dev***er@icloud.com",
            teamID: "TEAM",
            teamName: "Personal Team",
            certificateSerialNumber: nil,
            action: .sign,
            result: result,
            signedAt: Date(),
            expiryDate: expiryDate,
            errorCode: nil,
            errorReason: nil
        )
    }
}

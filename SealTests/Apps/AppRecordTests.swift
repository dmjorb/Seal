import Foundation
import Testing
@testable import Seal

struct AppRecordTests {
    @Test
    func importedRecordPreservesParsedMetadata() {
        let appID = UUID()
        let extensionID = UUID()
        let importedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let appExtension = AppExtensionRecord(
            id: extensionID,
            name: "Share",
            originalBundleIdentifier: "com.example.demo.share",
            kind: .share
        )

        let record = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            name: "Demo",
            version: "1.2.3",
            buildNumber: "45",
            size: 12_345,
            state: .imported,
            ipaRelativePath: "Apps/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/Original.ipa",
            importedAt: importedAt,
            extensions: [appExtension]
        )

        #expect(record.id == appID)
        #expect(record.originalBundleIdentifier == "com.example.demo")
        #expect(record.name == "Demo")
        #expect(record.version == "1.2.3")
        #expect(record.buildNumber == "45")
        #expect(record.size == 12_345)
        #expect(record.state == .imported)
        #expect(record.importedAt == importedAt)
        #expect(record.extensions == [appExtension])
        #expect(record.isSeal == false)
        #expect(record.isPinned == false)
    }


    @Test
    func signedButNotInstalledRecordLocksSigningIdentity() {
        let expiration = Date(timeIntervalSinceNow: 86_400)
        let record = AppRecord(
            originalBundleIdentifier: "com.example.original",
            mappedBundleIdentifier: "com.example.signed",
            name: "Pending Install",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .failedRecoverable,
            accountID: UUID(),
            signingTeamID: "TEAM123",
            certificateSerialNumber: "ABCDEF123456",
            signedDeviceIdentifier: "UDID-123",
            provisioningProfileExpirationDate: expiration,
            ipaRelativePath: "Apps/pending/Original.ipa",
            signedIPARelativePath: "Apps/pending/Signed.ipa",
            importedAt: Date()
        )

        #expect(record.hasPersistedSigningIdentity)
        #expect(record.requiresLockedSigningIdentity)
    }

    @Test(arguments: [
        (AppState.imported, "imported"),
        (AppState.preflightPassed, "preflightPassed"),
        (AppState.failedRecoverable, "failedRecoverable"),
        (AppState.failedFinal, "failedFinal")
    ])
    func appStateHasStablePersistenceValue(state: AppState, rawValue: String) {
        #expect(state.rawValue == rawValue)
        #expect(AppState(rawValue: rawValue) == state)
    }

    @Test
    func importFailureContainsOneRecoveryAction() {
        let failure = ImportFailure(
            title: "无法读取 IPA",
            reason: "未找到应用信息",
            recovery: "选择其他 IPA",
            code: "SEAL-IPA-101"
        )

        #expect(failure.title == "无法读取 IPA")
        #expect(failure.reason == "未找到应用信息")
        #expect(failure.recovery == "选择其他 IPA")
        #expect(failure.code == "SEAL-IPA-101")
    }
}

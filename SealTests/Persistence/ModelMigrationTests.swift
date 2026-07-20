import Foundation
import Testing
@testable import Seal

struct ModelMigrationTests {
    @Test
    func accountWithoutSelectedCertificateStillDecodes() throws {
        let account = AppleAccountRecord(
            maskedEmail: "s***@example.com",
            accountIdentifier: "account",
            teamID: "TEAMID",
            teamName: "Personal Team",
            certificateSerialNumber: "SERIAL",
            lastVerifiedAt: Date(timeIntervalSince1970: 100)
        )

        let legacyData = try removingKey(
            "selectedCertificateSerialNumber",
            from: JSONEncoder().encode(account)
        )
        let decoded = try JSONDecoder().decode(
            AppleAccountRecord.self,
            from: legacyData
        )

        #expect(decoded.certificateSerialNumber == "SERIAL")
        #expect(decoded.selectedCertificateSerialNumber == nil)
    }

    @Test
    func appWithoutCertificateSerialStillDecodes() throws {
        let app = AppRecord(
            originalBundleIdentifier: "com.example.app",
            name: "Example",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/example.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )

        let legacyData = try removingKey(
            "certificateSerialNumber",
            from: JSONEncoder().encode(app)
        )
        let decoded = try JSONDecoder().decode(AppRecord.self, from: legacyData)

        #expect(decoded.certificateSerialNumber == nil)
        #expect(decoded.state == .installed)
    }

    private func removingKey(_ key: String, from data: Data) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object)
    }
}

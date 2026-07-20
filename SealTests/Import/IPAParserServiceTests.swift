import Foundation
import Testing
@testable import Seal

struct IPAParserServiceTests {
    @Test
    func parsesAppIconExtensionAndEntitlements() throws {
        let url = try IPAArchiveFixture.make(
            includeShareExtension: true,
            includeEntitlements: true
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try IPAParserService().parse(url: url)

        #expect(result.name == "Demo")
        #expect(result.bundleIdentifier == "com.example.demo")
        #expect(result.version == "1.2.3")
        #expect(result.buildNumber == "45")
        #expect(result.fileSize > 0)
        #expect(result.iconData == Data("fixture-icon".utf8))
        #expect(result.extensions.count == 1)
        #expect(result.extensions.first?.kind == .share)
        #expect(result.entitlementKeys == [
            "aps-environment",
            "com.apple.security.application-groups"
        ])
    }

    @Test
    func preservesUTF8AppNamesAndArchivePaths() throws {
        let url = try IPAArchiveFixture.make(
            apps: [
                .init(
                    directoryName: "示例应用.app",
                    bundleIdentifier: "com.example.utf8",
                    name: "示例应用"
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try IPAParserService().parse(url: url)

        #expect(result.name == "示例应用")
        #expect(result.bundleIdentifier == "com.example.utf8")
    }

    @Test
    func rejectsArchiveWithoutAppInfo() throws {
        let url = try IPAArchiveFixture.make(includeInfo: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        assertFailure(code: "SEAL-IPA-101") {
            try IPAParserService().parse(url: url)
        }
    }

    @Test
    func rejectsMalformedAppInfo() throws {
        let url = try IPAArchiveFixture.make(apps: [.init(malformedInfo: true)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        assertFailure(code: "SEAL-IPA-102") {
            try IPAParserService().parse(url: url)
        }
    }

    @Test
    func rejectsMultipleAppRoots() throws {
        let url = try IPAArchiveFixture.make(apps: [
            .init(),
            .init(directoryName: "Other.app", bundleIdentifier: "com.example.other")
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        assertFailure(code: "SEAL-IPA-103") {
            try IPAParserService().parse(url: url)
        }
    }

    @Test
    func rejectsUnsafeArchivePath() throws {
        let url = try IPAArchiveFixture.make(
            extraEntries: [("../outside", Data("unsafe".utf8))]
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        assertFailure(code: "SEAL-IPA-104") {
            try IPAParserService().parse(url: url)
        }
    }

    @Test
    func rejectsExpandedSizeOverLimit() throws {
        let url = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let limits = ArchiveLimits(
            maximumEntryCount: 100,
            maximumExpandedSize: 1,
            maximumMetadataSize: 1_000_000
        )

        assertFailure(code: "SEAL-IPA-105") {
            try IPAParserService(limits: limits).parse(url: url)
        }
    }

    private func assertFailure(
        code: String,
        operation: () throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try operation()
            Issue.record("Expected import to fail.", sourceLocation: sourceLocation)
        } catch let failure as ImportFailure {
            #expect(failure.code == code, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}

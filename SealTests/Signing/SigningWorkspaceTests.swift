import Foundation
import Testing
@testable import Seal

struct SigningWorkspaceTests {
    @Test
    func safelyRemapsMainAndExtensionThenPackagesIPA() throws {
        let source = try IPAArchiveFixture.make(includeShareExtension: true)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SealSigningTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = SigningWorkspace()
        let prepared = try workspace.prepare(
            ipaURL: source,
            workspaceRoot: root.appending(path: "Work"),
            originalBundleID: "com.example.demo",
            teamID: "TEAMID"
        )
        let output = root.appending(path: "Signed.ipa")

        try workspace.package(prepared, outputURL: output)
        let parsed = try IPAParserService().parse(url: output)

        #expect(parsed.bundleIdentifier == prepared.mappedMainBundleID)
        #expect(parsed.extensions.first?.originalBundleIdentifier ==
            prepared.bundleIDMappings["com.example.demo.share"])
    }
}

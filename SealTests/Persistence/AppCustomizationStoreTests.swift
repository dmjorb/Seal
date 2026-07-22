import Foundation
import Testing
@testable import Seal

struct AppCustomizationStoreTests {
    @Test
    func savesAndReloadsCustomizationByOriginalBundleIdentifier() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppCustomizationStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "AppCustomizations.json")
        let store = AppCustomizationStore(fileURL: url)
        let preference = AppCustomizationPreference(
            originalBundleIdentifier: "com.example.demo",
            displayName: "Demo Custom",
            iconData: Data([0x89, 0x50, 0x4E, 0x47]),
            lastSuccessfulBundleIdentifier: "com.example.demo.seal",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try await store.save(preference)
        let loaded = try await store.all()

        #expect(loaded["com.example.demo"] == preference)
    }
}

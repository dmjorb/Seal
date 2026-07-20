import Foundation
import Testing
@testable import Seal

struct PairingStoreTests {
    @Test
    func importsNormalizesProtectsAndRemovesPairingFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Source.plist")
        let destination = root.appending(path: "Stored/Pairing.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["UDID": "device-123", "HostID": "host"],
            format: .binary,
            options: 0
        )
        try data.write(to: source)
        let store = PairingStore(
            fileURL: destination,
            fileProtector: MarkerFileProtector()
        )

        let imported = try await store.importFile(at: source)

        #expect(imported.deviceIdentifier == "device-123")
        #expect(imported.isRemotePairing == false)
        #expect(try await store.current() == imported)
        #expect(try await store.contents().contains("device-123"))
        #expect(FileManager.default.fileExists(
            atPath: destination.appendingPathExtension("protected").path
        ))

        try await store.remove()
        #expect(try await store.current() == nil)
    }

    @Test
    func rejectsUnrelatedPropertyList() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Invalid.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Name": "Not pairing"],
            format: .xml,
            options: 0
        )
        try data.write(to: source)
        let store = PairingStore(fileURL: root.appending(path: "Pairing.plist"))

        await #expect(throws: ImportFailure.self) {
            try await store.importFile(at: source)
        }
    }

    @Test
    func rejectsOversizedPairingFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Oversized.plist")
        try Data(repeating: 0, count: 5 * 1_024 * 1_024 + 1).write(to: source)
        let store = PairingStore(fileURL: root.appending(path: "Pairing.plist"))

        await #expect(throws: ImportFailure.self) {
            try await store.importFile(at: source)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "SealPairingTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}

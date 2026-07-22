import Foundation
import Testing
@testable import Seal

struct PairingStoreTests {
    @Test
    func importsValidatesProtectsAndRemovesStandardPairingFile() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Source.plist")
        let destination = root.appending(path: "Stored/Pairing.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: standardPairingDictionary(udid: "device-123"),
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
        #expect(imported.validationStatus == .unverified)

        let validated = try await store.markValidated(deviceIdentifier: "device-123")
        #expect(validated.isVerifiedForCurrentDevice)
        #expect(validated.validatedDeviceIdentifier == "device-123")
        #expect(try await store.current() == validated)
        #expect(try await store.contents().contains("device-123"))
        #expect(FileManager.default.fileExists(
            atPath: destination.appendingPathExtension("protected").path
        ))

        try await store.remove()
        #expect(try await store.current() == nil)
    }

    @Test
    func reimportingPairingFileResetsPreviousVerifiedMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Source.plist")
        let destination = root.appending(path: "Pairing.plist")
        let store = PairingStore(fileURL: destination)

        let first = try PropertyListSerialization.data(
            fromPropertyList: standardPairingDictionary(udid: "device-123"),
            format: .xml,
            options: 0
        )
        try first.write(to: source)
        _ = try await store.importFile(at: source)
        _ = try await store.markValidated(deviceIdentifier: "device-123")
        #expect(try await store.current()?.validationStatus == .verified)

        let replacement = try PropertyListSerialization.data(
            fromPropertyList: standardPairingDictionary(udid: "device-456"),
            format: .xml,
            options: 0
        )
        try replacement.write(to: source, options: .atomic)
        let imported = try await store.importFile(at: source)

        #expect(imported.validationStatus == .unverified)
        #expect(try await store.current()?.validationStatus == .unverified)
        #expect(try await store.current()?.deviceIdentifier == "device-456")
    }

    @Test
    func importsRemotePairingWithPrivateKeyOnly() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Remote.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["private_key": Data([1, 2, 3])],
            format: .xml,
            options: 0
        )
        try data.write(to: source)
        let store = PairingStore(fileURL: root.appending(path: "Pairing.plist"))

        let imported = try await store.importFile(at: source)
        #expect(imported.deviceIdentifier == nil)
        #expect(imported.isRemotePairing == true)
        #expect(imported.validationStatus == .unverified)
    }

    @Test
    func importsUDIDOnlyPairingForRuntimeValidation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "UDIDOnly.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["UDID": "device-123", "HostID": "host"],
            format: .xml,
            options: 0
        )
        try data.write(to: source)
        let store = PairingStore(fileURL: root.appending(path: "Pairing.plist"))

        let imported = try await store.importFile(at: source)
        #expect(imported.deviceIdentifier == "device-123")
        #expect(imported.isRemotePairing == false)
    }

    @Test
    func rejectsPairingFileForAnotherConnectedDevice() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Source.plist")
        let destination = root.appending(path: "Pairing.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: standardPairingDictionary(udid: "device-A"),
            format: .xml,
            options: 0
        )
        try data.write(to: source)
        let store = PairingStore(fileURL: destination)
        _ = try await store.importFile(at: source)

        await #expect(throws: ImportFailure.self) {
            try await store.markValidated(deviceIdentifier: "device-B")
        }
        #expect(try await store.current()?.validationStatus == .deviceMismatch)
    }

    @Test
    func rejectsPairingFileWithoutUDIDOrPrivateKey() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Invalid.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["HostID": "host"],
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

    private func standardPairingDictionary(udid: String) -> [String: Any] {
        [
            "UDID": udid,
            "HostID": "host-id",
            "SystemBUID": "system-buid",
            "HostCertificate": Data([1, 2, 3]),
            "HostPrivateKey": Data([4, 5, 6]),
            "RootCertificate": Data([7, 8, 9]),
            "RootPrivateKey": Data([10, 11, 12])
        ]
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "SealPairingTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}

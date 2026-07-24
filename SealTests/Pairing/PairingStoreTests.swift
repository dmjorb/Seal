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
    func reimportResetsPreviouslyVerifiedPairingMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceA = root.appending(path: "Source-A.plist")
        let sourceB = root.appending(path: "Source-B.plist")
        let destination = root.appending(path: "Stored/Pairing.plist")

        try PropertyListSerialization.data(
            fromPropertyList: standardPairingDictionary(udid: "device-A"),
            format: .xml,
            options: 0
        ).write(to: sourceA)
        try PropertyListSerialization.data(
            fromPropertyList: standardPairingDictionary(udid: "device-B"),
            format: .xml,
            options: 0
        ).write(to: sourceB)

        let store = PairingStore(fileURL: destination)
        _ = try await store.importFile(at: sourceA)
        _ = try await store.markValidated(deviceIdentifier: "device-A")
        #expect(try await store.current()?.validationStatus == .verified)

        let replacement = try await store.importFile(at: sourceB)
        #expect(replacement.deviceIdentifier == "device-B")
        #expect(replacement.validationStatus == .unverified)
        #expect(replacement.validatedDeviceIdentifier == nil)
        #expect(replacement.validatedAt == nil)

        let current = try await store.current()
        #expect(current?.deviceIdentifier == "device-B")
        #expect(current?.validationStatus == .unverified)
        #expect(current?.validatedDeviceIdentifier == nil)
        #expect(current?.validatedAt == nil)
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

import Foundation
import Testing
@testable import Seal

struct CoreDataAppStoreTests {
    @Test
    func fetchesNewestImportsFirst() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let older = makeRecord(
            name: "Older",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeRecord(
            name: "Newer",
            importedAt: Date(timeIntervalSince1970: 200)
        )

        try await store.save(older)
        try await store.save(newer)

        let records = try await store.fetchAll()
        #expect(records.map(\.name) == ["Newer", "Older"])
    }

    @Test
    func savingSameIDReplacesRecordAndExtensions() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let id = UUID()
        let original = makeRecord(
            id: id,
            name: "Original",
            extensions: [
                AppExtensionRecord(
                    name: "Share",
                    originalBundleIdentifier: "com.example.demo.share",
                    kind: .share
                )
            ]
        )
        let replacement = makeRecord(id: id, name: "Replacement", extensions: [])

        try await store.save(original)
        try await store.save(replacement)

        let records = try await store.fetchAll()
        let saved = try #require(records.first)
        #expect(records.count == 1)
        #expect(saved.name == "Replacement")
        #expect(saved.extensions.isEmpty)
    }

    @Test
    func persistentStoreReloadsSavedRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Seal.sqlite")
        let record = makeRecord(name: "Persisted")

        do {
            let firstStore = try CoreDataAppStore(storeURL: storeURL)
            try await firstStore.save(record)
        }

        let reopenedStore = try CoreDataAppStore(storeURL: storeURL)
        let records = try await reopenedStore.fetchAll()
        #expect(records == [record])
    }


    @Test
    func persistsCompleteSigningIdentityAndTargetProfiles() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let accountID = UUID()
        let profileExpiration = Date(timeIntervalSince1970: 1_900_000_000)
        let signingTarget = SigningTargetRecord(
            bundleIdentifier: "com.example.signed",
            profileUUID: "PROFILE-UUID-COMPLETE",
            profileName: "Apple Development Profile",
            profileCreationDate: Date(timeIntervalSince1970: 1_800_000_000),
            profileExpirationDate: profileExpiration,
            teamIdentifier: "TEAM-COMPLETE",
            certificateSerialNumbers: ["00AABBCCDDEEFF"],
            deviceIdentifiers: ["00008110-001A388E0A13801E"],
            entitlementKeys: ["application-identifier", "get-task-allow"]
        )
        let extensionRecord = AppExtensionRecord(
            name: "Share",
            originalBundleIdentifier: "com.example.original.share",
            mappedBundleIdentifier: "com.example.signed.share",
            kind: .share,
            provisioningProfileUUID: "EXT-PROFILE-UUID",
            provisioningProfileName: "Share Profile",
            provisioningProfileExpirationDate: profileExpiration,
            certificateSerialNumber: "00AABBCCDDEEFF"
        )
        let record = AppRecord(
            originalBundleIdentifier: "com.example.original",
            mappedBundleIdentifier: "com.example.signed",
            name: "Complete",
            version: "2.0",
            buildNumber: "20",
            size: 4_096,
            state: .installed,
            expiryDate: profileExpiration,
            accountID: accountID,
            signingTeamID: "TEAM-COMPLETE",
            certificateSerialNumber: "00AABBCCDDEEFF",
            signedDeviceIdentifier: "00008110-001A388E0A13801E",
            provisioningProfileUUID: "PROFILE-UUID-COMPLETE",
            provisioningProfileName: "Apple Development Profile",
            provisioningProfileCreationDate: Date(timeIntervalSince1970: 1_800_000_000),
            provisioningProfileExpirationDate: profileExpiration,
            entitlementValidationStatus: "validated",
            capabilityValidationStatus: "validated",
            lastSignedAt: Date(timeIntervalSince1970: 1_800_000_100),
            lastInstalledAt: Date(timeIntervalSince1970: 1_800_000_200),
            removedExtensionBundleIdentifiers: ["com.example.original.widget"],
            signingTargets: [signingTarget],
            ipaRelativePath: "Apps/complete/Original.ipa",
            signedIPARelativePath: "Apps/complete/Signed.ipa",
            preferredBundleIdentifier: "com.example.signed",
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            extensions: [extensionRecord]
        )

        try await store.save(record)
        let saved = try #require(try await store.fetchAll().first)

        #expect(saved == record)
        #expect(saved.hasPersistedSigningIdentity)
        #expect(saved.requiresLockedSigningIdentity)
        #expect(saved.signingTargets == [signingTarget])
    }

    @Test
    func importedReplacementMatchesBundleIdentifierCaseInsensitively() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let original = AppRecord(
            originalBundleIdentifier: "com.Example.Demo",
            name: "Original",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .imported,
            ipaRelativePath: "Apps/original/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let replacement = AppRecord(
            originalBundleIdentifier: "com.example.demo",
            name: "Replacement",
            version: "2",
            buildNumber: "2",
            size: 2,
            state: .imported,
            ipaRelativePath: "Apps/replacement/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.save(original)

        let replaced = try await store.replaceImportedApp(replacement)
        let records = try await store.fetchAll()

        #expect(replaced == [original])
        #expect(records == [replacement])
    }

    @Test
    func deletesRecordByID() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let record = makeRecord(name: "Delete Me")
        try await store.save(record)

        try await store.delete(id: record.id)

        #expect(try await store.fetchAll() == [])
    }

    @Test
    func failedSaveRollsBackAllContextChanges() async throws {
        let store = try CoreDataAppStore(
            inMemory: true,
            beforeSave: { operation in
                guard operation == .save else { return }
                throw InjectedPersistenceFailure.expected
            }
        )

        await #expect(throws: AppStoreError.self) {
            try await store.save(makeRecord(name: "Must Roll Back"))
        }

        #expect(await store.hasUncommittedChanges() == false)
        #expect(try await store.fetchAll().isEmpty)
    }

    @Test
    func failedDeleteRollsBackAllContextChanges() async throws {
        let store = try CoreDataAppStore(
            inMemory: true,
            beforeSave: { operation in
                guard operation == .delete else { return }
                throw InjectedPersistenceFailure.expected
            }
        )
        let record = makeRecord(name: "Keep Me")
        try await store.save(record)

        await #expect(throws: AppStoreError.self) {
            try await store.delete(id: record.id)
        }

        #expect(await store.hasUncommittedChanges() == false)
        #expect(try await store.fetchAll() == [record])
    }

    @Test
    func failedImportedAppReplacementRollsBackOriginalRecordAndContextChanges() async throws {
        let store = try CoreDataAppStore(
            inMemory: true,
            beforeSave: { operation in
                guard operation == .replaceImportedApp else { return }
                throw InjectedPersistenceFailure.expected
            }
        )
        let original = makeRecord(name: "Original")
        let replacement = AppRecord(
            originalBundleIdentifier: original.originalBundleIdentifier,
            name: "Replacement",
            version: "2.0",
            buildNumber: "2",
            size: 2_048,
            state: .imported,
            ipaRelativePath: "Apps/replacement/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.save(original)

        await #expect(throws: AppStoreError.self) {
            try await store.replaceImportedApp(replacement)
        }

        #expect(await store.hasUncommittedChanges() == false)
        #expect(try await store.fetchAll() == [original])
    }

    private func makeRecord(
        id: UUID = UUID(),
        name: String,
        importedAt: Date = Date(timeIntervalSince1970: 100),
        extensions: [AppExtensionRecord] = []
    ) -> AppRecord {
        AppRecord(
            id: id,
            originalBundleIdentifier: "com.example.\(id.uuidString.lowercased())",
            name: name,
            version: "1.0",
            buildNumber: "1",
            size: 1_024,
            state: .imported,
            ipaRelativePath: "Apps/\(id.uuidString)/Original.ipa",
            importedAt: importedAt,
            extensions: extensions
        )
    }
}

private enum InjectedPersistenceFailure: Error {
    case expected
}

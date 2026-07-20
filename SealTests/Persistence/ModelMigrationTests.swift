import CoreData
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


    @Test
    func legacyCoreDataStoreMigratesWithoutLosingApps() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SealLegacyMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Seal.sqlite")
        let legacyModel = CoreDataModel.makeLegacyV1()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: legacyModel)
        _ = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataModel.appEntityName,
                into: context
            )
            object.setValue(UUID(), forKey: "id")
            object.setValue("com.example.legacy", forKey: "originalBundleIdentifier")
            object.setValue("Legacy", forKey: "name")
            object.setValue("1.0", forKey: "version")
            object.setValue("1", forKey: "buildNumber")
            object.setValue(Int64(1_024), forKey: "size")
            object.setValue(AppState.imported.rawValue, forKey: "stateRaw")
            object.setValue("Apps/legacy/Original.ipa", forKey: "ipaRelativePath")
            object.setValue(false, forKey: "isSeal")
            object.setValue(false, forKey: "isPinned")
            object.setValue(Date(timeIntervalSince1970: 100), forKey: "importedAt")
            try context.save()
        }
        if let store = coordinator.persistentStores.first {
            try coordinator.remove(store)
        }

        let migratedStore = try CoreDataAppStore(storeURL: storeURL)
        let records = try await migratedStore.fetchAll()
        let record = try #require(records.first)
        #expect(record.originalBundleIdentifier == "com.example.legacy")
        #expect(record.signingTeamID == nil)
        #expect(record.signingTargets.isEmpty)
        #expect(record.removedExtensionBundleIdentifiers.isEmpty)
    }

    @Test
    func legacyAppJSONDefaultsNewCollections() throws {
        let app = AppRecord(
            originalBundleIdentifier: "com.example.legacy-json",
            name: "Legacy JSON",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .imported,
            ipaRelativePath: "Apps/legacy-json.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) as? [String: Any]
        )
        object.removeValue(forKey: "removedExtensionBundleIdentifiers")
        object.removeValue(forKey: "signingTargets")
        let decoded = try JSONDecoder().decode(
            AppRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.removedExtensionBundleIdentifiers.isEmpty)
        #expect(decoded.signingTargets.isEmpty)
    }

    private func removingKey(_ key: String, from data: Data) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object)
    }
}

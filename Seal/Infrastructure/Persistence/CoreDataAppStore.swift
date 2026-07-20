import CoreData
import Foundation

actor CoreDataAppStore: AppStore {
    private let context: NSManagedObjectContext

    init(inMemory: Bool) throws {
        guard inMemory else { throw AppStoreError.invalidConfiguration }
        context = try Self.makeContext(storeType: NSInMemoryStoreType, storeURL: nil)
    }

    init(storeURL: URL) throws {
        context = try Self.makeContext(storeType: NSSQLiteStoreType, storeURL: storeURL)
    }

    func fetchAll() throws -> [AppRecord] {
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(
                entityName: CoreDataModel.appEntityName
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "importedAt", ascending: false),
                NSSortDescriptor(key: "name", ascending: true)
            ]
            return try context.fetch(request).map(Self.decode)
        }
    }

    func save(_ record: AppRecord) throws {
        try context.performAndWait {
            do {
                let app = try Self.fetchApp(id: record.id, context: context)
                    ?? NSEntityDescription.insertNewObject(
                        forEntityName: CoreDataModel.appEntityName,
                        into: context
                    )
                Self.write(record, to: app, context: context)

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func replaceImportedApp(_ record: AppRecord) throws -> [AppRecord] {
        try context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(
                    entityName: CoreDataModel.appEntityName
                )
                request.predicate = NSPredicate(
                    format: "originalBundleIdentifier == %@",
                    record.originalBundleIdentifier
                )
                let existing = try context.fetch(request)
                let replaced = try existing.map(Self.decode)
                existing.forEach(context.delete)

                let app = NSEntityDescription.insertNewObject(
                    forEntityName: CoreDataModel.appEntityName,
                    into: context
                )
                Self.write(record, to: app, context: context)

                try context.save()
                return replaced
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func delete(id: UUID) throws {
        try context.performAndWait {
            if let app = try Self.fetchApp(id: id, context: context) {
                context.delete(app)
                try context.save()
            }
        }
    }

    private static func makeContext(
        storeType: String,
        storeURL: URL?
    ) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: CoreDataModel.make()
        )
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSPersistentStoreFileProtectionKey:
                FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try coordinator.addPersistentStore(
            ofType: storeType,
            configurationName: nil,
            at: storeURL,
            options: options
        )

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        context.undoManager = nil
        return context
    }

    private static func fetchApp(
        id: UUID,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(
            entityName: CoreDataModel.appEntityName
        )
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func apply(_ record: AppRecord, to object: NSManagedObject) {
        object.setValue(record.id, forKey: "id")
        object.setValue(record.originalBundleIdentifier, forKey: "originalBundleIdentifier")
        object.setValue(record.mappedBundleIdentifier, forKey: "mappedBundleIdentifier")
        object.setValue(record.name, forKey: "name")
        object.setValue(record.version, forKey: "version")
        object.setValue(record.buildNumber, forKey: "buildNumber")
        object.setValue(record.size, forKey: "size")
        object.setValue(record.iconRelativePath, forKey: "iconRelativePath")
        object.setValue(record.state.rawValue, forKey: "stateRaw")
        object.setValue(record.expiryDate, forKey: "expiryDate")
        object.setValue(record.accountID, forKey: "accountID")
        object.setValue(record.certificateSerialNumber, forKey: "certificateSerialNumber")
        object.setValue(record.ipaRelativePath, forKey: "ipaRelativePath")
        object.setValue(record.signedIPARelativePath, forKey: "signedIPARelativePath")
        object.setValue(record.preferredBundleIdentifier, forKey: "preferredBundleIdentifier")
        object.setValue(record.isSeal, forKey: "isSeal")
        object.setValue(record.isPinned, forKey: "isPinned")
        object.setValue(record.importedAt, forKey: "importedAt")
    }

    private static func write(
        _ record: AppRecord,
        to app: NSManagedObject,
        context: NSManagedObjectContext
    ) {
        apply(record, to: app)
        let oldExtensions = (app.value(forKey: "extensions") as? NSSet)?
            .allObjects as? [NSManagedObject] ?? []
        oldExtensions.forEach(context.delete)

        for appExtension in record.extensions {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataModel.extensionEntityName,
                into: context
            )
            apply(appExtension, to: object)
            object.setValue(app, forKey: "app")
        }
    }

    private static func apply(
        _ record: AppExtensionRecord,
        to object: NSManagedObject
    ) {
        object.setValue(record.id, forKey: "id")
        object.setValue(record.name, forKey: "name")
        object.setValue(record.originalBundleIdentifier, forKey: "originalBundleIdentifier")
        object.setValue(record.mappedBundleIdentifier, forKey: "mappedBundleIdentifier")
        object.setValue(record.kind.rawValue, forKey: "kindRaw")
    }

    private static func decode(_ object: NSManagedObject) throws -> AppRecord {
        guard let id = object.value(forKey: "id") as? UUID,
              let originalBundleIdentifier = object.value(
                forKey: "originalBundleIdentifier"
              ) as? String,
              let name = object.value(forKey: "name") as? String,
              let version = object.value(forKey: "version") as? String,
              let buildNumber = object.value(forKey: "buildNumber") as? String,
              let stateRaw = object.value(forKey: "stateRaw") as? String,
              let state = AppState(rawValue: stateRaw),
              let ipaRelativePath = object.value(forKey: "ipaRelativePath") as? String,
              let importedAt = object.value(forKey: "importedAt") as? Date else {
            throw AppStoreError.corruptRecord
        }

        let extensionObjects = (object.value(forKey: "extensions") as? NSSet)?
            .allObjects as? [NSManagedObject] ?? []
        let appExtensions = try extensionObjects
            .map(Self.decodeExtension)
            .sorted { first, second in
                if first.name == second.name {
                    return first.id.uuidString < second.id.uuidString
                }
                return first.name < second.name
            }

        return AppRecord(
            id: id,
            originalBundleIdentifier: originalBundleIdentifier,
            mappedBundleIdentifier: object.value(forKey: "mappedBundleIdentifier") as? String,
            name: name,
            version: version,
            buildNumber: buildNumber,
            size: (object.value(forKey: "size") as? NSNumber)?.int64Value ?? 0,
            iconRelativePath: object.value(forKey: "iconRelativePath") as? String,
            state: state,
            expiryDate: object.value(forKey: "expiryDate") as? Date,
            accountID: object.value(forKey: "accountID") as? UUID,
            certificateSerialNumber: object.value(forKey: "certificateSerialNumber") as? String,
            ipaRelativePath: ipaRelativePath,
            signedIPARelativePath: object.value(forKey: "signedIPARelativePath") as? String,
            preferredBundleIdentifier: object.value(forKey: "preferredBundleIdentifier") as? String,
            isSeal: (object.value(forKey: "isSeal") as? NSNumber)?.boolValue ?? false,
            isPinned: (object.value(forKey: "isPinned") as? NSNumber)?.boolValue ?? false,
            importedAt: importedAt,
            extensions: appExtensions
        )
    }

    private static func decodeExtension(
        _ object: NSManagedObject
    ) throws -> AppExtensionRecord {
        guard let id = object.value(forKey: "id") as? UUID,
              let name = object.value(forKey: "name") as? String,
              let originalBundleIdentifier = object.value(
                forKey: "originalBundleIdentifier"
              ) as? String,
              let kindRaw = object.value(forKey: "kindRaw") as? String,
              let kind = AppExtensionKind(rawValue: kindRaw) else {
            throw AppStoreError.corruptRecord
        }

        return AppExtensionRecord(
            id: id,
            name: name,
            originalBundleIdentifier: originalBundleIdentifier,
            mappedBundleIdentifier: object.value(forKey: "mappedBundleIdentifier") as? String,
            kind: kind
        )
    }
}

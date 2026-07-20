import CoreData

enum CoreDataModel {
    static let appEntityName = "AppEntity"
    static let extensionEntityName = "ExtensionEntity"

    static func make() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let app = NSEntityDescription()
        app.name = appEntityName
        app.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        app.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("originalBundleIdentifier", type: .stringAttributeType),
            attribute("mappedBundleIdentifier", type: .stringAttributeType, optional: true),
            attribute("name", type: .stringAttributeType),
            attribute("version", type: .stringAttributeType),
            attribute("buildNumber", type: .stringAttributeType),
            attribute("size", type: .integer64AttributeType),
            attribute("iconRelativePath", type: .stringAttributeType, optional: true),
            attribute("stateRaw", type: .stringAttributeType),
            attribute("expiryDate", type: .dateAttributeType, optional: true),
            attribute("accountID", type: .UUIDAttributeType, optional: true),
            attribute("signingTeamID", type: .stringAttributeType, optional: true),
            attribute("certificateSerialNumber", type: .stringAttributeType, optional: true),
            attribute("signedDeviceIdentifier", type: .stringAttributeType, optional: true),
            attribute("provisioningProfileUUID", type: .stringAttributeType, optional: true),
            attribute("provisioningProfileName", type: .stringAttributeType, optional: true),
            attribute("provisioningProfileCreationDate", type: .dateAttributeType, optional: true),
            attribute("provisioningProfileExpirationDate", type: .dateAttributeType, optional: true),
            attribute("entitlementValidationStatus", type: .stringAttributeType, optional: true),
            attribute("capabilityValidationStatus", type: .stringAttributeType, optional: true),
            attribute("lastSignedAt", type: .dateAttributeType, optional: true),
            attribute("lastInstalledAt", type: .dateAttributeType, optional: true),
            attribute("removedExtensionBundleIdentifiersData", type: .binaryDataAttributeType, optional: true),
            attribute("signingTargetsData", type: .binaryDataAttributeType, optional: true),
            attribute("ipaRelativePath", type: .stringAttributeType),
            attribute("signedIPARelativePath", type: .stringAttributeType, optional: true),
            attribute("preferredBundleIdentifier", type: .stringAttributeType, optional: true),
            attribute("isSeal", type: .booleanAttributeType, defaultValue: false),
            attribute("isPinned", type: .booleanAttributeType, defaultValue: false),
            attribute("importedAt", type: .dateAttributeType)
        ]

        let appExtension = NSEntityDescription()
        appExtension.name = extensionEntityName
        appExtension.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        appExtension.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("name", type: .stringAttributeType),
            attribute("originalBundleIdentifier", type: .stringAttributeType),
            attribute("mappedBundleIdentifier", type: .stringAttributeType, optional: true),
            attribute("kindRaw", type: .stringAttributeType),
            attribute("provisioningProfileUUID", type: .stringAttributeType, optional: true),
            attribute("provisioningProfileName", type: .stringAttributeType, optional: true),
            attribute("provisioningProfileExpirationDate", type: .dateAttributeType, optional: true),
            attribute("certificateSerialNumber", type: .stringAttributeType, optional: true)
        ]

        addRelationships(app: app, appExtension: appExtension)
        model.entities = [app, appExtension]
        return model
    }


    static func makeLegacyV1() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let app = NSEntityDescription()
        app.name = appEntityName
        app.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        app.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("originalBundleIdentifier", type: .stringAttributeType),
            attribute("mappedBundleIdentifier", type: .stringAttributeType, optional: true),
            attribute("name", type: .stringAttributeType),
            attribute("version", type: .stringAttributeType),
            attribute("buildNumber", type: .stringAttributeType),
            attribute("size", type: .integer64AttributeType),
            attribute("iconRelativePath", type: .stringAttributeType, optional: true),
            attribute("stateRaw", type: .stringAttributeType),
            attribute("expiryDate", type: .dateAttributeType, optional: true),
            attribute("accountID", type: .UUIDAttributeType, optional: true),
            attribute("certificateSerialNumber", type: .stringAttributeType, optional: true),
            attribute("ipaRelativePath", type: .stringAttributeType),
            attribute("signedIPARelativePath", type: .stringAttributeType, optional: true),
            attribute("preferredBundleIdentifier", type: .stringAttributeType, optional: true),
            attribute("isSeal", type: .booleanAttributeType, defaultValue: false),
            attribute("isPinned", type: .booleanAttributeType, defaultValue: false),
            attribute("importedAt", type: .dateAttributeType)
        ]

        let appExtension = NSEntityDescription()
        appExtension.name = extensionEntityName
        appExtension.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        appExtension.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("name", type: .stringAttributeType),
            attribute("originalBundleIdentifier", type: .stringAttributeType),
            attribute("mappedBundleIdentifier", type: .stringAttributeType, optional: true),
            attribute("kindRaw", type: .stringAttributeType)
        ]

        addRelationships(app: app, appExtension: appExtension)
        model.entities = [app, appExtension]
        return model
    }


    private static func addRelationships(
        app: NSEntityDescription,
        appExtension: NSEntityDescription
    ) {
        let extensionsRelationship = NSRelationshipDescription()
        extensionsRelationship.name = "extensions"
        extensionsRelationship.destinationEntity = appExtension
        extensionsRelationship.minCount = 0
        extensionsRelationship.maxCount = 0
        extensionsRelationship.deleteRule = .cascadeDeleteRule
        extensionsRelationship.isOptional = true

        let appRelationship = NSRelationshipDescription()
        appRelationship.name = "app"
        appRelationship.destinationEntity = app
        appRelationship.minCount = 0
        appRelationship.maxCount = 1
        appRelationship.deleteRule = .nullifyDeleteRule
        appRelationship.isOptional = true

        extensionsRelationship.inverseRelationship = appRelationship
        appRelationship.inverseRelationship = extensionsRelationship
        app.properties.append(extensionsRelationship)
        appExtension.properties.append(appRelationship)
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}

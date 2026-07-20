import Foundation

enum SelfManagedSealMigrationPolicy {
    static let canonicalBundleIdentifier = "com.mjorb.seal"

    static func isSealIPAPackage(name: String, bundleIdentifier: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedName == "seal"
            || bundleIdentifier == canonicalBundleIdentifier
            || bundleIdentifier.hasPrefix(canonicalBundleIdentifier + ".")
    }

    static func isMigrationPackage(_ app: AppRecord) -> Bool {
        app.isSeal == false
            && app.state != .installed
            && isSealIPAPackage(name: app.name, bundleIdentifier: app.originalBundleIdentifier)
    }

    static func recommendedBundleIdentifier(teamID: String?) -> String {
        let suffix = (teamID ?? "")
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber
            }

        if suffix.isEmpty {
            return canonicalBundleIdentifier + ".self"
        }
        return canonicalBundleIdentifier + ".t" + String(suffix)
    }
}

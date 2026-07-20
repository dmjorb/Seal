import Foundation

struct SelfAppMetadata: Sendable {
    let bundleURL: URL
    let bundleIdentifier: String
    let originalBundleIdentifier: String?
    let name: String
    let version: String
    let buildNumber: String
    let iconData: Data?
    let expirationDate: Date?

    @MainActor
    static func current(bundle: Bundle = .main) -> SelfAppMetadata? {
        guard let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Seal"
        let version = (bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String) ?? "1.0"
        let buildNumber = (bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String) ?? "1"
        let profileURL = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
        let expirationDate = profileURL
            .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
            .flatMap { try? ProvisioningProfileReader().expirationDate(from: $0) }

        return SelfAppMetadata(
            bundleURL: bundle.bundleURL,
            bundleIdentifier: bundleIdentifier,
            originalBundleIdentifier: bundle.object(
                forInfoDictionaryKey: "SealOriginalBundleIdentifier"
            ) as? String,
            name: name,
            version: version,
            buildNumber: buildNumber,
            iconData: iconData(bundle: bundle),
            expirationDate: expirationDate
        )
    }

    @MainActor
    private static func iconData(bundle: Bundle) -> Data? {
        let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primaryIcon = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconNames = primaryIcon?["CFBundleIconFiles"] as? [String]
        for name in (iconNames ?? []).reversed() {
            let resourceName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            let resourceExtension = URL(fileURLWithPath: name).pathExtension
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: resourceExtension.isEmpty ? "png" : resourceExtension
            ), let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                return data
            }
        }
        return nil
    }
}

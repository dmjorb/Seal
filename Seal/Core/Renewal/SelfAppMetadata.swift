import Foundation
import UIKit

struct SelfAppMetadata: Sendable {
    let bundleURL: URL
    let bundleIdentifier: String
    let originalBundleIdentifier: String?
    let name: String
    let version: String
    let buildNumber: String
    let iconData: Data?
    let expirationDate: Date?
    let signingTeamIdentifier: String?
    let signingApplicationIdentifier: String?

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
        let profileSummary = profileURL
            .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
            .flatMap { try? ProvisioningProfileReader().summary(from: $0) }

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
            expirationDate: profileSummary?.expirationDate,
            signingTeamIdentifier: profileSummary?.teamIdentifier,
            signingApplicationIdentifier: profileSummary?.applicationIdentifier
        )
    }

    @MainActor
    private static func iconData(bundle: Bundle) -> Data? {
        let names = iconFileNames(bundle: bundle)
        for name in names.reversed() {
            if let data = resourceIconData(name: name, bundle: bundle) { return data }
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil),
               let data = image.pngData() {
                return data
            }
        }

        for candidate in ["AppIcon", "SealIcon", "Icon", "iTunesArtwork", "iTunesArtwork@2x"] {
            if let data = resourceIconData(name: candidate, bundle: bundle) { return data }
            if let image = UIImage(named: candidate, in: bundle, compatibleWith: nil),
               let data = image.pngData() {
                return data
            }
        }
        return nil
    }

    private static func iconFileNames(bundle: Bundle) -> [String] {
        let info = bundle.infoDictionary ?? [:]
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primaryIcon["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        if let files = info["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files)
        }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private static func resourceIconData(name: String, bundle: Bundle) -> Data? {
        let url = URL(fileURLWithPath: name)
        let resourceName = url.deletingPathExtension().lastPathComponent
        let resourceExtension = url.pathExtension
        let extensions = resourceExtension.isEmpty ? ["png", ""] : [resourceExtension]
        for ext in extensions {
            let found = ext.isEmpty
                ? bundle.url(forResource: resourceName, withExtension: nil)
                : bundle.url(forResource: resourceName, withExtension: ext)
            if let found, let data = try? Data(contentsOf: found, options: .mappedIfSafe) {
                return data
            }
        }
        return nil
    }
}

import CryptoKit
import Foundation

struct BundleIDMapper: Sendable {
    let prefix: String

    init(prefix: String = "com.mjorb.seal.apps") {
        self.prefix = prefix
    }

    func mainBundleID(
        original: String,
        teamID: String,
        requested: String? = nil
    ) -> String {
        if let requested, requested.isEmpty == false {
            return requested
        }
        return BundleIDPolicy.recommendedBundleIdentifier(for: original)
    }

    func extensionBundleID(
        original: String,
        mappedMainBundleID: String
    ) -> String {
        "\(mappedMainBundleID).e\(digest(original, length: 10))"
    }

    func appGroupID(original: String, teamID: String) -> String {
        "group.com.mjorb.seal.groups.\(digest("\(teamID):\(original)", length: 20))"
    }

    private func digest(_ value: String, length: Int) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.map { String(format: "%02x", $0) }
            .joined()
            .prefix(length)
            .description
    }
}

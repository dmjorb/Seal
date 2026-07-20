import Foundation

struct ProvisioningProfileReader: Sendable {
    struct Summary: Sendable, Equatable {
        let expirationDate: Date?
        let teamIdentifier: String?
        let applicationIdentifier: String?
    }

    func summary(from data: Data) throws -> Summary {
        let dictionary = try plistDictionary(from: data)
        let teamIdentifier = (dictionary["TeamIdentifier"] as? [String])?.first
            ?? (dictionary["ApplicationIdentifierPrefix"] as? [String])?.first
        let entitlements = dictionary["Entitlements"] as? [String: Any]

        return Summary(
            expirationDate: dictionary["ExpirationDate"] as? Date,
            teamIdentifier: teamIdentifier,
            applicationIdentifier: entitlements?["application-identifier"] as? String
        )
    }

    func expirationDate(from data: Data) throws -> Date? {
        try summary(from: data).expirationDate
    }

    private func plistDictionary(from data: Data) throws -> [String: Any] {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker)?.lowerBound,
              let endRange = data.range(of: endMarker, in: start..<data.endIndex) else {
            return [:]
        }
        let plistData = data[start..<endRange.upperBound]
        let value = try PropertyListSerialization.propertyList(
            from: Data(plistData),
            options: [],
            format: nil
        )
        return value as? [String: Any] ?? [:]
    }
}

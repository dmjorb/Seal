import Foundation

struct ProvisioningProfileReader: Sendable {
    func expirationDate(from data: Data) throws -> Date? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker)?.lowerBound,
              let endRange = data.range(of: endMarker, in: start..<data.endIndex) else {
            return nil
        }
        let plistData = data[start..<endRange.upperBound]
        let value = try PropertyListSerialization.propertyList(
            from: Data(plistData),
            options: [],
            format: nil
        )
        return (value as? [String: Any])?["ExpirationDate"] as? Date
    }
}

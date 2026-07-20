import Foundation
import Security

struct ProvisioningProfileReader: Sendable {
    struct Summary: Sendable, Equatable {
        let expirationDate: Date?
        let teamIdentifier: String?
        let applicationIdentifier: String?
    }

    struct Details: Sendable, Equatable {
        let uuid: String?
        let name: String?
        let creationDate: Date?
        let expirationDate: Date?
        let teamIdentifier: String?
        let applicationIdentifier: String?
        let bundleIdentifier: String?
        let deviceIdentifiers: [String]
        let certificateSerialNumbers: [String]
        let entitlements: [String: ProvisioningEntitlementValue]

        var entitlementKeys: [String] {
            entitlements.keys.sorted()
        }
    }

    func summary(from data: Data) throws -> Summary {
        let details = try details(from: data)
        return Summary(
            expirationDate: details.expirationDate,
            teamIdentifier: details.teamIdentifier,
            applicationIdentifier: details.applicationIdentifier
        )
    }

    func details(from data: Data) throws -> Details {
        let dictionary = try plistDictionary(from: data)
        let teamIdentifier = (dictionary["TeamIdentifier"] as? [String])?.first
            ?? (dictionary["ApplicationIdentifierPrefix"] as? [String])?.first
        let entitlements = dictionary["Entitlements"] as? [String: Any] ?? [:]
        let applicationIdentifier = entitlements["application-identifier"] as? String
        let bundleIdentifier = Self.bundleIdentifier(
            applicationIdentifier: applicationIdentifier,
            teamIdentifier: teamIdentifier
        )
        let certificateData = dictionary["DeveloperCertificates"] as? [Data] ?? []

        return Details(
            uuid: dictionary["UUID"] as? String,
            name: dictionary["Name"] as? String,
            creationDate: dictionary["CreationDate"] as? Date,
            expirationDate: dictionary["ExpirationDate"] as? Date,
            teamIdentifier: teamIdentifier,
            applicationIdentifier: applicationIdentifier,
            bundleIdentifier: bundleIdentifier,
            deviceIdentifiers: (dictionary["ProvisionedDevices"] as? [String]) ?? [],
            certificateSerialNumbers: certificateData.compactMap(Self.certificateSerialNumber),
            entitlements: entitlements.reduce(into: [:]) { result, item in
                if let value = ProvisioningEntitlementValue.make(from: item.value) {
                    result[item.key] = value
                }
            }
        )
    }

    func binding(from data: Data) throws -> ProvisioningProfileBinding {
        let details = try details(from: data)
        guard let expirationDate = details.expirationDate else {
            throw ImportFailure(
                title: "描述文件校验失败",
                reason: "描述文件没有 ExpirationDate。",
                recovery: "重新获取描述文件",
                code: "SEAL-PROFILE-315"
            )
        }
        guard let teamIdentifier = details.teamIdentifier,
              teamIdentifier.isEmpty == false else {
            throw ImportFailure(
                title: "描述文件校验失败",
                reason: "描述文件没有 TeamIdentifier / ApplicationIdentifierPrefix。",
                recovery: "重新获取描述文件",
                code: "SEAL-PROFILE-317"
            )
        }
        guard let bundleIdentifier = details.bundleIdentifier,
              bundleIdentifier.isEmpty == false else {
            throw ImportFailure(
                title: "描述文件校验失败",
                reason: "描述文件没有有效的 application-identifier / Bundle ID。",
                recovery: "重新获取描述文件",
                code: "SEAL-PROFILE-316"
            )
        }
        return ProvisioningProfileBinding(
            bundleIdentifier: bundleIdentifier,
            profileUUID: details.uuid,
            profileName: details.name,
            teamIdentifier: teamIdentifier,
            creationDate: details.creationDate,
            expirationDate: expirationDate,
            certificateSerialNumbers: details.certificateSerialNumbers,
            deviceIdentifiers: details.deviceIdentifiers,
            entitlements: details.entitlements
        )
    }

    func expirationDate(from data: Data) throws -> Date? {
        try summary(from: data).expirationDate
    }

    private func plistDictionary(from data: Data) throws -> [String: Any] {
        let startMarkers = [Data("<?xml".utf8), Data("bplist00".utf8)]
        let endMarker = Data("</plist>".utf8)

        if let xmlStart = data.range(of: startMarkers[0])?.lowerBound,
           let endRange = data.range(of: endMarker, in: xmlStart..<data.endIndex) {
            let plistData = data[xmlStart..<endRange.upperBound]
            let value = try PropertyListSerialization.propertyList(
                from: Data(plistData),
                options: [],
                format: nil
            )
            guard let dictionary = value as? [String: Any] else {
                throw Self.invalidProfile
            }
            return dictionary
        }

        if let binaryStart = data.range(of: startMarkers[1])?.lowerBound {
            let plistData = data[binaryStart..<data.endIndex]
            if let value = try? PropertyListSerialization.propertyList(
                from: Data(plistData),
                options: [],
                format: nil
            ), let dictionary = value as? [String: Any] {
                return dictionary
            }
        }

        throw Self.invalidProfile
    }

    private static func bundleIdentifier(
        applicationIdentifier: String?,
        teamIdentifier: String?
    ) -> String? {
        guard let applicationIdentifier else { return nil }
        guard let teamIdentifier, teamIdentifier.isEmpty == false else {
            return applicationIdentifier
        }
        let prefix = teamIdentifier + "."
        guard applicationIdentifier.hasPrefix(prefix) else {
            return applicationIdentifier
        }
        return String(applicationIdentifier.dropFirst(prefix.count))
    }

    private static func certificateSerialNumber(_ data: Data) -> String? {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData),
              let serialData = SecCertificateCopySerialNumberData(certificate, nil) else {
            return nil
        }
        let serial = serialData as Data
        return serial.map { String(format: "%02X", $0) }.joined()
    }

    private static let invalidProfile = ImportFailure(
        title: "描述文件校验失败",
        reason: "无法解析 embedded.mobileprovision。",
        recovery: "重新获取描述文件",
        code: "SEAL-PROFILE-309"
    )
}

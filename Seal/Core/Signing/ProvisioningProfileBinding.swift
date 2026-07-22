import Foundation

struct ProvisioningProfileBinding: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let profileUUID: String?
    let profileName: String?
    let teamIdentifier: String
    let creationDate: Date?
    let expirationDate: Date
    let certificateSerialNumbers: [String]
    let deviceIdentifiers: [String]
    let entitlements: [String: ProvisioningEntitlementValue]

    var entitlementKeys: [String] {
        entitlements.keys.sorted()
    }

    func validated(
        expectedTeamID: String,
        expectedBundleID: String,
        expectedCertificateSerialNumber: String,
        expectedDeviceIdentifier: String,
        now: Date = Date()
    ) throws -> ProvisioningProfileBinding {
        guard teamIdentifier.caseInsensitiveCompare(expectedTeamID) == .orderedSame else {
            throw Self.failure(
                reason: "描述文件 Team ID 与当前签名 Team 不一致。实际：\(teamIdentifier)，期望：\(expectedTeamID)。",
                code: "SEAL-PROFILE-310"
            )
        }
        guard bundleIdentifier.caseInsensitiveCompare(expectedBundleID) == .orderedSame else {
            throw Self.failure(
                reason: "描述文件 Bundle ID 与签名目标不一致。实际：\(bundleIdentifier)，期望：\(expectedBundleID)。",
                code: "SEAL-PROFILE-311"
            )
        }
        guard expirationDate > now else {
            throw Self.failure(
                reason: "Apple 返回的描述文件已经过期：\(expirationDate.formatted(date: .numeric, time: .shortened))。",
                code: "SEAL-PROFILE-312"
            )
        }
        guard certificateSerialNumbers.contains(where: {
            CertificateSerial.matches($0, expectedCertificateSerialNumber)
        }) else {
            throw Self.failure(
                reason: "描述文件不包含当前签名证书。当前 Serial：\(expectedCertificateSerialNumber)。",
                code: "SEAL-PROFILE-313"
            )
        }
        guard deviceIdentifiers.contains(where: {
            $0.caseInsensitiveCompare(expectedDeviceIdentifier) == .orderedSame
        }) else {
            throw Self.failure(
                reason: "描述文件不包含当前设备 UDID：\(expectedDeviceIdentifier)。",
                code: "SEAL-PROFILE-314"
            )
        }
        return self
    }

    static func validateEntitlements(
        requested: [String: ProvisioningEntitlementValue],
        profile: [String: ProvisioningEntitlementValue],
        bundleIdentifier: String
    ) throws {
        let valuesManagedBySigner: Set<String> = [
            "com.apple.developer.team-identifier",
            "application-identifier",
            "keychain-access-groups",
            "get-task-allow"
        ]
        let missing = Set(requested.keys)
            .subtracting(profile.keys)
            .subtracting(valuesManagedBySigner)
            .sorted()
        guard missing.isEmpty else {
            throw Self.failure(
                reason: "描述文件未授权 \(bundleIdentifier) 请求的权限：\(missing.joined(separator: "、"))。",
                code: "SEAL-ENTITLEMENT-401"
            )
        }

        let mismatched = requested.keys.sorted().filter { key in
            guard valuesManagedBySigner.contains(key) == false,
                  let requestedValue = requested[key],
                  let profileValue = profile[key] else {
                return false
            }
            return profileValue.permits(requestedValue) == false
        }
        guard mismatched.isEmpty else {
            throw Self.failure(
                reason: "描述文件中的权限值与 \(bundleIdentifier) 请求不一致：\(mismatched.joined(separator: "、"))。",
                code: "SEAL-ENTITLEMENT-402"
            )
        }
    }

    static func validateEntitlements(
        requestedKeys: Set<String>,
        profileKeys: Set<String>,
        bundleIdentifier: String
    ) throws {
        let requested = Dictionary(uniqueKeysWithValues: requestedKeys.map {
            ($0, ProvisioningEntitlementValue.bool(true))
        })
        let profile = Dictionary(uniqueKeysWithValues: profileKeys.map {
            ($0, ProvisioningEntitlementValue.bool(true))
        })
        try validateEntitlements(
            requested: requested,
            profile: profile,
            bundleIdentifier: bundleIdentifier
        )
    }


    private static func failure(reason: String, code: String) -> ImportFailure {
        ImportFailure(
            title: "描述文件校验失败",
            reason: reason,
            recovery: "重新获取描述文件；仍失败时检查 Apple ID、Team、证书和设备",
            code: code
        )
    }
}

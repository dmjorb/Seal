import Foundation
@preconcurrency import AltSign

struct ApplePortalInventory: Codable, Equatable, Sendable {
    let accountID: UUID
    let teamID: String
    let teamName: String
    let appIDs: [ApplePortalAppIDSnapshot]
    let certificates: [ApplePortalCertificateSnapshot]
    let fetchedAt: Date

    var usedBundleIDCount: Int {
        Set(appIDs.map { $0.bundleIdentifier.lowercased() }).count
    }
}

struct ApplePortalAppIDSnapshot: Codable, Equatable, Identifiable, Sendable {
    enum ProvisioningProfileState: String, Codable, Equatable, Sendable {
        case available
        case unavailable
    }

    var id: String { identifier }

    let identifier: String
    let name: String
    let bundleIdentifier: String
    let appIDExpirationDate: Date?
    let provisioningProfileName: String?
    let provisioningProfileExpirationDate: Date?
    let provisioningProfileState: ProvisioningProfileState
}

struct ApplePortalCertificateSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: String { serialNumber }
    let serialNumber: String
    let machineName: String
    let machineIdentifier: String?
    let hasLocalPrivateKey: Bool

    var displayName: String { machineName }
}

actor ApplePortalInventoryService {
    enum FetchScope: Sendable {
        case appIDs
        case certificates
        case all

        var includesAppIDs: Bool {
            switch self {
            case .appIDs, .all: true
            case .certificates: false
            }
        }

        var includesCertificates: Bool {
            switch self {
            case .certificates, .all: true
            case .appIDs: false
            }
        }
    }
    private let anisetteProvider: any AnisetteProvider

    init(anisetteProvider: any AnisetteProvider = AnisetteV3Client()) {
        self.anisetteProvider = anisetteProvider
    }

    func fetchInventory(
        account: AppleAccountRecord,
        secret: AccountSecret,
        scope: FetchScope = .all
    ) async throws -> ApplePortalInventory {
        do {
            return try await fetchInventoryOnce(account: account, secret: secret, scope: scope)
        } catch ALTAppleAPIError.invalidAnisetteData {
            await anisetteProvider.resetProvisioning()
            return try await fetchInventoryOnce(account: account, secret: secret, scope: scope)
        }
    }

    private func fetchInventoryOnce(
        account: AppleAccountRecord,
        secret: AccountSecret,
        scope: FetchScope
    ) async throws -> ApplePortalInventory {
        try Task.checkCancellation()
        let anisette = try await anisetteProvider.fetch()
        let session = ALTAppleAPISession(
            dsid: secret.dsid,
            authToken: secret.authToken,
            anisetteData: anisette
        )
        let altAccount = ALTAccount()
        altAccount.appleID = secret.email
        altAccount.identifier = secret.accountIdentifier

        let teams = try await fetchTeams(account: altAccount, session: session)
        guard let team = teams.first(where: { $0.identifier == account.teamID }) else {
            throw ImportFailure(
                title: "Apple 同步失败",
                reason: "Apple 返回的 Team 列表中没有当前账号保存的 Team ID：\(account.teamID)。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-INVENTORY-101"
            )
        }

        let certificates = scope.includesCertificates
            ? try await fetchCertificates(team: team, session: session)
            : []
        let appIDs = scope.includesAppIDs
            ? try await fetchAppIDs(team: team, session: session)
            : []
        let fetchedAt = Date()

        let localP12SerialNumber: String? = {
            guard let p12 = secret.certificateP12,
                  let localCertificate = try? ALTCertificate(p12Data: p12, password: nil) else {
                return nil
            }
            return localCertificate.serialNumber
        }()

        let certificateSnapshots = certificates.map { certificate in
            let matchesStoredSerial = secret.certificateSerialNumber?.caseInsensitiveCompare(
                certificate.serialNumber
            ) == .orderedSame
            let matchesP12Serial = localP12SerialNumber?.caseInsensitiveCompare(
                certificate.serialNumber
            ) == .orderedSame
            return ApplePortalCertificateSnapshot(
                serialNumber: certificate.serialNumber,
                machineName: certificate.machineName ?? "Apple Development",
                machineIdentifier: certificate.machineIdentifier,
                hasLocalPrivateKey: matchesStoredSerial && matchesP12Serial
            )
        }

        // Apple ID 页面只读取 Apple 返回的 App ID 元数据。
        // 刷新列表绝不能获取或生成 provisioning profile，否则会改变描述文件时间。
        let appSnapshots: [ApplePortalAppIDSnapshot] = appIDs.compactMap { appID in
            guard let expirationDate = appID.expirationDate, expirationDate > fetchedAt else {
                return nil
            }
            return ApplePortalAppIDSnapshot(
                identifier: appID.identifier,
                name: Self.displayName(
                    from: appID.name,
                    fallbackBundleIdentifier: appID.bundleIdentifier
                ),
                bundleIdentifier: appID.bundleIdentifier,
                appIDExpirationDate: expirationDate,
                provisioningProfileName: nil,
                provisioningProfileExpirationDate: nil,
                provisioningProfileState: .unavailable
            )
        }

        var sortedAppSnapshots = appSnapshots
        sortedAppSnapshots.sort {
            let result = $0.name.localizedStandardCompare($1.name)
            if result == .orderedSame {
                return $0.bundleIdentifier.localizedStandardCompare($1.bundleIdentifier) == .orderedAscending
            }
            return result == .orderedAscending
        }

        return ApplePortalInventory(
            accountID: account.id,
            teamID: team.identifier,
            teamName: team.name,
            appIDs: sortedAppSnapshots,
            certificates: certificateSnapshots,
            fetchedAt: fetchedAt
        )
    }


    private static func displayName(
        from rawName: String,
        fallbackBundleIdentifier: String
    ) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return fallbackBundleIdentifier }
        let prefix = "Seal "
        if trimmed.hasPrefix(prefix) {
            let original = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return original.isEmpty ? fallbackBundleIdentifier : original
        }
        return trimmed
    }

    private func fetchTeams(
        account: ALTAccount,
        session: ALTAppleAPISession
    ) async throws -> [ALTTeam] {
        let box: LegacyBox<[ALTTeam]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchTeams(for: account, session: session) { teams, error in
                if let teams {
                    continuation.resume(returning: LegacyBox(teams))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
        return box.value
    }

    private func fetchCertificates(
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> [ALTCertificate] {
        let box: LegacyBox<[ALTCertificate]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certificates, error in
                if let certificates {
                    continuation.resume(returning: LegacyBox(certificates))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
        return box.value
    }

    private func fetchAppIDs(
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> [ALTAppID] {
        let box: LegacyBox<[ALTAppID]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
                if let appIDs {
                    continuation.resume(returning: LegacyBox(appIDs))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
        return box.value
    }


}

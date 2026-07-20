import Foundation
@preconcurrency import AltSign

struct ApplePortalInventory: Equatable, Sendable {
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

struct ApplePortalAppIDSnapshot: Equatable, Identifiable, Sendable {
    enum ProvisioningProfileState: Equatable, Sendable {
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

struct ApplePortalCertificateSnapshot: Equatable, Identifiable, Sendable {
    var id: String { serialNumber }
    let serialNumber: String
    let machineName: String
    let machineIdentifier: String?
    let hasLocalPrivateKey: Bool

    var displayName: String { machineName }
}

actor ApplePortalInventoryService {
    private let anisetteProvider: any AnisetteProvider

    init(anisetteProvider: any AnisetteProvider = AnisetteV3Client()) {
        self.anisetteProvider = anisetteProvider
    }

    func fetchInventory(
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws -> ApplePortalInventory {
        do {
            return try await fetchInventoryOnce(account: account, secret: secret)
        } catch ALTAppleAPIError.invalidAnisetteData {
            await anisetteProvider.resetProvisioning()
            return try await fetchInventoryOnce(account: account, secret: secret)
        }
    }

    private func fetchInventoryOnce(
        account: AppleAccountRecord,
        secret: AccountSecret
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

        let certificates = try await fetchCertificates(team: team, session: session)
        let appIDs = try await fetchAppIDs(team: team, session: session)

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

        var appSnapshots: [ApplePortalAppIDSnapshot] = []
        appSnapshots.reserveCapacity(appIDs.count)

        // Apple 的 App ID 响应提供真实名称和 App ID 到期时间。
        // 描述文件日期必须读取 Apple 返回的 provisioning profile，不能用本地 AppRecord 代替。
        // 逐项读取可避免 AltSign 旧模型跨并发边界引发 Swift 6 Sendable 问题。
        for appID in appIDs {
            try Task.checkCancellation()

            let profile = try? await fetchProvisioningProfile(
                appID: appID,
                team: team,
                session: session
            )
            let normalizedName = appID.name.trimmingCharacters(in: .whitespacesAndNewlines)

            appSnapshots.append(
                ApplePortalAppIDSnapshot(
                    identifier: appID.identifier,
                    name: normalizedName.isEmpty ? appID.bundleIdentifier : normalizedName,
                    bundleIdentifier: appID.bundleIdentifier,
                    appIDExpirationDate: appID.expirationDate,
                    provisioningProfileName: profile?.name,
                    provisioningProfileExpirationDate: profile?.expirationDate,
                    provisioningProfileState: profile == nil ? .unavailable : .available
                )
            )
        }

        appSnapshots.sort {
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
            appIDs: appSnapshots,
            certificates: certificateSnapshots,
            fetchedAt: Date()
        )
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

    private func fetchProvisioningProfile(
        appID: ALTAppID,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> ALTProvisioningProfile {
        let box: LegacyBox<ALTProvisioningProfile> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchProvisioningProfile(
                for: appID,
                deviceType: .iphone,
                team: team,
                session: session
            ) { profile, error in
                if let profile {
                    continuation.resume(returning: LegacyBox(profile))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
        return box.value
    }
}

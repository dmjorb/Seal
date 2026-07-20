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
    enum ProfileState: Equatable, Sendable {
        case available
        case unavailable(code: String, message: String)
    }

    var id: String { bundleIdentifier.lowercased() }
    let bundleIdentifier: String
    let provisioningProfileExpirationDate: Date?
    let profileState: ProfileState
}

struct ApplePortalCertificateSnapshot: Equatable, Identifiable, Sendable {
    var id: String { serialNumber }
    let serialNumber: String
    let machineName: String
    let hasLocalPrivateKey: Bool
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
                title: "Apple 侧同步失败",
                reason: "Apple 返回的 Team 列表中没有当前账号保存的 Team ID：\(account.teamID)。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-INVENTORY-101"
            )
        }

        let certificates = try await fetchCertificates(team: team, session: session)
        let appIDs = try await fetchAppIDs(team: team, session: session)

        let certificateSnapshots = certificates.map { certificate in
            ApplePortalCertificateSnapshot(
                serialNumber: certificate.serialNumber,
                machineName: certificate.machineName ?? "Apple Development",
                hasLocalPrivateKey: certificate.serialNumber == secret.certificateSerialNumber
                    && secret.certificateP12 != nil
            )
        }

        var appSnapshots: [ApplePortalAppIDSnapshot] = []
        for appID in appIDs.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier }) {
            try Task.checkCancellation()
            do {
                let profile = try await fetchProvisioningProfile(
                    for: appID,
                    team: team,
                    session: session
                )
                appSnapshots.append(
                    ApplePortalAppIDSnapshot(
                        bundleIdentifier: appID.bundleIdentifier,
                        provisioningProfileExpirationDate: profile.expirationDate,
                        profileState: .available
                    )
                )
            } catch {
                let nsError = error as NSError
                appSnapshots.append(
                    ApplePortalAppIDSnapshot(
                        bundleIdentifier: appID.bundleIdentifier,
                        provisioningProfileExpirationDate: nil,
                        profileState: .unavailable(
                            code: "\(nsError.domain) \(nsError.code)",
                            message: nsError.localizedDescription
                        )
                    )
                )
            }
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
        for appID: ALTAppID,
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

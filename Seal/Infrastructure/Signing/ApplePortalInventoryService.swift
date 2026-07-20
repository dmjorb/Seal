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
    var id: String { bundleIdentifier.lowercased() }
    let bundleIdentifier: String
}

struct ApplePortalCertificateSnapshot: Equatable, Identifiable, Sendable {
    var id: String { serialNumber }
    let serialNumber: String
    let machineName: String
    let hasLocalPrivateKey: Bool

    var displayName: String {
        machineName.hasPrefix("Seal") ? "Seal" : machineName
    }
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

        // 详情页同步必须是只读操作。这里只读取证书和 App ID，
        // 不请求或生成 provisioning profile，避免刷新页面改变 Apple 账号状态。
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

        let appSnapshots = appIDs
            .map { ApplePortalAppIDSnapshot(bundleIdentifier: $0.bundleIdentifier) }
            .sorted { $0.bundleIdentifier < $1.bundleIdentifier }

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
}

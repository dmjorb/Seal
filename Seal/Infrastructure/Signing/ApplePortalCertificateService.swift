import Foundation
import UIKit
@preconcurrency import AltSign

struct CreatedCertificateMaterial: Sendable {
    let updatedSecret: AccountSecret
    let serialNumber: String
    let machineIdentifier: String?
    let machineName: String
}

actor ApplePortalCertificateService {
    private let anisetteProvider: any AnisetteProvider

    init(anisetteProvider: any AnisetteProvider = AnisetteV3Client()) {
        self.anisetteProvider = anisetteProvider
    }

    func createLocalCertificate(
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws -> CreatedCertificateMaterial {
        do {
            return try await createOnce(account: account, secret: secret)
        } catch ALTAppleAPIError.invalidAnisetteData {
            await anisetteProvider.resetProvisioning()
            return try await createOnce(account: account, secret: secret)
        }
    }

    func revokeCertificate(
        serialNumber: String,
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws {
        do {
            try await revokeOnce(
                serialNumber: serialNumber,
                account: account,
                secret: secret
            )
        } catch ALTAppleAPIError.invalidAnisetteData {
            await anisetteProvider.resetProvisioning()
            try await revokeOnce(
                serialNumber: serialNumber,
                account: account,
                secret: secret
            )
        }
    }

    private func createOnce(
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws -> CreatedCertificateMaterial {
        let context = try await context(account: account, secret: secret)
        _ = try await fetchCertificates(team: context.team, session: context.session)
        let deviceName = await MainActor.run { UIDevice.current.name }
        let localP12Serial: String? = {
            guard let p12 = secret.certificateP12,
                  let certificate = try? ALTCertificate(p12Data: p12, password: nil) else {
                return nil
            }
            return certificate.serialNumber
        }()
        let operations = CertificatePortalOperations<LegacyBox<ALTCertificate>>(
            addCertificate: { [self] in
                LegacyBox(
                    try await addCertificate(
                        team: context.team,
                        session: context.session,
                        deviceName: deviceName
                    )
                )
            },
            cleanupCandidates: { [self] in
                try await fetchCertificates(team: context.team, session: context.session)
                    .filter { CertificateSerial.matches($0.serialNumber, localP12Serial) == false }
                    .map(LegacyBox.init)
            },
            revokeCertificate: { [self] certificate in
                try await revoke(
                    certificate.value,
                    team: context.team,
                    session: context.session
                )
            }
        )
        let requested = try await ApplePortalCertificateCapacityOrchestrator.create(
            using: operations
        ).value
        do {
            let refreshed = try await fetchCertificates(
                team: context.team,
                session: context.session
            )
            guard let certificate = refreshed.first(where: {
                CertificateSerial.matches($0.serialNumber, requested.serialNumber)
            }) else {
                throw Self.failure(
                    title: "证书创建结果不一致",
                    reason: "Apple 已返回新证书，但重新同步后找不到完整 Serial：\(requested.serialNumber)。",
                    recovery: "重新同步证书",
                    code: "SEAL-CERT-209"
                )
            }

            certificate.privateKey = requested.privateKey
            guard let p12 = certificate.p12Data() else {
                throw Self.failure(
                    title: "无法保存本机证书",
                    reason: "Apple 已创建证书，但 Seal 无法将证书与本机私钥组成 P12。",
                    recovery: "重新同步后重试",
                    code: "SEAL-CERT-202"
                )
            }

            var updatedSecret = secret
            updatedSecret.certificateP12 = p12
            updatedSecret.certificateSerialNumber = certificate.serialNumber
            updatedSecret.certificateMachineIdentifier = certificate.machineIdentifier

            return CreatedCertificateMaterial(
                updatedSecret: updatedSecret,
                serialNumber: certificate.serialNumber,
                machineIdentifier: certificate.machineIdentifier,
                machineName: certificate.machineName ?? "Apple Development"
            )
        } catch {
            let cleanedUp = await cleanUpNewCertificate(
                serialNumber: requested.serialNumber,
                certificate: requested,
                team: context.team,
                session: context.session,
                account: account,
                secret: secret
            )
            guard cleanedUp else {
                throw Self.failure(
                    title: "签名失败",
                    reason: "Apple 返回：无法创建签名证书",
                    recovery: "重试",
                    code: "SEAL-CERT-215"
                )
            }
            if let failure = error as? ImportFailure { throw failure }
            throw error
        }
    }

    private func cleanUpNewCertificate(
        serialNumber: String,
        certificate: ALTCertificate,
        team: ALTTeam,
        session: ALTAppleAPISession,
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async -> Bool {
        if (try? await revoke(certificate, team: team, session: session)) != nil {
            return true
        }
        await anisetteProvider.resetProvisioning()
        guard let refreshedContext = try? await context(account: account, secret: secret),
              let certificates = try? await fetchCertificates(
                  team: refreshedContext.team,
                  session: refreshedContext.session
              ) else {
            return false
        }
        guard let exactCertificate = certificates.first(where: {
            CertificateSerial.matches($0.serialNumber, serialNumber)
        }) else {
            return true
        }
        return (try? await revoke(
            exactCertificate,
            team: refreshedContext.team,
            session: refreshedContext.session
        )) != nil
    }

    private func revokeOnce(
        serialNumber: String,
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws {
        let context = try await context(account: account, secret: secret)
        let certificates = try await fetchCertificates(team: context.team, session: context.session)
        guard let certificate = certificates.first(where: {
            CertificateSerial.matches($0.serialNumber, serialNumber)
        }) else {
            throw Self.failure(
                title: "证书不存在",
                reason: "Apple 返回：证书撤销失败",
                recovery: "重新同步证书",
                code: "SEAL-CERT-210"
            )
        }
        try await revoke(certificate, team: context.team, session: context.session)
    }

    private func context(
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws -> (team: ALTTeam, session: ALTAppleAPISession) {
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
            throw Self.failure(
                title: "账号 Team 不一致",
                reason: "Apple 当前返回的 Team 中没有已保存的 Team ID：\(account.teamID)。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-AUTH-112"
            )
        }
        return (team, session)
    }

    private func fetchTeams(
        account: ALTAccount,
        session: ALTAppleAPISession
    ) async throws -> [ALTTeam] {
        let box: LegacyBox<[ALTTeam]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchTeams(for: account, session: session) { teams, error in
                Self.resume(continuation, value: teams, error: error)
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
                Self.resume(continuation, value: certificates, error: error)
            }
        }
        return box.value
    }

    private func addCertificate(
        team: ALTTeam,
        session: ALTAppleAPISession,
        deviceName: String
    ) async throws -> ALTCertificate {
        let box: LegacyBox<ALTCertificate> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.addCertificate(
                machineName: Self.certificateMachineName(team: team, deviceName: deviceName),
                to: team,
                session: session
            ) { certificate, error in
                Self.resume(continuation, value: certificate, error: error)
            }
        }
        return box.value
    }

    private func revoke(
        _ certificate: ALTCertificate,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
    }

    private static func certificateMachineName(team: ALTTeam, deviceName: String) -> String {
        let sanitizedDevice = deviceName
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let devicePart = sanitizedDevice.isEmpty ? "Device" : String(sanitizedDevice.prefix(18))
        let teamPart = String(team.identifier.prefix(8))
        let timestamp = Int(Date().timeIntervalSince1970)
        return "Apple Development-\(teamPart)-\(devicePart)-\(timestamp)"
    }

    private static func isCertificateLimitError(_ error: Error) -> Bool {
        if let apiError = error as? ALTAppleAPIError,
           case .invalidCertificateRequest = apiError {
            return true
        }
        let nsError = error as NSError
        let normalized = "\(nsError.domain) \(nsError.code) \(nsError.localizedDescription) \(String(describing: error))".lowercased()
        return nsError.code == 3022
            || normalized.contains("3022")
            || normalized.contains("maximum number of certificates")
            || normalized.contains("maximum") && normalized.contains("certificate")
            || normalized.contains("too many") && normalized.contains("certificate")
            || normalized.contains("invalidcertificaterequest")
    }

    private static func resume<T>(
        _ continuation: CheckedContinuation<LegacyBox<T>, any Error>,
        value: T?,
        error: Error?
    ) {
        if let value {
            continuation.resume(returning: LegacyBox(value))
        } else {
            continuation.resume(throwing: error ?? URLError(.badServerResponse))
        }
    }

    private static func failure(
        title: String,
        reason: String,
        recovery: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(title: title, reason: reason, recovery: recovery, code: code)
    }
}

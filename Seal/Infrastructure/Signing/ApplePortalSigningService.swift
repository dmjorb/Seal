import Foundation
import UIKit
@preconcurrency import AltSign

enum ApplePortalSigningStage {
    case account
    case device
    case certificate
    case appID
    case provisioningProfile
    case signing
    case packaging
}

enum ApplePortalAppIDResolver {
    static func matches(
        existingBundleIdentifier: String,
        requestedBundleIdentifier: String
    ) -> Bool {
        existingBundleIdentifier.caseInsensitiveCompare(requestedBundleIdentifier) == .orderedSame
    }
}

enum ApplePortalSigningFailure {
    static func make(stage: ApplePortalSigningStage, error: Error) -> ImportFailure {
        let nsError = error as NSError
        let diagnostic = "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
        let details: (title: String, reason: String, recovery: String, code: String)
        switch stage {
        case .account:
            details = ("Apple 账户失败", "Apple 返回：\(diagnostic)", "重新验证 Apple ID", "SEAL-AUTH-105")
        case .device:
            details = ("设备注册失败", "Apple 返回：\(diagnostic)", "检查设备配对", "SEAL-DEVICE-203")
        case .certificate:
            return certificateFailure(error: error, diagnostic: diagnostic)
        case .appID:
            return appIDFailure(error: error, diagnostic: diagnostic)
        case .provisioningProfile:
            details = ("描述文件失败", "Apple 返回：\(diagnostic)", "重试", "SEAL-PROFILE-303")
        case .signing:
            details = ("签名失败", "签名工具返回：\(diagnostic)", "重试", "SEAL-SIGN-501")
        case .packaging:
            details = ("打包失败", "打包工具返回：\(diagnostic)", "重试", "SEAL-SIGN-502")
        }
        return ImportFailure(
            title: details.title,
            reason: details.reason,
            recovery: details.recovery,
            code: details.code
        )
    }

    private static func appIDFailure(error: Error, diagnostic: String) -> ImportFailure {
        let nsError = error as NSError
        let rawMessage = nsError.localizedDescription
        let normalized = rawMessage.lowercased()

        if nsError.code == 3011
            || normalized.contains("bundle identifier is unavailable")
            || normalized.contains("already registered by another developer account")
            || normalized.contains("bundle identifier unavailable") {
            return ImportFailure(
                title: "Bundle ID 不可用",
                reason: "Apple 返回：\(diagnostic)",
                recovery: "更换 Bundle ID",
                code: "SEAL-APPID-302"
            )
        }

        return ImportFailure(
            title: "App ID 操作失败",
            reason: "Apple 返回：\(diagnostic)",
            recovery: "重试",
            code: "SEAL-APPID-303"
        )
    }

    private static func certificateFailure(error: Error, diagnostic: String) -> ImportFailure {
        let nsError = error as NSError
        let rawMessage = nsError.localizedDescription
        let normalized = rawMessage.lowercased()

        if normalized.contains("maximum")
            || normalized.contains("limit")
            || normalized.contains("too many")
            || normalized.contains("invalidcertificaterequest") {
            return ImportFailure(
                title: "签名失败",
                reason: "Apple 返回：无法创建签名证书",
                recovery: "重试",
                code: "SEAL-CERT-204"
            )
        }

        if normalized.contains("network")
            || normalized.contains("timed out")
            || normalized.contains("cannot connect")
            || nsError.domain == NSURLErrorDomain {
            return ImportFailure(
                title: "证书服务连接失败",
                reason: "Apple 返回：\(diagnostic)",
                recovery: "重试",
                code: "SEAL-CERT-205"
            )
        }

        if normalized.contains("unauthorized")
            || normalized.contains("authentication")
            || normalized.contains("session")
            || normalized.contains("forbidden") {
            return ImportFailure(
                title: "账号需要重新验证",
                reason: "Apple 返回：\(diagnostic)",
                recovery: "重新验证 Apple ID",
                code: "SEAL-AUTH-104"
            )
        }

        return ImportFailure(
            title: "证书准备失败",
            reason: "Apple 返回：\(diagnostic)",
            recovery: "重试",
            code: "SEAL-CERT-203"
        )
    }

}

actor ApplePortalSigningService {
    private let anisetteProvider: any AnisetteProvider
    private let signingWorkspace: SigningWorkspace

    init(
        anisetteProvider: any AnisetteProvider = AnisetteV3Client(),
        signingWorkspace: SigningWorkspace = SigningWorkspace()
    ) {
        self.anisetteProvider = anisetteProvider
        self.signingWorkspace = signingWorkspace
    }

    func sign(
        app: AppRecord,
        account: AppleAccountRecord,
        secret: AccountSecret,
        deviceIdentifier: String,
        originalIPAURL: URL,
        workspaceRoot: URL,
        targetBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String? = nil,
        allowDroppingExtensions: Bool,
        persistSigningMaterial: @escaping @Sendable (AccountSecret, String) async throws -> Void,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> PortalSigningResult {
        let secretState = SigningSecretState(secret)
        let persistence: @Sendable (AccountSecret, String) async throws -> Void = {
            updatedSecret, serialNumber in
            try await persistSigningMaterial(updatedSecret, serialNumber)
            await secretState.update(updatedSecret)
        }

        do {
            return try await signOnce(
                app: app,
                account: account,
                secret: await secretState.value(),
                deviceIdentifier: deviceIdentifier,
                originalIPAURL: originalIPAURL,
                workspaceRoot: workspaceRoot,
                targetBundleIdentifier: targetBundleIdentifier,
                selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                allowDroppingExtensions: allowDroppingExtensions,
                persistSigningMaterial: persistence,
                progress: progress
            )
        } catch ALTAppleAPIError.invalidAnisetteData {
            await anisetteProvider.resetProvisioning()
            do {
                return try await signOnce(
                    app: app,
                    account: account,
                    secret: await secretState.value(),
                    deviceIdentifier: deviceIdentifier,
                    originalIPAURL: originalIPAURL,
                    workspaceRoot: workspaceRoot,
                    targetBundleIdentifier: targetBundleIdentifier,
                    selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                    allowDroppingExtensions: allowDroppingExtensions,
                    persistSigningMaterial: persistence,
                    progress: progress
                )
            } catch let failure as ImportFailure {
                throw failure
            } catch {
                let nsError = error as NSError
                throw Self.failure(
                    title: "签名失败",
                    reason: "Apple 返回：\(nsError.domain) \(nsError.code)；\(nsError.localizedDescription)",
                    recovery: "重试",
                    code: "SEAL-SIGN-501"
                )
            }
        }
    }

    private func signOnce(
        app: AppRecord,
        account: AppleAccountRecord,
        secret: AccountSecret,
        deviceIdentifier: String,
        originalIPAURL: URL,
        workspaceRoot: URL,
        targetBundleIdentifier: String?,
        selectedCertificateSerialNumber: String?,
        allowDroppingExtensions: Bool,
        persistSigningMaterial: @escaping @Sendable (AccountSecret, String) async throws -> Void,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> PortalSigningResult {
        var stage: ApplePortalSigningStage = .account
        do {
            try Task.checkCancellation()
            await progress(.preparingAccount)
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
            try Task.checkCancellation()
            guard let team = teams.first(where: { $0.identifier == account.teamID }) else {
                throw Self.failure(
                    title: "账号需要验证",
                    reason: "开发团队不可用",
                    recovery: "重新验证账号",
                    code: "SEAL-AUTH-104"
                )
            }
            let deviceName = await MainActor.run { UIDevice.current.name }
            stage = .device
            _ = try await ensureDevice(
                identifier: deviceIdentifier,
                name: deviceName,
                team: team,
                session: session
            )
            try Task.checkCancellation()

            await progress(.preparingCertificate)
            stage = .certificate
            let identity = try await signingIdentity(
                account: account,
                secret: secret,
                team: team,
                session: session,
                deviceName: deviceName,
                selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                persistSigningMaterial: persistSigningMaterial
            )
            try Task.checkCancellation()

            stage = .packaging
            let prepared = try signingWorkspace.prepare(
                ipaURL: originalIPAURL,
                workspaceRoot: workspaceRoot,
                originalBundleID: app.originalBundleIdentifier,
                teamID: team.identifier,
                targetMainBundleID: targetBundleIdentifier
            )
            try Task.checkCancellation()

            await progress(.preparingAppID)
            stage = .appID
            let profilePreparation = try await provisioningProfiles(
                mappings: prepared.bundleIDMappings,
                mappedMainBundleID: prepared.mappedMainBundleID,
                appName: app.name,
                appURL: prepared.appURL,
                workspace: prepared,
                allowDroppingExtensions: allowDroppingExtensions,
                team: team,
                session: session,
                progress: progress
            )
            try Task.checkCancellation()
            guard let mainProfile = profilePreparation.profiles.first(where: {
                $0.bundleIdentifier == prepared.mappedMainBundleID
            }) else {
                throw Self.failure(
                    title: "无法签名",
                    reason: "主应用描述文件缺失",
                    recovery: "重试",
                    code: "SEAL-PROFILE-303"
                )
            }

            await progress(.signing)
            stage = .signing
            try await signApp(
                at: prepared.appURL,
                team: team,
                certificate: identity.certificate,
                profiles: profilePreparation.profiles
            )
            try Task.checkCancellation()

            let profileBindings = try validateEmbeddedProfiles(
                in: prepared,
                teamID: team.identifier,
                certificateSerialNumber: identity.certificate.serialNumber,
                deviceIdentifier: deviceIdentifier,
                requestedEntitlements: profilePreparation.requestedEntitlements
            )
            guard let mainBinding = profileBindings[prepared.mappedMainBundleID] else {
                throw Self.failure(
                    title: "描述文件校验失败",
                    reason: "签名完成后未找到主应用的 embedded.mobileprovision：\(prepared.mappedMainBundleID)。",
                    recovery: "重新获取描述文件",
                    code: "SEAL-PROFILE-317"
                )
            }

            stage = .packaging
            let signedIPAURL = prepared.rootURL.appending(path: "Signed.ipa")
            try signingWorkspace.package(prepared, outputURL: signedIPAURL)

            return PortalSigningResult(
                mappedMainBundleID: prepared.mappedMainBundleID,
                mappedBundleIdentifiers: prepared.bundleIDMappings,
                expirationDate: mainBinding.expirationDate,
                signedIPAURL: signedIPAURL,
                updatedSecret: identity.secret,
                certificateSerialNumber: identity.certificate.serialNumber,
                certificateMachineIdentifier: identity.certificate.machineIdentifier,
                deviceIdentifier: deviceIdentifier,
                teamID: team.identifier,
                profileBindings: profileBindings,
                droppedExtensionBundleIdentifiers:
                    profilePreparation.droppedExtensionBundleIdentifiers
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch ALTAppleAPIError.invalidAnisetteData {
            throw ALTAppleAPIError(.invalidAnisetteData)
        } catch ALTAppleAPIError.maximumAppIDLimitReached {
            throw Self.failure(
                title: "App ID 名额已满",
                reason: "Apple 返回 App ID 数量已达到账号上限。",
                recovery: "使用其他 Bundle ID 或开发者账号。",
                code: "SEAL-APPID-301"
            )
        } catch ALTAppleAPIError.incorrectCredentials {
            throw Self.failure(
                title: "账号需要验证",
                reason: "Apple ID 会话已失效",
                recovery: "重新验证账号",
                code: "SEAL-AUTH-104"
            )
        } catch ALTAppleAPIError.authenticationHandshakeFailed {
            throw Self.failure(
                title: "账号需要验证",
                reason: "Apple ID 会话已失效",
                recovery: "重新验证账号",
                code: "SEAL-AUTH-104"
            )
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw ApplePortalSigningFailure.make(stage: stage, error: error)
        }
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

    private func ensureDevice(
        identifier: String,
        name: String,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> ALTDevice {
        let devicesBox: LegacyBox<[ALTDevice]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchDevices(
                for: team,
                types: [.iphone, .ipad],
                session: session
            ) { devices, error in
                Self.resume(continuation, value: devices, error: error)
            }
        }
        if let device = devicesBox.value.first(where: { $0.identifier == identifier }) {
            return device
        }
        let deviceBox: LegacyBox<ALTDevice> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.registerDevice(
                name: name,
                identifier: identifier,
                type: .iphone,
                team: team,
                session: session
            ) { device, error in
                Self.resume(continuation, value: device, error: error)
            }
        }
        return deviceBox.value
    }

    private func signingIdentity(
        account: AppleAccountRecord,
        secret: AccountSecret,
        team: ALTTeam,
        session: ALTAppleAPISession,
        deviceName: String,
        selectedCertificateSerialNumber: String?,
        persistSigningMaterial: @escaping @Sendable (AccountSecret, String) async throws -> Void
    ) async throws -> SigningIdentity {
        let certificates = try await fetchCertificates(team: team, session: session)
        try Task.checkCancellation()

        if let selectedCertificateSerialNumber,
           let data = secret.certificateP12,
           let remote = certificates.first(where: {
               $0.serialNumber.caseInsensitiveCompare(selectedCertificateSerialNumber) == .orderedSame
           }),
           let local = try? ALTCertificate(p12Data: data, password: nil),
           local.serialNumber.caseInsensitiveCompare(selectedCertificateSerialNumber) == .orderedSame {
            local.machineIdentifier = remote.machineIdentifier
            return SigningIdentity(certificate: local, secret: secret)
        }

        if let serial = secret.certificateSerialNumber,
           let data = secret.certificateP12,
           let remote = certificates.first(where: {
               $0.serialNumber.caseInsensitiveCompare(serial) == .orderedSame
           }),
           let local = try? ALTCertificate(p12Data: data, password: nil),
           local.serialNumber.caseInsensitiveCompare(serial) == .orderedSame {
            local.machineIdentifier = remote.machineIdentifier
            return SigningIdentity(certificate: local, secret: secret)
        }

        return try await createSigningIdentity(
            secret: secret,
            certificates: certificates,
            team: team,
            session: session,
            deviceName: deviceName,
            persistSigningMaterial: persistSigningMaterial
        )
    }

    private func createSigningIdentity(
        secret: AccountSecret,
        certificates: [ALTCertificate],
        team: ALTTeam,
        session: ALTAppleAPISession,
        deviceName: String,
        persistSigningMaterial: @escaping @Sendable (AccountSecret, String) async throws -> Void
    ) async throws -> SigningIdentity {
        let requested: ALTCertificate
        do {
            let created = try await addCertificate(
                team: team,
                session: session,
                deviceName: deviceName
            )
            try Task.checkCancellation()
            requested = created
        } catch {
            guard Self.isCertificateLimitError(error) else { throw error }
            requested = try await recoverCertificateCapacityAndCreate(
                initialCertificates: certificates,
                protectedSerialNumber: secret.certificateSerialNumber,
                team: team,
                session: session,
                deviceName: deviceName
            )
        }

        var wasPersisted = false
        do {
            let refreshed = try await fetchCertificates(team: team, session: session)
            try Task.checkCancellation()
            guard let certificate = refreshed.first(where: {
                $0.serialNumber.caseInsensitiveCompare(requested.serialNumber) == .orderedSame
            }) else {
                throw Self.failure(
                    title: "证书创建结果不一致",
                    reason: "Apple 已返回新证书，但重新同步后找不到 Serial：\(requested.serialNumber)。",
                    recovery: "重新同步证书",
                    code: "SEAL-CERT-209"
                )
            }
            certificate.privateKey = requested.privateKey
            guard let p12 = certificate.p12Data() else {
                throw Self.failure(
                    title: "无法保存新证书",
                    reason: "Apple 已创建证书，但本机无法将证书与私钥合成 P12。",
                    recovery: "重新创建本机证书",
                    code: "SEAL-CERT-202"
                )
            }

            var updatedSecret = secret
            updatedSecret.certificateP12 = p12
            updatedSecret.certificateSerialNumber = certificate.serialNumber
            updatedSecret.certificateMachineIdentifier = certificate.machineIdentifier

            try await persistSigningMaterial(updatedSecret, certificate.serialNumber)
            wasPersisted = true
            return SigningIdentity(certificate: certificate, secret: updatedSecret)
        } catch {
            guard wasPersisted == false else { throw error }
            let cleanedUp = await cleanUpNewCertificate(
                serialNumber: requested.serialNumber,
                certificate: requested,
                team: team,
                session: session,
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

    private func recoverCertificateCapacityAndCreate(
        initialCertificates: [ALTCertificate],
        protectedSerialNumber: String?,
        team: ALTTeam,
        session: ALTAppleAPISession,
        deviceName: String
    ) async throws -> ALTCertificate {
        let latest = (try? await fetchCertificates(team: team, session: session))
            ?? initialCertificates
        let protected = protectedSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = latest.filter { certificate in
            guard let protected, protected.isEmpty == false else { return true }
            return certificate.serialNumber.caseInsensitiveCompare(protected) != .orderedSame
        }

        for certificate in candidates {
            try Task.checkCancellation()
            guard (try? await revokeCertificate(certificate, team: team, session: session)) != nil else {
                continue
            }
            do {
                let created = try await addCertificate(
                    team: team,
                    session: session,
                    deviceName: deviceName
                )
                try Task.checkCancellation()
                return created
            } catch {
                guard Self.isCertificateLimitError(error) else { throw error }
            }
        }

        throw Self.failure(
            title: "签名失败",
            reason: "Apple 返回：无法创建签名证书",
            recovery: "重试",
            code: "SEAL-CERT-204"
        )
    }

    private func cleanUpNewCertificate(
        serialNumber: String,
        certificate: ALTCertificate,
        team: ALTTeam,
        session: ALTAppleAPISession,
        secret: AccountSecret
    ) async -> Bool {
        if (try? await revokeCertificate(certificate, team: team, session: session)) != nil {
            return true
        }

        await anisetteProvider.resetProvisioning()
        guard let anisette = try? await anisetteProvider.fetch() else { return false }
        let refreshedSession = ALTAppleAPISession(
            dsid: secret.dsid,
            authToken: secret.authToken,
            anisetteData: anisette
        )
        guard let certificates = try? await fetchCertificates(
            team: team,
            session: refreshedSession
        ) else {
            return false
        }
        guard let exactCertificate = certificates.first(where: {
            $0.serialNumber.caseInsensitiveCompare(serialNumber) == .orderedSame
        }) else {
            return true
        }
        return (try? await revokeCertificate(
            exactCertificate,
            team: team,
            session: refreshedSession
        )) != nil
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

    private func fetchCertificates(
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> [ALTCertificate] {
        let box: LegacyBox<[ALTCertificate]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) {
                certificates, error in
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
                machineName: certificateMachineName(team: team, deviceName: deviceName),
                to: team,
                session: session
            ) { certificate, error in
                Self.resume(continuation, value: certificate, error: error)
            }
        }
        return box.value
    }

    private func certificateMachineName(team: ALTTeam, deviceName: String) -> String {
        let sanitizedDevice = deviceName
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let devicePart = sanitizedDevice.isEmpty ? "Device" : String(sanitizedDevice.prefix(18))
        let teamPart = String(team.identifier.prefix(8))
        let timestamp = Int(Date().timeIntervalSince1970)
        return "Apple Development-\(teamPart)-\(devicePart)-\(timestamp)"
    }

    private func revokeCertificate(
        _ certificate: ALTCertificate,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            ALTAppleAPI.shared.revoke(certificate, for: team, session: session) {
                success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? URLError(.badServerResponse)
                    )
                }
            }
        }
    }

    private func provisioningProfiles(
        mappings: [String: String],
        mappedMainBundleID: String,
        appName: String,
        appURL: URL,
        workspace: PreparedSigningWorkspace,
        allowDroppingExtensions: Bool,
        team: ALTTeam,
        session: ALTAppleAPISession,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> ProfilePreparation {
        guard let mainApplication = ALTApplication(fileURL: appURL) else {
            throw Self.failure(
                title: "无法签名",
                reason: "应用结构无效",
                recovery: "检查 IPA",
                code: "SEAL-SIGN-404"
            )
        }
        var applications = [mainApplication.bundleIdentifier: mainApplication]
        for appExtension in mainApplication.appExtensions {
            applications[appExtension.bundleIdentifier] = appExtension
        }

        var existing = try await fetchAppIDs(team: team, session: session)
        var preparedAppIDs: [(original: String, mapped: String, appID: ALTAppID)] = []
        var requestedEntitlements: [String: [String: ProvisioningEntitlementValue]] = [:]
        var droppedExtensionBundleIdentifiers: [String] = []

        // Phase 1: only read/create/update App IDs. No provisioning profile is fetched here.
        for (originalBundleID, mappedBundleID) in mappings.sorted(by: { $0.key < $1.key }) {
            do {
                try Task.checkCancellation()
                var appID: ALTAppID
                if let found = existing.first(where: {
                    ApplePortalAppIDResolver.matches(
                        existingBundleIdentifier: $0.bundleIdentifier,
                        requestedBundleIdentifier: mappedBundleID
                    )
                }) {
                    appID = found
                } else {
                    do {
                        let createdBox: LegacyBox<ALTAppID> =
                            try await withCheckedThrowingContinuation { continuation in
                                let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
                                let appIDNameSource = normalizedName.isEmpty ? mappedBundleID : normalizedName
                                let appIDName = String(appIDNameSource.prefix(50))
                                ALTAppleAPI.shared.addAppID(
                                    withName: appIDName,
                                    bundleIdentifier: mappedBundleID,
                                    team: team,
                                    session: session
                                ) { created, error in
                                    Self.resume(continuation, value: created, error: error)
                                }
                            }
                        appID = createdBox.value
                    } catch ALTAppleAPIError.bundleIdentifierUnavailable {
                        let refreshed = try await fetchAppIDs(team: team, session: session)
                        guard let found = refreshed.first(where: {
                            ApplePortalAppIDResolver.matches(
                                existingBundleIdentifier: $0.bundleIdentifier,
                                requestedBundleIdentifier: mappedBundleID
                            )
                        }) else {
                            throw ALTAppleAPIError(.bundleIdentifierUnavailable)
                        }
                        appID = found
                    }
                    existing.append(appID)
                }

                if let application = applications[mappedBundleID] {
                    let entitlementSource = filteredAppIDEntitlements(from: application, team: team)
                    var entitlementValues: [String: ProvisioningEntitlementValue] = [:]
                    for (entitlement, value) in entitlementSource {
                        guard let converted = ProvisioningEntitlementValue.make(from: value) else {
                            throw Self.failure(
                                title: "应用权限无法解析",
                                reason: "\(mappedBundleID) 的权限 \(entitlement.rawValue) 包含无法校验的值类型。",
                                recovery: "检查 IPA 权限或使用支持该能力的账号",
                                code: "SEAL-ENTITLEMENT-403"
                            )
                        }
                        entitlementValues[entitlement.rawValue] = converted
                    }
                    requestedEntitlements[mappedBundleID] = entitlementValues
                    appID = try await updateFeatures(
                        appID: appID,
                        application: application,
                        team: team,
                        session: session
                    )
                    if team.type != .free {
                        try await assignAppGroups(
                            appID: appID,
                            application: application,
                            team: team,
                            session: session
                        )
                    }
                }
                preparedAppIDs.append((originalBundleID, mappedBundleID, appID))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard mappedBundleID != mappedMainBundleID else { throw error }
                guard allowDroppingExtensions else {
                    throw Self.failure(
                        title: "签名失败",
                        reason: "Apple 返回：扩展无法创建 App ID",
                        recovery: "移除扩展后重试",
                        code: "SEAL-EXT-401"
                    )
                }
                try signingWorkspace.removeExtension(
                    mappedBundleIdentifier: mappedBundleID,
                    from: workspace
                )
                requestedEntitlements.removeValue(forKey: mappedBundleID)
                droppedExtensionBundleIdentifiers.append(originalBundleID)
            }
        }

        // Phase 2: App IDs are settled; now fetch/generate real provisioning profiles.
        await progress(.preparingProfiles)
        var profiles: [ALTProvisioningProfile] = []
        for preparedAppID in preparedAppIDs {
            do {
                try Task.checkCancellation()
                let profile = try await fetchProvisioningProfile(
                    for: preparedAppID.appID,
                    team: team,
                    session: session
                )
                profiles.append(profile)
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as ImportFailure {
                if preparedAppID.mapped == mappedMainBundleID { throw failure }
                guard allowDroppingExtensions else { throw failure }
                try signingWorkspace.removeExtension(
                    mappedBundleIdentifier: preparedAppID.mapped,
                    from: workspace
                )
                requestedEntitlements.removeValue(forKey: preparedAppID.mapped)
                droppedExtensionBundleIdentifiers.append(preparedAppID.original)
            } catch {
                if preparedAppID.mapped == mappedMainBundleID {
                    throw ApplePortalSigningFailure.make(
                        stage: .provisioningProfile,
                        error: error
                    )
                }
                guard allowDroppingExtensions else {
                    throw Self.failure(
                        title: "签名失败",
                        reason: "Apple 返回：扩展无法生成描述文件",
                        recovery: "移除扩展后重试",
                        code: "SEAL-EXT-401"
                    )
                }
                try signingWorkspace.removeExtension(
                    mappedBundleIdentifier: preparedAppID.mapped,
                    from: workspace
                )
                requestedEntitlements.removeValue(forKey: preparedAppID.mapped)
                droppedExtensionBundleIdentifiers.append(preparedAppID.original)
            }
        }

        return ProfilePreparation(
            profiles: profiles,
            requestedEntitlements: requestedEntitlements,
            droppedExtensionBundleIdentifiers: Array(Set(droppedExtensionBundleIdentifiers))
        )
    }


    private func fetchAppIDs(
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> [ALTAppID] {
        let box: LegacyBox<[ALTAppID]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
                Self.resume(continuation, value: appIDs, error: error)
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
                Self.resume(continuation, value: profile, error: error)
            }
        }
        return box.value
    }


    private func updateFeatures(
        appID: ALTAppID,
        application: ALTApplication,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> ALTAppID {
        let filteredEntitlements = filteredAppIDEntitlements(
            from: application,
            team: team
        )
        var features: [ALTFeature: Any] = [:]
        for (entitlement, value) in filteredEntitlements {
            if let feature = ALTFeature(entitlement: entitlement) {
                features[feature] = value
            }
        }
        if team.type != .free,
           let groups = filteredEntitlements[.appGroups] as? [String],
           groups.isEmpty == false {
            features[.appGroups] = true
        }

        // If there is nothing Apple needs to toggle, keep the existing App ID as-is.
        // This avoids sending empty or signer-managed entitlement payloads that Apple
        // rejects as "provided parameters are invalid" for free accounts.
        guard features.isEmpty == false || filteredEntitlements.isEmpty == false else {
            return appID
        }

        guard let updated = appID.copy() as? ALTAppID else {
            throw Self.failure(
                title: "无法签名",
                reason: "应用能力更新失败",
                recovery: "重试",
                code: "SEAL-PROFILE-304"
            )
        }
        updated.features = features
        updated.entitlements = filteredEntitlements
        do {
            return try await submitUpdatedAppID(updated, team: team, session: session)
        } catch {
            guard Self.isInvalidAppIDParameterError(error),
                  team.type == .free,
                  let fallback = appID.copy() as? ALTAppID else {
                throw error
            }
            fallback.features = [:]
            fallback.entitlements = [:]
            return try await submitUpdatedAppID(fallback, team: team, session: session)
        }
    }

    private func filteredAppIDEntitlements(
        from application: ALTApplication,
        team: ALTTeam
    ) -> [ALTEntitlement: Any] {
        let signerManagedEntitlements: Set<String> = [
            "application-identifier",
            "com.apple.developer.team-identifier",
            "keychain-access-groups",
            "get-task-allow"
        ]
        var filtered: [ALTEntitlement: Any] = [:]
        for (entitlement, value) in application.entitlements {
            if signerManagedEntitlements.contains(entitlement.rawValue) {
                continue
            }
            if team.type == .free,
               ALTFreeDeveloperCanUseEntitlement(entitlement) == false {
                continue
            }
            if team.type == .free, entitlement == .appGroups {
                continue
            }
            filtered[entitlement] = value
        }
        return filtered
    }

    private func submitUpdatedAppID(
        _ updated: ALTAppID,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws -> ALTAppID {
        let box: LegacyBox<ALTAppID> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.update(
                updated,
                team: team,
                session: session
            ) { appID, error in
                Self.resume(continuation, value: appID, error: error)
            }
        }
        return box.value
    }

    private static func isInvalidAppIDParameterError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let normalized = "\(nsError.domain) \(nsError.code) \(nsError.localizedDescription) \(String(describing: error))".lowercased()
        return nsError.code == 3001
            || normalized.contains("3001")
            || normalized.contains("provided parameters are invalid")
    }

    private func assignAppGroups(
        appID: ALTAppID,
        application: ALTApplication,
        team: ALTTeam,
        session: ALTAppleAPISession
    ) async throws {
        guard let originalGroups = application.entitlements[.appGroups] as? [String],
              originalGroups.isEmpty == false else { return }
        let mappedIdentifiers = originalGroups.map {
            signingWorkspace.bundleIDMapper.appGroupID(
                original: $0,
                teamID: team.identifier
            )
        }
        let fetchedBox: LegacyBox<[ALTAppGroup]> =
            try await withCheckedThrowingContinuation { continuation in
                ALTAppleAPI.shared.fetchAppGroups(for: team, session: session) {
                    groups, error in
                    Self.resume(continuation, value: groups, error: error)
                }
            }
        var available = fetchedBox.value
        var assigned: [ALTAppGroup] = []
        for identifier in mappedIdentifiers {
            try Task.checkCancellation()
            if let existing = available.first(where: {
                $0.groupIdentifier == identifier
            }) {
                assigned.append(existing)
                continue
            }
            let suffix = identifier.split(separator: ".").last.map(String.init) ?? "Group"
            let createdBox: LegacyBox<ALTAppGroup> =
                try await withCheckedThrowingContinuation { continuation in
                    ALTAppleAPI.shared.addAppGroup(
                        withName: "Seal Group \(suffix)",
                        groupIdentifier: identifier,
                        team: team,
                        session: session
                    ) { group, error in
                        Self.resume(continuation, value: group, error: error)
                    }
                }
            available.append(createdBox.value)
            assigned.append(createdBox.value)
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            ALTAppleAPI.shared.assign(
                appID,
                to: assigned,
                team: team,
                session: session
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? URLError(.badServerResponse)
                    )
                }
            }
        }
    }

    private func validateEmbeddedProfiles(
        in workspace: PreparedSigningWorkspace,
        teamID: String,
        certificateSerialNumber: String,
        deviceIdentifier: String,
        requestedEntitlements: [String: [String: ProvisioningEntitlementValue]]
    ) throws -> [String: ProvisioningProfileBinding] {
        let reader = ProvisioningProfileReader()
        var bindings: [String: ProvisioningProfileBinding] = [:]

        for target in try signingWorkspace.signedBundleTargets(in: workspace) {
            let profileURL = target.bundleURL.appending(path: "embedded.mobileprovision")
            guard FileManager.default.fileExists(atPath: profileURL.path) else {
                throw Self.failure(
                    title: "描述文件校验失败",
                    reason: "\(target.bundleIdentifier) 没有 embedded.mobileprovision。主应用和每个扩展都必须独立包含正确的描述文件。",
                    recovery: "重新获取描述文件",
                    code: "SEAL-PROFILE-318"
                )
            }
            let data = try Data(contentsOf: profileURL)
            let binding = try reader.binding(from: data)
                .validated(
                    expectedTeamID: teamID,
                    expectedBundleID: target.bundleIdentifier,
                    expectedCertificateSerialNumber: certificateSerialNumber,
                    expectedDeviceIdentifier: deviceIdentifier
                )
            try ProvisioningProfileBinding.validateEntitlements(
                requested: requestedEntitlements[target.bundleIdentifier] ?? [:],
                profile: binding.entitlements,
                bundleIdentifier: target.bundleIdentifier
            )
            bindings[target.bundleIdentifier] = binding
        }
        return bindings
    }

    private func signApp(
        at appURL: URL,
        team: ALTTeam,
        certificate: ALTCertificate,
        profiles: [ALTProvisioningProfile]
    ) async throws {
        let signer = ALTSigner(team: team, certificate: certificate)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            signer.signApp(at: appURL, provisioningProfiles: profiles) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? URLError(.cannotCreateFile)
                    )
                }
            }
        }
    }

    private static func resume<Value>(
        _ continuation: CheckedContinuation<LegacyBox<Value>, any Error>,
        value: Value?,
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

private struct SigningIdentity {
    let certificate: ALTCertificate
    let secret: AccountSecret
}

private struct ProfilePreparation {
    let profiles: [ALTProvisioningProfile]
    let requestedEntitlements: [String: [String: ProvisioningEntitlementValue]]
    let droppedExtensionBundleIdentifiers: [String]
}

private actor SigningSecretState {
    private var secret: AccountSecret

    init(_ secret: AccountSecret) {
        self.secret = secret
    }

    func update(_ secret: AccountSecret) {
        self.secret = secret
    }

    func value() -> AccountSecret {
        secret
    }
}

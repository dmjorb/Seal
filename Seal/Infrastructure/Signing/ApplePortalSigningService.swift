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
            details = ("无法连接 Apple 账户", "Apple 账户会话失败。", "检查网络后重新验证账户", "SEAL-AUTH-105")
        case .device:
            details = ("无法注册设备", "Apple 设备注册失败。", "检查设备配对后重试", "SEAL-DEVICE-203")
        case .certificate:
            return certificateFailure(error: error, diagnostic: diagnostic)
        case .appID:
            return appIDFailure(error: error, diagnostic: diagnostic)
        case .provisioningProfile:
            details = ("无法完成签名", "描述文件生成失败。", "重试", "SEAL-PROFILE-303")
        case .signing:
            details = ("无法完成签名", "应用签名失败。", "重试", "SEAL-SIGN-501")
        case .packaging:
            details = ("无法完成签名", "签名包生成失败。", "重试", "SEAL-SIGN-502")
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
                title: "Apple 返回 Bundle ID 不可用",
                reason: "Apple 返回目标 Bundle ID 不可用。",
                recovery: "首次签名更换 Bundle ID；续签继续使用原签名账号与原 Bundle ID。",
                code: "SEAL-APPID-302"
            )
        }

        return ImportFailure(
            title: "Apple App ID 操作失败",
            reason: "Apple 返回 App ID 操作失败。",
            recovery: "重新验证 Apple ID 后重试。",
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
                title: "证书名额已满",
                reason: "Apple 开发证书数量已达到上限。Seal 没有撤销任何证书，也没有自动选择替换对象。",
                recovery: "前往签名证书页面处理旧证书",
                code: "SEAL-CERT-204"
            )
        }

        if normalized.contains("network")
            || normalized.contains("timed out")
            || normalized.contains("cannot connect")
            || nsError.domain == NSURLErrorDomain {
            return ImportFailure(
                title: "证书服务连接失败",
                reason: "连接 Apple 证书服务失败。",
                recovery: "检查网络后重试",
                code: "SEAL-CERT-205"
            )
        }

        if normalized.contains("unauthorized")
            || normalized.contains("authentication")
            || normalized.contains("session")
            || normalized.contains("forbidden") {
            return ImportFailure(
                title: "账号需要重新验证",
                reason: "Apple ID 会话在准备证书时失效。",
                recovery: "重新验证 Apple ID 后重试",
                code: "SEAL-AUTH-104"
            )
        }

        return ImportFailure(
            title: "无法准备证书",
            reason: "Apple 开发证书准备失败。",
            recovery: "重新同步证书后重试",
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
                    title: "无法签名",
                    reason: "Apple 签名服务失败，但 Seal 没有收到明确的失败原因。",
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

            await progress(.preparingProfiles)
            stage = .appID
            let profilePreparation = try await provisioningProfiles(
                mappings: prepared.bundleIDMappings,
                mappedMainBundleID: prepared.mappedMainBundleID,
                appName: app.name,
                appURL: prepared.appURL,
                workspace: prepared,
                allowDroppingExtensions: allowDroppingExtensions,
                team: team,
                session: session
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
                title: "Apple 返回 App ID 名额已满",
                reason: "Apple 返回 App ID 数量已达到账号上限。Seal 不在本地预判断数量。",
                recovery: "等待旧 App ID 过期，或使用 Apple Developer Program 账号。",
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

        if let selectedCertificateSerialNumber {
            guard secret.certificateSerialNumber?.caseInsensitiveCompare(
                selectedCertificateSerialNumber
            ) == .orderedSame,
            let data = secret.certificateP12 else {
                throw Self.failure(
                    title: "所选证书不可用",
                    reason: "所选证书 Serial：\(selectedCertificateSerialNumber) 没有对应的本地 P12 和私钥。Seal 没有自动改用或创建其他证书。",
                    recovery: "在签名证书页面创建本机证书，或明确执行证书迁移",
                    code: "SEAL-CERT-206"
                )
            }

            guard let remote = certificates.first(where: {
                $0.serialNumber.caseInsensitiveCompare(selectedCertificateSerialNumber) == .orderedSame
            }) else {
                throw Self.failure(
                    title: "所选证书已失效",
                    reason: "Apple 当前证书列表中没有 Serial：\(selectedCertificateSerialNumber)。Seal 没有自动申请或切换其他证书。",
                    recovery: "在签名证书页面明确创建或迁移证书",
                    code: "SEAL-CERT-207"
                )
            }

            guard let local = try? ALTCertificate(p12Data: data, password: nil),
                  local.serialNumber.caseInsensitiveCompare(selectedCertificateSerialNumber) == .orderedSame else {
                throw Self.failure(
                    title: "证书私钥损坏",
                    reason: "本地 P12 无法读取，或 P12 Serial 与所选证书不一致：\(selectedCertificateSerialNumber)。",
                    recovery: "在签名证书页面明确执行证书迁移",
                    code: "SEAL-CERT-202"
                )
            }
            local.machineIdentifier = remote.machineIdentifier
            return SigningIdentity(certificate: local, secret: secret)
        }

        if let serial = secret.certificateSerialNumber,
           let data = secret.certificateP12 {
            guard let remote = certificates.first(where: {
                $0.serialNumber.caseInsensitiveCompare(serial) == .orderedSame
            }) else {
                throw Self.failure(
                    title: "本机证书已失效",
                    reason: "Apple 当前证书列表中没有本机保存的 Serial：\(serial)。Seal 没有静默创建新证书。",
                    recovery: "在签名证书页面明确创建本机证书",
                    code: "SEAL-CERT-207"
                )
            }
            guard let local = try? ALTCertificate(p12Data: data, password: nil),
                  local.serialNumber.caseInsensitiveCompare(serial) == .orderedSame else {
                throw Self.failure(
                    title: "证书私钥损坏",
                    reason: "Seal 无法读取本机保存的 P12，或 P12 Serial 与记录不一致：\(serial)。",
                    recovery: "在签名证书页面明确执行证书迁移",
                    code: "SEAL-CERT-202"
                )
            }
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
            requested = try await addCertificate(
                team: team,
                session: session,
                deviceName: deviceName
            )
            try Task.checkCancellation()
        } catch {
            guard Self.isCertificateLimitError(error) else { throw error }
            let descriptions = certificates.map { certificate in
                let name = certificate.machineName ?? "Apple Development"
                return "\(name) [Serial: \(certificate.serialNumber)]"
            }.joined(separator: "、")
            let suffix = descriptions.isEmpty ? "" : " Apple 当前证书：\(descriptions)。"
            throw Self.failure(
                title: "证书名额已满",
                reason: "Apple 拒绝创建新的开发证书。Seal 没有撤销任何证书，也没有自动选择替换对象。\(suffix)",
                recovery: "前往签名证书页面，选择完整 Serial 并确认撤销",
                code: "SEAL-CERT-204"
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
                    title: "新证书回滚失败",
                    reason: "Apple 已创建证书 Serial：\(requested.serialNumber)，但 P12 保存前发生失败，且 Seal 无法确认该证书已回滚。Seal 没有创建第二张证书，也没有撤销其他证书。",
                    recovery: "前往签名证书页面同步并处理此完整 Serial",
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
        return "Seal-\(teamPart)-\(devicePart)-\(timestamp)"
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
        session: ALTAppleAPISession
    ) async throws -> ProfilePreparation {
        guard let mainApplication = ALTApplication(fileURL: appURL) else {
            throw Self.failure(
                title: "无法签名",
                reason: "应用结构无效",
                recovery: "检查 IPA",
                code: "SEAL-SIGN-404"
            )
        }
        var applications = [
            mainApplication.bundleIdentifier: mainApplication
        ]
        for appExtension in mainApplication.appExtensions {
            applications[appExtension.bundleIdentifier] = appExtension
        }
        let existingBox: LegacyBox<[ALTAppID]> = try await withCheckedThrowingContinuation {
            continuation in
            ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
                Self.resume(continuation, value: appIDs, error: error)
            }
        }
        var existing = existingBox.value
        var profiles: [ALTProvisioningProfile] = []
        var requestedEntitlements: [String: [String: ProvisioningEntitlementValue]] = [:]
        var droppedExtensionBundleIdentifiers: [String] = []

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
                                let preferredName = "Seal \(appName)"
                                let appIDName = preferredName.allSatisfy(\.isASCII)
                                    ? String(preferredName.prefix(50))
                                    : mappedBundleID
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
                    var entitlementValues: [String: ProvisioningEntitlementValue] = [:]
                    for (entitlement, value) in application.entitlements {
                        guard let converted = ProvisioningEntitlementValue.make(from: value) else {
                            throw Self.failure(
                                title: "应用权限无法解析",
                                reason: "\(mappedBundleID) 的权限 \(entitlement.rawValue) 包含 Seal 无法安全校验的值类型。Seal 没有静默删除该权限。",
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

                let profile: ALTProvisioningProfile
                do {
                    profile = try await fetchProvisioningProfile(
                        for: appID,
                        team: team,
                        session: session
                    )
                } catch let failure as ImportFailure {
                    throw failure
                } catch {
                    throw ApplePortalSigningFailure.make(
                        stage: .provisioningProfile,
                        error: error
                    )
                }
                profiles.append(profile)
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard mappedBundleID != mappedMainBundleID else { throw error }
                guard allowDroppingExtensions else {
                    throw Self.failure(
                        title: "扩展无法签名",
                        reason: "此 IPA 包含无法用当前账号签名的扩展：\(originalBundleID)。继续重试可移除扩展，主 App 仍可安装，但 Widget、分享扩展或通知扩展等功能可能不可用。",
                        recovery: "移除扩展后重试",
                        code: "SEAL-EXT-401"
                    )
                }
                try signingWorkspace.removeExtension(
                    mappedBundleIdentifier: mappedBundleID,
                    from: workspace
                )
                droppedExtensionBundleIdentifiers.append(originalBundleID)
            }
        }
        return ProfilePreparation(
            profiles: profiles,
            requestedEntitlements: requestedEntitlements,
            droppedExtensionBundleIdentifiers: droppedExtensionBundleIdentifiers
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
        var features: [ALTFeature: Any] = [:]
        for (entitlement, value) in application.entitlements {
            if team.type == .free,
               ALTFreeDeveloperCanUseEntitlement(entitlement) == false {
                continue
            }
            if let feature = ALTFeature(entitlement: entitlement) {
                features[feature] = value
            }
        }
        let hasAppGroups = team.type != .free
            && ((application.entitlements[.appGroups] as? [String])?.isEmpty == false)
        features[.appGroups] = hasAppGroups

        guard let updated = appID.copy() as? ALTAppID else {
            throw Self.failure(
                title: "无法签名",
                reason: "应用能力更新失败",
                recovery: "重试",
                code: "SEAL-PROFILE-304"
            )
        }
        updated.features = features
        updated.entitlements = application.entitlements
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

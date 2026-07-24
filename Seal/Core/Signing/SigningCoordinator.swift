import Foundation
@preconcurrency import AltSign

actor SigningCoordinator {
    private let appStore: any AppStore
    private let accountRepository: any AccountRepository
    private let keychain: KeychainVault
    private let fileStore: AppFileStore
    private let installChannel: any InstallChannel
    private let portal: ApplePortalSigningService

    init(
        appStore: any AppStore,
        accountRepository: any AccountRepository,
        keychain: KeychainVault,
        fileStore: AppFileStore,
        installChannel: any InstallChannel,
        portal: ApplePortalSigningService = ApplePortalSigningService()
    ) {
        self.appStore = appStore
        self.accountRepository = accountRepository
        self.keychain = keychain
        self.fileStore = fileStore
        self.installChannel = installChannel
        self.portal = portal
    }

    func signAndInstall(
        appID: UUID,
        accountID: UUID,
        requestedBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String? = nil,
        allowDroppingExtensions: Bool = false,
        installAfterSigning: Bool = true,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord {
        guard var app = try await appStore.fetchAll().first(where: { $0.id == appID }) else {
            throw Self.failure(
                reason: "应用记录不存在",
                recovery: "重新导入 IPA",
                code: "SEAL-SIGN-404"
            )
        }
        guard var account = try await accountRepository.fetchAll().first(where: {
            $0.id == accountID
        }) else {
            throw Self.failure(
                reason: "签名账号记录不存在",
                recovery: "添加 Apple ID",
                code: "SEAL-AUTH-105"
            )
        }
        guard var secret = try await keychain.load(accountID: accountID) else {
            account.status = .needsVerification
            account.verificationFailureReason = .localCredentialsMissing
            try await persistAccountState(account)
            throw Self.failure(
                reason: "本机 Keychain 中缺少当前 Apple ID 的登录凭据。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-AUTH-105"
            )
        }
        try await validateAccountSession(
            account: account,
            secret: secret,
            selectedAccountID: accountID
        )
        let normalizedSigningMaterial = try await normalizeCachedCertificateState(
            account: account,
            secret: secret
        )
        account = normalizedSigningMaterial.account
        secret = normalizedSigningMaterial.secret
        try SigningCertificateSelectionPolicy.validateAccountAndTeam(
            for: app,
            account: account
        )
        let effectiveCertificateSerialNumber = try SigningCertificateSelectionPolicy
            .resolvedSerialNumber(
                for: app,
                account: account,
                requestedSerialNumber: selectedCertificateSerialNumber
            )
        let targetBundleIdentifier = try BundleIDPolicy.targetBundleIdentifier(
            for: app,
            requestedBundleIdentifier: requestedBundleIdentifier
        )
        let workspaceRoot = try await fileStore.signingWorkspace(appID: appID)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        let originalState = app.state
        let originalSecret = secret
        let originalAccount = account
        var didPersistNewSignedArtifact = false

        do {
            try Task.checkCancellation()
            try await updateState(appID: appID, stage: .waitingForChannel)
            await progress(.waitingForChannel)
            let deviceIdentifier = try await installChannel.start()

            if installAfterSigning,
               let cachedInstall = try await installCachedSignedIPAIfPossible(
                app: app,
                account: account,
                targetBundleIdentifier: targetBundleIdentifier,
                certificateSerialNumber: effectiveCertificateSerialNumber,
                deviceIdentifier: deviceIdentifier,
                progress: progress
            ) {
                return cachedInstall
            }

            let originalURL = try await fileStore.fileURL(
                relativePath: app.ipaRelativePath
            )
            let preferredIconData: Data?
            if let preferredIconPath = app.preferredIconRelativePath {
                preferredIconData = try? await fileStore.read(relativePath: preferredIconPath)
            } else {
                preferredIconData = nil
            }
            let portalResult = try await portal.sign(
                app: app,
                account: account,
                secret: secret,
                deviceIdentifier: deviceIdentifier,
                originalIPAURL: originalURL,
                workspaceRoot: workspaceRoot,
                targetBundleIdentifier: targetBundleIdentifier,
                preferredIconData: preferredIconData,
                selectedCertificateSerialNumber: effectiveCertificateSerialNumber,
                allowDroppingExtensions: allowDroppingExtensions,
                persistSigningMaterial: { updatedSecret, serialNumber in
                    try await self.persistNewSigningMaterial(
                        updatedSecret,
                        serialNumber: serialNumber,
                        accountID: accountID,
                        originalSecret: originalSecret,
                        originalAccount: originalAccount
                    )
                },
                progress: { stage in
                    await progress(stage)
                }
            )

            account.certificateSerialNumber = portalResult.certificateSerialNumber
            account.selectedCertificateSerialNumber = portalResult.certificateSerialNumber
            account.status = .verified
            account.verificationFailureReason = nil
            account.lastVerifiedAt = Date()
            try await accountRepository.save(account)

            let signedPath = try await fileStore.storeSignedIPA(
                sourceURL: portalResult.signedIPAURL,
                appID: appID
            )
            let signedSHA256 = try await fileStore.sha256(relativePath: signedPath)
            applySigningResult(
                portalResult,
                signedPath: signedPath,
                accountID: accountID,
                to: &app
            )
            app.signedIPASHA256 = signedSHA256
            app.signedArtifactStatus = originalState == .installed ? .installed : .available
            app.lastInstallFailureCode = nil
            app.lastInstallFailureReason = nil
            app.state = originalState == .installed ? .installed : .signed
            try await appStore.save(app)
            didPersistNewSignedArtifact = true

            guard installAfterSigning else { return app }

            let installed = try await installSignedIPA(
                app: app,
                signedPath: signedPath,
                bundleIdentifier: portalResult.mappedMainBundleID,
                expirationDate: portalResult.expirationDate,
                progress: progress
            )
            return installed
        } catch is CancellationError {
            if app.signedIPARelativePath != nil, originalState != .installed {
                app.state = .signed
            } else {
                app.state = originalState
            }
            try await persistAppState(app)
            throw CancellationError()
        } catch let failure as ImportFailure {
            if let reason = AppleServiceFailurePolicy.verificationFailureReason(for: failure) {
                account.status = .needsVerification
                account.verificationFailureReason = reason
                try await persistAccountState(account)
            }
            if didPersistNewSignedArtifact || failure.code.hasPrefix("SEAL-INSTALL-") {
                app.state = originalState == .installed ? .installed : .signed
                app.signedArtifactStatus = .installFailed
                app.lastInstallFailureCode = failure.code
                app.lastInstallFailureReason = failure.reason
            } else {
                app.state = originalState == .installed ? .installed : originalState
            }
            try await persistAppState(app)
            throw failure
        } catch {
            if didPersistNewSignedArtifact {
                app.state = originalState == .installed ? .installed : .signed
                app.signedArtifactStatus = .installFailed
                app.lastInstallFailureCode = "SEAL-INSTALL-500"
                app.lastInstallFailureReason = "安装流程遇到未预期错误，技术信息已写入脱敏日志。"
            } else {
                app.state = originalState == .installed ? .installed : originalState
            }
            try await persistAppState(app)
            throw error
        }
    }

    func signOnly(
        appID: UUID,
        accountID: UUID,
        requestedBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String? = nil,
        allowDroppingExtensions: Bool = false,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord {
        try await signAndInstall(
            appID: appID,
            accountID: accountID,
            requestedBundleIdentifier: requestedBundleIdentifier,
            selectedCertificateSerialNumber: selectedCertificateSerialNumber,
            allowDroppingExtensions: allowDroppingExtensions,
            installAfterSigning: false,
            progress: progress
        )
    }

    func installSignedArtifact(
        appID: UUID,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord {
        guard var app = try await appStore.fetchAll().first(where: { $0.id == appID }),
              let signedPath = app.signedIPARelativePath,
              let expectedSHA256 = app.signedIPASHA256,
              let bundleIdentifier = app.mappedBundleIdentifier,
              let expirationDate = app.provisioningProfileExpirationDate else {
            throw Self.failure(
                reason: "已签名 IPA 记录不完整。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-710"
            )
        }
        guard try await fileStore.exists(relativePath: signedPath) else {
            app.signedArtifactStatus = .missing
            try await persistAppState(app)
            throw Self.failure(
                reason: "本机保存的已签名 IPA 文件缺失。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-711"
            )
        }
        guard try await fileStore.validateSHA256(relativePath: signedPath, expected: expectedSHA256) else {
            app.signedArtifactStatus = .damaged
            try await persistAppState(app)
            throw Self.failure(
                reason: "已签名 IPA 的 SHA-256 校验不一致。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-712"
            )
        }
        guard expirationDate > Date() else {
            app.signedArtifactStatus = .expired
            try await persistAppState(app)
            throw Self.failure(
                reason: "已签名 IPA 的描述文件已经过期。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-713"
            )
        }
        guard BundleIDPolicy.validationError(for: bundleIdentifier) == nil else {
            app.signedArtifactStatus = .damaged
            try await persistAppState(app)
            throw Self.failure(
                reason: "已签名 IPA 的 Bundle ID 记录不完整或格式无效。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-716"
            )
        }

        await progress(.waitingForChannel)
        let currentDeviceIdentifier = try await installChannel.start()
        if let mainTarget = app.signingTargets.first(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) {
            guard mainTarget.profileExpirationDate > Date(),
                  mainTarget.deviceIdentifiers.contains(where: {
                      $0.caseInsensitiveCompare(currentDeviceIdentifier) == .orderedSame
                  }) else {
                app.signedArtifactStatus = .deviceUnavailable
                try await persistAppState(app)
                throw Self.failure(
                    reason: "当前设备不在此已签名 IPA 的描述文件设备列表中，或描述文件已经过期。",
                    recovery: "重新签名",
                    code: "SEAL-INSTALL-714"
                )
            }
            if let signingTeamID = app.signingTeamID,
               mainTarget.teamIdentifier.caseInsensitiveCompare(signingTeamID) != .orderedSame {
                app.signedArtifactStatus = .damaged
                try await persistAppState(app)
                throw Self.failure(
                    reason: "已签名 IPA 的 Team 与保存的签名记录不一致。",
                    recovery: "重新签名",
                    code: "SEAL-INSTALL-717"
                )
            }
            if let serial = app.certificateSerialNumber {
                let expected = serial.filter(\.isHexDigit).uppercased()
                let serials = Set(mainTarget.certificateSerialNumbers.map {
                    $0.filter(\.isHexDigit).uppercased()
                })
                guard serials.contains(expected) else {
                    app.signedArtifactStatus = .damaged
                    try await persistAppState(app)
                    throw Self.failure(
                        reason: "已签名 IPA 的描述文件不包含保存的签名证书。",
                        recovery: "重新签名",
                        code: "SEAL-INSTALL-718"
                    )
                }
            }
        } else if let signedDeviceIdentifier = app.signedDeviceIdentifier,
                  signedDeviceIdentifier.caseInsensitiveCompare(currentDeviceIdentifier) != .orderedSame {
            app.signedArtifactStatus = .deviceUnavailable
            try await persistAppState(app)
            throw Self.failure(
                reason: "当前设备不在此签名包使用的设备记录中。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-714"
            )
        }

        do {
            return try await installSignedIPA(
                app: app,
                signedPath: signedPath,
                bundleIdentifier: bundleIdentifier,
                expirationDate: expirationDate,
                progress: progress
            )
        } catch let failure as ImportFailure {
            app.state = app.state == .installed ? .installed : .signed
            app.signedArtifactStatus = .installFailed
            app.lastInstallFailureCode = failure.code
            app.lastInstallFailureReason = failure.reason
            try await persistAppState(app)
            throw failure
        } catch {
            app.state = app.state == .installed ? .installed : .signed
            app.signedArtifactStatus = .installFailed
            app.lastInstallFailureCode = "SEAL-INSTALL-500"
            app.lastInstallFailureReason = "安装流程遇到未预期错误，技术信息已写入脱敏日志。"
            try await persistAppState(app)
            throw error
        }
    }

    private func persistNewSigningMaterial(
        _ updatedSecret: AccountSecret,
        serialNumber: String,
        accountID: UUID,
        originalSecret: AccountSecret,
        originalAccount: AppleAccountRecord
    ) async throws {
        do {
            try await keychain.save(updatedSecret, for: accountID)
            guard let reloaded = try await keychain.load(accountID: accountID),
                  reloaded.certificateSerialNumber?.caseInsensitiveCompare(serialNumber) == .orderedSame,
                  let p12 = reloaded.certificateP12,
                  let certificate = try? ALTCertificate(p12Data: p12, password: nil),
                  certificate.serialNumber.caseInsensitiveCompare(serialNumber) == .orderedSame else {
                throw Self.failure(
                    reason: "Apple 返回：无法创建签名证书",
                    recovery: "重试",
                    code: "SEAL-CERT-210"
                )
            }

            var updatedAccount = originalAccount
            updatedAccount.certificateSerialNumber = serialNumber
            updatedAccount.selectedCertificateSerialNumber = serialNumber
            updatedAccount.status = .verified
            updatedAccount.verificationFailureReason = nil
            updatedAccount.lastVerifiedAt = Date()
            try await accountRepository.save(updatedAccount)
        } catch {
            let originalError = error
            var rollbackFailures: [String] = []
            do {
                try await keychain.save(originalSecret, for: accountID)
            } catch {
                rollbackFailures.append("Keychain")
            }
            do {
                try await accountRepository.save(originalAccount)
            } catch {
                rollbackFailures.append("账号记录")
            }
            if rollbackFailures.isEmpty == false {
                throw Self.failure(
                    reason: "证书保存失败，且本地补偿未完整完成（\(rollbackFailures.joined(separator: "、"))）。",
                    recovery: "重新验证 Apple ID 后检查证书状态",
                    code: "SEAL-CERT-215"
                )
            }
            throw originalError
        }
    }

    private func applySigningResult(
        _ result: PortalSigningResult,
        signedPath: String,
        accountID: UUID,
        to app: inout AppRecord
    ) {
        let mainBinding = result.profileBindings[result.mappedMainBundleID]
        app.mappedBundleIdentifier = result.mappedMainBundleID
        app.preferredBundleIdentifier = result.mappedMainBundleID
        app.accountID = accountID
        app.signingTeamID = result.teamID
        app.certificateSerialNumber = result.certificateSerialNumber
        app.signedDeviceIdentifier = result.deviceIdentifier
        app.signedIPARelativePath = signedPath
        app.provisioningProfileUUID = mainBinding?.profileUUID
        app.provisioningProfileName = mainBinding?.profileName
        app.provisioningProfileCreationDate = mainBinding?.creationDate
        app.provisioningProfileExpirationDate = mainBinding?.expirationDate
        app.entitlementValidationStatus = "已按 embedded.mobileprovision 校验"
        app.capabilityValidationStatus = "已按 Apple App ID 与描述文件校验"
        app.lastSignedAt = Date()
        app.removedExtensionBundleIdentifiers = result.droppedExtensionBundleIdentifiers
        app.signingTargets = result.profileBindings.values
            .map(SigningTargetRecord.init(binding:))
            .sorted { $0.bundleIdentifier < $1.bundleIdentifier }

        app.extensions.removeAll {
            result.droppedExtensionBundleIdentifiers.contains(
                $0.originalBundleIdentifier
            )
        }
        for index in app.extensions.indices {
            let mapped = result.mappedBundleIdentifiers[
                app.extensions[index].originalBundleIdentifier
            ]
            app.extensions[index].mappedBundleIdentifier = mapped
            if let mapped, let binding = result.profileBindings[mapped] {
                app.extensions[index].provisioningProfileUUID = binding.profileUUID
                app.extensions[index].provisioningProfileName = binding.profileName
                app.extensions[index].provisioningProfileExpirationDate = binding.expirationDate
                app.extensions[index].certificateSerialNumber = result.certificateSerialNumber
            }
        }
    }

    private func installCachedSignedIPAIfPossible(
        app: AppRecord,
        account: AppleAccountRecord,
        targetBundleIdentifier: String,
        certificateSerialNumber: String?,
        deviceIdentifier: String,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord? {
        guard let signedPath = app.signedIPARelativePath,
              let expectedSHA256 = app.signedIPASHA256,
              let mappedBundleIdentifier = app.mappedBundleIdentifier,
              mappedBundleIdentifier.caseInsensitiveCompare(targetBundleIdentifier) == .orderedSame,
              app.accountID == account.id,
              app.signingTeamID?.caseInsensitiveCompare(account.teamID) == .orderedSame,
              let storedSerial = app.certificateSerialNumber,
              let certificateSerialNumber,
              storedSerial.caseInsensitiveCompare(certificateSerialNumber) == .orderedSame,
              app.signedDeviceIdentifier?.caseInsensitiveCompare(deviceIdentifier) == .orderedSame,
              let pendingExpiration = app.provisioningProfileExpirationDate,
              pendingExpiration > Date(),
              app.state != .installed || app.expiryDate != pendingExpiration else {
            return nil
        }

        do {
            _ = try await fileStore.fileURL(relativePath: signedPath)
            guard try await fileStore.validateSHA256(
                relativePath: signedPath,
                expected: expectedSHA256
            ) else { return nil }
        } catch {
            return nil
        }
        return try await installSignedIPA(
            app: app,
            signedPath: signedPath,
            bundleIdentifier: mappedBundleIdentifier,
            expirationDate: pendingExpiration,
            progress: progress
        )
    }

    private func installSignedIPA(
        app: AppRecord,
        signedPath: String,
        bundleIdentifier: String,
        expirationDate: Date,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord {
        var updated = app
        try await updateState(appID: app.id, stage: .installing)
        await progress(.installing)
        let signedData = try await fileStore.read(relativePath: signedPath)

        if app.isSeal {
            // Persist the real signed-profile expiry before iOS replaces this running app.
            updated.state = .installed
            updated.signedArtifactStatus = .installed
            updated.lastInstallFailureCode = nil
            updated.lastInstallFailureReason = nil
            updated.expiryDate = expirationDate
            updated.lastInstalledAt = Date()
            try await appStore.save(updated)
            try await installChannel.install(
                ipaData: signedData,
                bundleID: bundleIdentifier,
                isSelfReplacement: true
            )
            return updated
        }

        try await installChannel.install(
            ipaData: signedData,
            bundleID: bundleIdentifier,
            isSelfReplacement: false
        )

        try await updateState(appID: app.id, stage: .verifying)
        await progress(.verifying)
        try await installChannel.verifyInstalled(bundleID: bundleIdentifier)

        updated.state = .installed
        updated.signedArtifactStatus = .installed
        updated.lastInstallFailureCode = nil
        updated.lastInstallFailureReason = nil
        updated.expiryDate = expirationDate
        updated.lastInstalledAt = Date()
        try await appStore.save(updated)
        return updated
    }

    private func validateAccountSession(
        account: AppleAccountRecord,
        secret: AccountSecret,
        selectedAccountID: UUID
    ) async throws {
        guard secret.accountIdentifier == account.accountIdentifier else {
            throw Self.failure(
                reason: "本地 Keychain 凭据与当前 Apple ID 记录不一致。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-AUTH-106"
            )
        }

        guard account.teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw Self.failure(
                reason: "此 Apple ID 没有可用 Team ID，无法创建 App ID 或证书。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-AUTH-109"
            )
        }
    }

    private func normalizeCachedCertificateState(
        account: AppleAccountRecord,
        secret: AccountSecret
    ) async throws -> (account: AppleAccountRecord, secret: AccountSecret) {
        var updatedAccount = account
        var updatedSecret = secret
        var accountChanged = false

        let localCertificateSerial: String? = {
            guard let p12 = secret.certificateP12,
                  let certificate = try? ALTCertificate(p12Data: p12, password: nil) else {
                return nil
            }
            return certificate.serialNumber
        }()
        let storedSerial = secret.certificateSerialNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsableLocalPrivateKey = {
            guard let storedSerial, storedSerial.isEmpty == false,
                  let localCertificateSerial else { return false }
            return storedSerial.caseInsensitiveCompare(localCertificateSerial) == .orderedSame
        }()

        if hasUsableLocalPrivateKey == false,
           secret.certificateSerialNumber != nil || secret.certificateP12 != nil {
            try await keychain.clearSigningMaterial(accountID: account.id)
            updatedSecret.certificateP12 = nil
            updatedSecret.certificateSerialNumber = nil
            updatedSecret.certificateMachineIdentifier = nil
            updatedAccount.certificateSerialNumber = nil
            updatedAccount.selectedCertificateSerialNumber = nil
            accountChanged = true
        } else {
            if updatedAccount.certificateSerialNumber != storedSerial {
                updatedAccount.certificateSerialNumber = storedSerial
                accountChanged = true
            }
            if updatedAccount.selectedCertificateSerialNumber != storedSerial {
                updatedAccount.selectedCertificateSerialNumber = storedSerial
                accountChanged = true
            }
        }

        if accountChanged {
            try await accountRepository.save(updatedAccount)
        }
        return (updatedAccount, updatedSecret)
    }

    private func persistAppState(_ app: AppRecord) async throws {
        do {
            try await appStore.save(app)
        } catch {
            throw Self.failure(
                reason: "签名状态未能写入本机数据库。",
                recovery: "检查本机存储空间后重试",
                code: "SEAL-SIGN-DB-001"
            )
        }
    }

    private func persistAccountState(_ account: AppleAccountRecord) async throws {
        do {
            try await accountRepository.save(account)
        } catch {
            throw Self.failure(
                reason: "Apple ID 状态未能写入本机数据库。",
                recovery: "检查本机存储空间后重试",
                code: "SEAL-AUTH-DB-001"
            )
        }
    }

    private func updateState(appID: UUID, stage: SigningStage) async throws {
        guard var app = try await appStore.fetchAll().first(where: {
            $0.id == appID
        }) else { return }
        app.state = stage.appState
        try await appStore.save(app)
    }

    private static func failure(
        reason: String,
        recovery: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(
            title: "无法完成签名",
            reason: reason,
            recovery: recovery,
            code: code
        )
    }
}

private extension SigningStage {
    var appState: AppState {
        switch self {
        case .waitingForChannel: .waitingForInstallChannel
        case .preparingAccount: .waitingForAccount
        case .preparingCertificate: .preparingCertificate
        case .preparingAppID, .preparingProfiles: .preparingProfiles
        case .signing: .signing
        case .installing: .installing
        case .verifying: .verifying
        }
    }
}

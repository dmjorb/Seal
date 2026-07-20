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
        }), let secret = try await keychain.load(accountID: accountID) else {
            throw Self.failure(
                reason: "签名账号不可用",
                recovery: "添加 Apple ID",
                code: "SEAL-AUTH-105"
            )
        }
        try await validateAccountSession(
            account: account,
            secret: secret,
            selectedAccountID: accountID
        )
        account = try await normalizeCachedCertificateState(
            account: account,
            secret: secret
        )
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
        try await validateSelfAppRenewalContext(
            app: app,
            selectedAccountID: accountID,
            selectedAccount: account,
            targetBundleIdentifier: targetBundleIdentifier
        )

        let workspaceRoot = try await fileStore.signingWorkspace(appID: appID)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        let originalState = app.state
        let originalSecret = secret
        let originalAccount = account

        do {
            try Task.checkCancellation()
            try await updateState(appID: appID, stage: .waitingForChannel)
            await progress(.waitingForChannel)
            let deviceIdentifier = try await installChannel.start()

            if let cached = try await installCachedSignedIPAIfPossible(
                app: app,
                account: account,
                targetBundleIdentifier: targetBundleIdentifier,
                certificateSerialNumber: effectiveCertificateSerialNumber,
                deviceIdentifier: deviceIdentifier,
                progress: progress
            ) {
                return cached
            }

            let originalURL = try await fileStore.fileURL(
                relativePath: app.ipaRelativePath
            )
            let portalResult = try await portal.sign(
                app: app,
                account: account,
                secret: secret,
                deviceIdentifier: deviceIdentifier,
                originalIPAURL: originalURL,
                workspaceRoot: workspaceRoot,
                targetBundleIdentifier: targetBundleIdentifier,
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
                    try? await self.updateState(appID: appID, stage: stage)
                    await progress(stage)
                }
            )

            account.certificateSerialNumber = portalResult.certificateSerialNumber
            account.selectedCertificateSerialNumber = portalResult.certificateSerialNumber
            account.status = .verified
            account.lastVerifiedAt = Date()
            try await accountRepository.save(account)

            let signedPath = try await fileStore.storeSignedIPA(
                sourceURL: portalResult.signedIPAURL,
                appID: appID
            )
            applySigningResult(
                portalResult,
                signedPath: signedPath,
                accountID: accountID,
                to: &app
            )
            app.state = originalState == .installed ? .installed : .waitingForInstallChannel
            try await appStore.save(app)

            let installed = try await installSignedIPA(
                app: app,
                signedPath: signedPath,
                bundleIdentifier: portalResult.mappedMainBundleID,
                expirationDate: portalResult.expirationDate,
                progress: progress
            )
            return installed
        } catch is CancellationError {
            app.state = originalState
            try? await appStore.save(app)
            throw CancellationError()
        } catch let failure as ImportFailure {
            if failure.code.hasPrefix("SEAL-AUTH-") {
                account.status = .needsVerification
                try? await accountRepository.save(account)
            }
            app.state = originalState == .installed ? .installed : .failedRecoverable
            try? await appStore.save(app)
            throw failure
        } catch {
            app.state = originalState == .installed ? .installed : .failedRecoverable
            try? await appStore.save(app)
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
                    reason: "新证书 P12 写入 Keychain 后无法完整读取，或 Serial 不一致：\(serialNumber)。",
                    recovery: "解锁设备后重新创建证书",
                    code: "SEAL-CERT-210"
                )
            }

            var updatedAccount = originalAccount
            updatedAccount.certificateSerialNumber = serialNumber
            updatedAccount.selectedCertificateSerialNumber = serialNumber
            updatedAccount.status = .verified
            updatedAccount.lastVerifiedAt = Date()
            try await accountRepository.save(updatedAccount)
        } catch {
            try? await keychain.save(originalSecret, for: accountID)
            try? await accountRepository.save(originalAccount)
            throw error
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
            SelfRenewalTracker.markPending(
                bundleIdentifier: bundleIdentifier,
                version: app.version
            )
        }
        try await installChannel.install(
            ipaData: signedData,
            bundleID: bundleIdentifier
        )

        try await updateState(appID: app.id, stage: .verifying)
        await progress(.verifying)
        try await installChannel.verifyInstalled(bundleID: bundleIdentifier)

        updated.state = .installed
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
            try? await keychain.delete(accountID: selectedAccountID)
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
    ) async throws -> AppleAccountRecord {
        var updated = account
        var changed = false

        if updated.certificateSerialNumber != secret.certificateSerialNumber {
            updated.certificateSerialNumber = secret.certificateSerialNumber
            changed = true
        }

        if secret.certificateP12 == nil, secret.certificateSerialNumber != nil {
            try await keychain.clearSigningMaterial(accountID: account.id)
            if updated.selectedCertificateSerialNumber == secret.certificateSerialNumber {
                updated.selectedCertificateSerialNumber = nil
            }
            updated.certificateSerialNumber = nil
            changed = true
        } else if updated.selectedCertificateSerialNumber == nil,
                  let serial = secret.certificateSerialNumber,
                  secret.certificateP12 != nil {
            updated.selectedCertificateSerialNumber = serial
            changed = true
        }

        if changed {
            try await accountRepository.save(updated)
        }
        return updated
    }

    private func validateSelfAppRenewalContext(
        app: AppRecord,
        selectedAccountID: UUID,
        selectedAccount: AppleAccountRecord,
        targetBundleIdentifier: String
    ) async throws {
        guard app.isSeal else { return }

        let currentBundleIdentifier = BundleIDPolicy.currentSealBundleIdentifier()
            ?? app.mappedBundleIdentifier
            ?? app.preferredBundleIdentifier
            ?? app.originalBundleIdentifier
        let currentSigningTeamID = await Self.currentInstalledSealTeamIdentifier()
        try SelfRenewalContextValidator.validate(
            currentBundleIdentifier: currentBundleIdentifier,
            targetBundleIdentifier: targetBundleIdentifier,
            currentSigningTeamIdentifier: currentSigningTeamID,
            selectedAccount: selectedAccount,
            boundAccountID: app.accountID,
            selectedAccountID: selectedAccountID
        )
    }

    @MainActor
    private static func currentInstalledSealTeamIdentifier() -> String? {
        guard let profileURL = Bundle.main.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ), let data = try? Data(contentsOf: profileURL, options: .mappedIfSafe),
           let summary = try? ProvisioningProfileReader().summary(from: data) else {
            return nil
        }
        return summary.teamIdentifier
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
        case .preparingProfiles: .preparingProfiles
        case .signing: .signing
        case .installing: .installing
        case .verifying: .verifying
        }
    }
}

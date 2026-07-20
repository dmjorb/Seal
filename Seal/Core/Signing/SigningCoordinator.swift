import Foundation

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
        allowDroppingExtensions: Bool = false,
        allowCertificateReplacement: Bool = false,
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

        do {
            try Task.checkCancellation()
            try await updateState(appID: appID, stage: .waitingForChannel)
            await progress(.waitingForChannel)
            let deviceIdentifier = try await installChannel.start()
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
                allowDroppingExtensions: allowDroppingExtensions,
                allowCertificateReplacement: allowCertificateReplacement,
                progress: { stage in
                    try? await self.updateState(appID: appID, stage: stage)
                    await progress(stage)
                }
            )

            try await keychain.save(portalResult.updatedSecret, for: accountID)
            account.certificateSerialNumber = portalResult.certificateSerialNumber
            account.status = .verified
            account.lastVerifiedAt = Date()
            try await accountRepository.save(account)

            let signedPath = try await fileStore.storeSignedIPA(
                sourceURL: portalResult.signedIPAURL,
                appID: appID
            )
            try Task.checkCancellation()
            try await updateState(appID: appID, stage: .installing)
            await progress(.installing)
            let signedData = try await fileStore.read(relativePath: signedPath)
            if app.isSeal {
                SelfRenewalTracker.markPending(
                    bundleIdentifier: portalResult.mappedMainBundleID,
                    version: app.version
                )
            }
            try await installChannel.install(
                ipaData: signedData,
                bundleID: portalResult.mappedMainBundleID
            )

            try await updateState(appID: appID, stage: .verifying)
            await progress(.verifying)
            try await installChannel.verifyInstalled(
                bundleID: portalResult.mappedMainBundleID
            )

            app.mappedBundleIdentifier = portalResult.mappedMainBundleID
            app.preferredBundleIdentifier = targetBundleIdentifier
            app.accountID = accountID
            app.signedIPARelativePath = signedPath
            app.expiryDate = portalResult.expirationDate
            app.extensions.removeAll {
                portalResult.droppedExtensionBundleIdentifiers.contains(
                    $0.originalBundleIdentifier
                )
            }
            for index in app.extensions.indices {
                app.extensions[index].mappedBundleIdentifier =
                    portalResult.mappedBundleIdentifiers[
                        app.extensions[index].originalBundleIdentifier
                    ]
            }
            app.state = .installed
            try await appStore.save(app)
            return app
        } catch is CancellationError {
            app.state = originalState
            try? await appStore.save(app)
            throw CancellationError()
        } catch let failure as ImportFailure {
            if failure.code.hasPrefix("SEAL-AUTH-") {
                account.status = .needsVerification
                try? await accountRepository.save(account)
            }
            if failure.code.hasPrefix("SEAL-CERT-") {
                try? await keychain.clearSigningMaterial(accountID: accountID)
                account.certificateSerialNumber = nil
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
        if updated.certificateSerialNumber != secret.certificateSerialNumber {
            updated.certificateSerialNumber = secret.certificateSerialNumber
            try await accountRepository.save(updated)
        }
        if secret.certificateP12 == nil, secret.certificateSerialNumber != nil {
            try await keychain.clearSigningMaterial(accountID: account.id)
            updated.certificateSerialNumber = nil
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

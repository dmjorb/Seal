import Combine
import Foundation
@preconcurrency import AltSign

enum SettingsRoute: Hashable {
    case account
    case addAccount
    case certificates
    case accountDetail(UUID)
    case pairing
    case localDevVPN
    case storage
    case logs
}

@MainActor
final class SettingsViewModel: ObservableObject {
    struct PendingTeamSelection: Identifiable {
        let id = UUID()
        let authenticated: AuthenticatedAppleAccount

        var teams: [AppleTeamRecord] { authenticated.teams }
    }

    enum AccountPhase: Equatable {
        case idle
        case authenticating
    }

    enum DiagnosticState: Equatable {
        case idle
        case running
        case ready(deviceIdentifier: String)
        case failed(ImportFailure)
    }

    @Published private(set) var accounts: [AppleAccountRecord] = []
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var fullAccountEmails: [UUID: String] = [:]
    @Published private(set) var appIconData: [UUID: Data] = [:]
    @Published private(set) var pairingRecord: PairingRecord?
    @Published private(set) var accountPhase: AccountPhase = .idle
    @Published private(set) var diagnosticState: DiagnosticState = .idle
    @Published private(set) var installDiagnostics: InstallChannelDiagnostics = .empty
    @Published private(set) var logs: [SealLogEntry] = []
    @Published private(set) var signingHistory: [SigningHistoryRecord] = []
    @Published private(set) var signingHistoryIconData: [UUID: Data] = [:]
    @Published private(set) var certificateInventories: [UUID: ApplePortalInventory] = [:]
    @Published private(set) var certificateInventoryLoadingIDs: Set<UUID> = []
    @Published private(set) var certificateInventoryFailures: [UUID: ImportFailure] = [:]
    @Published private(set) var certificateHealthStatuses: [UUID: CertificateHealthStatus] = [:]
    @Published private(set) var isCertificateOperationRunning = false
    @Published private(set) var notificationsEnabled = false
    @Published private(set) var reminderHours = 24
    @Published private(set) var notificationStatus = NotificationScheduleStatus.disabled
    @Published private(set) var anisetteServers: [AnisetteServer] = []
    @Published private(set) var selectedAnisetteServerID: String?
    @Published private(set) var storageUsage: SettingsStorageUsage = .empty
    @Published private(set) var logExportText = ""
    @Published var isPairingImporterPresented = false
    @Published var alertFailure: ImportFailure?
    @Published var requestedRoute: SettingsRoute?
    @Published private(set) var pendingTeamSelection: PendingTeamSelection?

    let verificationBroker = VerificationCodeBroker()

    private let accountRepository: (any AccountRepository)?
    private let keychain: KeychainVault?
    private let accountClient: AppleAccountClient?
    private let pairingStore: PairingStore?
    private let installChannel: (any InstallChannel)?
    private let appStore: (any AppStore)?
    private let fileStore: AppFileStore?
    private let logStore: SealLogStore?
    private let signingHistoryStore: SigningHistoryStore?
    private let applePortalInventoryService: ApplePortalInventoryService?
    private let applePortalCertificateService: ApplePortalCertificateService?
    private let notificationScheduler: ExpiryNotificationScheduler?
    private let notificationPreferences: NotificationPreferences?
    private let anisetteEnvironment: (any AnisetteEnvironmentManaging)?
    private let signingPreferenceStore: SigningPreferenceStore?
    private let operationCoordinator: OperationCoordinator?
    private var hasLoaded = false
    private var loadGeneration = 0
    private static let pairingAssistantInboxFileName = "SealPairing.mobiledevicepairing"
    private static let pairingAssistantSource = "Seal 配对助手"

    init(
        accountRepository: any AccountRepository,
        keychain: KeychainVault,
        accountClient: AppleAccountClient,
        pairingStore: PairingStore,
        installChannel: any InstallChannel,
        appStore: any AppStore,
        fileStore: AppFileStore,
        logStore: SealLogStore,
        signingHistoryStore: SigningHistoryStore,
        notificationScheduler: ExpiryNotificationScheduler,
        notificationPreferences: NotificationPreferences,
        anisetteEnvironment: any AnisetteEnvironmentManaging,
        signingPreferenceStore: SigningPreferenceStore,
        operationCoordinator: OperationCoordinator? = nil
    ) {
        self.accountRepository = accountRepository
        self.keychain = keychain
        self.accountClient = accountClient
        self.pairingStore = pairingStore
        self.installChannel = installChannel
        self.appStore = appStore
        self.fileStore = fileStore
        self.logStore = logStore
        self.signingHistoryStore = signingHistoryStore
        self.applePortalInventoryService = ApplePortalInventoryService()
        self.applePortalCertificateService = ApplePortalCertificateService()
        self.notificationScheduler = notificationScheduler
        self.notificationPreferences = notificationPreferences
        self.anisetteEnvironment = anisetteEnvironment
        self.signingPreferenceStore = signingPreferenceStore
        self.operationCoordinator = operationCoordinator
        notificationsEnabled = notificationPreferences.isEnabled
        reminderHours = notificationPreferences.leadHours
    }

    init(startupFailure: ImportFailure) {
        accountRepository = nil
        keychain = nil
        accountClient = nil
        pairingStore = nil
        installChannel = nil
        appStore = nil
        fileStore = nil
        logStore = nil
        signingHistoryStore = nil
        applePortalInventoryService = nil
        applePortalCertificateService = nil
        notificationScheduler = nil
        notificationPreferences = nil
        anisetteEnvironment = nil
        signingPreferenceStore = nil
        operationCoordinator = nil
        alertFailure = startupFailure
    }

    private init() {
        accountRepository = nil
        keychain = nil
        accountClient = nil
        pairingStore = nil
        installChannel = nil
        appStore = nil
        fileStore = nil
        logStore = nil
        signingHistoryStore = nil
        applePortalInventoryService = nil
        applePortalCertificateService = nil
        notificationScheduler = nil
        notificationPreferences = nil
        anisetteEnvironment = nil
        signingPreferenceStore = nil
        operationCoordinator = nil
        hasLoaded = true
    }

    var environment: EnvironmentSnapshot {
        EnvironmentSnapshot(
            accountCount: accounts.count,
            verifiedAccountCount: accounts.filter { AccountAvailabilityPolicy.isSelectable($0) }.count,
            hasPairingFile: pairingRecord != nil,
            channelIsReady: {
                guard case .ready = diagnosticState else { return false }
                return true
            }()
        )
    }

    func load(force: Bool = false) async {
        guard force || hasLoaded == false else { return }
        guard let accountRepository, let pairingStore else { return }
        loadGeneration &+= 1
        let generation = loadGeneration

        do {
            let fetchedAccounts = try await accountRepository.fetchAll()
            guard generation == loadGeneration else { return }
            let repairedAccounts = try await repairLegacyAccountStatuses(fetchedAccounts)
            guard generation == loadGeneration else { return }
            let displayedAccounts = try await refreshedAccountDisplayNames(repairedAccounts)
            guard generation == loadGeneration else { return }

            _ = await importPairingAssistantInboxIfPresent()
            guard generation == loadGeneration else { return }

            let loadedPairing: PairingRecord?
            do {
                loadedPairing = try await pairingStore.current()
            } catch {
                loadedPairing = PairingRecord(
                    deviceIdentifier: nil,
                    isRemotePairing: false,
                    validationStatus: .fileUnreadable
                )
            }
            guard generation == loadGeneration else { return }

            let loadedEmails = await loadFullAccountEmails(for: displayedAccounts)
            guard generation == loadGeneration else { return }

            let storedApps = (try? await appStore?.fetchAll()) ?? []
            guard generation == loadGeneration else { return }
            let loadedAppIcons = await loadAppIcons(for: storedApps)
            guard generation == loadGeneration else { return }

            let preferredAccountID: UUID?
            if let signingPreferenceStore {
                preferredAccountID = await signingPreferenceStore.activeAccountID()
            } else {
                preferredAccountID = nil
            }
            guard generation == loadGeneration else { return }

            let selectableAccounts = displayedAccounts.filter { AccountAvailabilityPolicy.isSelectable($0) }
            let resolvedAccountID: UUID?
            if let preferredAccountID, displayedAccounts.contains(where: { $0.id == preferredAccountID }) {
                resolvedAccountID = preferredAccountID
            } else if let current = activeAccountID, displayedAccounts.contains(where: { $0.id == current }) {
                resolvedAccountID = current
            } else {
                resolvedAccountID = selectableAccounts.first?.id
                if preferredAccountID == nil {
                    await signingPreferenceStore?.setActiveAccountID(resolvedAccountID)
                    guard generation == loadGeneration else { return }
                }
            }

            let loadedLogs = (try? await logStore?.entries()) ?? []
            let loadedHistory = (try? await signingHistoryStore?.records()) ?? []
            guard generation == loadGeneration else { return }
            let loadedHistoryIcons = await loadSigningHistoryIcons(for: loadedHistory)
            guard generation == loadGeneration else { return }

            var loadedServers: [AnisetteServer] = anisetteServers
            var loadedSelectedServerID: String? = selectedAnisetteServerID
            if let anisetteEnvironment {
                async let availableServers = anisetteEnvironment.availableServers()
                async let selectedServerID = anisetteEnvironment.selectedServerID()
                loadedServers = await availableServers
                loadedSelectedServerID = (await selectedServerID) ?? loadedServers.first?.id
                guard generation == loadGeneration else { return }
            }

            var loadedNotificationsEnabled = notificationsEnabled
            var loadedReminderHours = reminderHours
            var loadedNotificationStatus = notificationStatus
            if let notificationPreferences {
                loadedNotificationsEnabled = notificationPreferences.isEnabled
                loadedReminderHours = notificationPreferences.leadHours
                if let notificationScheduler {
                    loadedNotificationStatus = await notificationScheduler.status(
                        sealEnabled: loadedNotificationsEnabled
                    )
                }
                guard generation == loadGeneration else { return }
            }

            let loadedStorageUsage: SettingsStorageUsage
            if let fileStore {
                loadedStorageUsage = (try? await fileStore.storageUsage()) ?? .empty
            } else {
                loadedStorageUsage = .empty
            }
            guard generation == loadGeneration else { return }

            accounts = displayedAccounts
            pairingRecord = loadedPairing
            fullAccountEmails = loadedEmails
            loadCertificateInventoryCache(for: displayedAccounts)
            appIconData = loadedAppIcons
            activeAccountID = resolvedAccountID
            logs = loadedLogs
            signingHistory = loadedHistory
            signingHistoryIconData = loadedHistoryIcons
            anisetteServers = loadedServers
            selectedAnisetteServerID = loadedSelectedServerID
            notificationsEnabled = loadedNotificationsEnabled
            reminderHours = loadedReminderHours
            notificationStatus = loadedNotificationStatus
            storageUsage = loadedStorageUsage
            refreshLogExportText()
            hasLoaded = true
        } catch {
            guard generation == loadGeneration else { return }
            alertFailure = Self.failure(
                title: "无法读取设置",
                reason: "本地配置不可用",
                recovery: "重试",
                code: "SEAL-SET-001"
            )
        }
    }

    func performLightweightLaunchCheck() async {
        await load(force: true)
        guard pairingRecord != nil, diagnosticState != .running else { return }
        await runInstallChannelCheck(successMessage: "安装通道可用")
    }

    var activeAccount: AppleAccountRecord? {
        guard let activeAccountID else { return nil }
        return accounts.first { $0.id == activeAccountID }
    }

    func fullEmail(for account: AppleAccountRecord) -> String {
        fullAccountEmails[account.id] ?? account.maskedEmail
    }

    func selectActiveAccount(_ account: AppleAccountRecord) async {
        guard AccountAvailabilityPolicy.isSelectable(account),
              accounts.contains(where: { $0.id == account.id }) else { return }
        activeAccountID = account.id
        await signingPreferenceStore?.setActiveAccountID(account.id)
    }

    func selectCertificate(
        serialNumber: String,
        for account: AppleAccountRecord
    ) async {
        guard let accountRepository, let keychain else { return }
        let secret: AccountSecret?
        do {
            secret = try await keychain.load(accountID: account.id)
        } catch {
            alertFailure = Self.failure(
                title: "证书不可用",
                reason: "Seal 无法读取本地证书私钥。",
                recovery: "重新验证 Apple ID",
                code: "SEAL-CERT-206"
            )
            return
        }
        guard let inventory = certificateInventories[account.id],
              inventory.certificates.contains(where: {
                  $0.serialNumber == serialNumber && $0.hasLocalPrivateKey
              }),
              let secret,
              secret.certificateSerialNumber == serialNumber,
              secret.certificateP12 != nil else {
            alertFailure = Self.failure(
                title: "证书不可用",
                reason: "Seal 本地没有此证书对应的私钥，未更改当前签名证书。",
                recovery: "知道了",
                code: "SEAL-CERT-206"
            )
            return
        }

        var updated = account
        updated.selectedCertificateSerialNumber = serialNumber
        do {
            try await accountRepository.save(updated)
            await load(force: true)
            try? await logStore?.append(
                category: .account,
                message: "已选择签名证书，完整 Serial：\(serialNumber)"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法选择证书",
                reason: "证书选择未能保存。",
                recovery: "重试",
                code: "SEAL-CERT-102"
            )
        }
    }

    func createLocalCertificate(for account: AppleAccountRecord) async {
        guard isCertificateOperationRunning == false,
              let keychain,
              let accountRepository,
              let applePortalCertificateService else { return }
        guard let operationLease = acquireOperation(.managingCertificate) else { return }
        defer { releaseOperation(operationLease) }

        isCertificateOperationRunning = true
        defer { isCertificateOperationRunning = false }

        do {
            guard let originalSecret = try await keychain.load(accountID: account.id) else {
                try await persistVerificationFailure(.localCredentialsMissing, for: account)
                throw Self.failure(
                    title: "无法创建证书",
                    reason: "本机没有当前 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-AUTH-105"
                )
            }

            let material = try await applePortalCertificateService.createLocalCertificate(
                account: account,
                secret: originalSecret
            )
            try await persistCreatedCertificate(
                material,
                originalSecret: originalSecret,
                originalAccount: account,
                keychain: keychain,
                accountRepository: accountRepository,
                certificateService: applePortalCertificateService
            )
            await load(force: true)
            await refreshCertificateInventory(for: account, force: true)
            try? await logStore?.append(
                category: .account,
                message: "已创建并保存本机签名证书。完整 Serial：\(material.serialNumber)"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch let failure as ImportFailure {
            alertFailure = failure
        } catch {
            alertFailure = Self.failure(
                title: "签名失败",
                reason: "Apple 返回：无法创建签名证书",
                recovery: "重试",
                code: "SEAL-CERT-211"
            )
        }
    }

    func revokeCertificate(
        serialNumber: String,
        for account: AppleAccountRecord
    ) async {
        guard isCertificateOperationRunning == false,
              let keychain,
              let accountRepository,
              let applePortalCertificateService else { return }
        guard let operationLease = acquireOperation(.managingCertificate) else { return }
        defer { releaseOperation(operationLease) }

        isCertificateOperationRunning = true
        defer { isCertificateOperationRunning = false }

        do {
            guard let originalSecret = try await keychain.load(accountID: account.id) else {
                try await persistVerificationFailure(.localCredentialsMissing, for: account)
                throw Self.failure(
                    title: "无法撤销证书",
                    reason: "本机没有当前 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-AUTH-105"
                )
            }

            try await applePortalCertificateService.revokeCertificate(
                serialNumber: serialNumber,
                account: account,
                secret: originalSecret
            )

            if originalSecret.certificateSerialNumber?.caseInsensitiveCompare(serialNumber) == .orderedSame {
                var clearedSecret = originalSecret
                clearedSecret.certificateP12 = nil
                clearedSecret.certificateSerialNumber = nil
                clearedSecret.certificateMachineIdentifier = nil
                var clearedAccount = account
                clearedAccount.certificateSerialNumber = nil
                clearedAccount.selectedCertificateSerialNumber = nil
                try await keychain.save(clearedSecret, for: account.id)
                try await accountRepository.save(clearedAccount)
            }

            try? await logStore?.append(
                category: .account,
                message: "用户已明确撤销证书。完整 Serial：\(serialNumber)"
            )
            await load(force: true)
            if let refreshedAccount = accounts.first(where: { $0.id == account.id }) {
                await refreshCertificateInventory(for: refreshedAccount, force: true)
            }
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch let failure as ImportFailure {
            await load(force: true)
            await refreshCertificateInventory(for: account, force: true)
            alertFailure = failure
        } catch {
            await load(force: true)
            await refreshCertificateInventory(for: account, force: true)
            alertFailure = Self.failure(
                title: "签名失败",
                reason: "Apple 返回：证书撤销失败",
                recovery: "重试",
                code: "SEAL-CERT-216"
            )
        }
    }

    func revokeCertificateAndCreateLocal(
        serialNumber: String,
        for account: AppleAccountRecord
    ) async {
        guard isCertificateOperationRunning == false,
              let keychain,
              let accountRepository,
              let applePortalCertificateService else { return }
        guard let operationLease = acquireOperation(.managingCertificate) else { return }
        defer { releaseOperation(operationLease) }

        isCertificateOperationRunning = true
        defer { isCertificateOperationRunning = false }

        do {
            guard let originalSecret = try await keychain.load(accountID: account.id) else {
                try await persistVerificationFailure(.localCredentialsMissing, for: account)
                throw Self.failure(
                    title: "无法更换证书",
                    reason: "本机没有当前 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-AUTH-105"
                )
            }

            try await applePortalCertificateService.revokeCertificate(
                serialNumber: serialNumber,
                account: account,
                secret: originalSecret
            )

            var clearedSecret = originalSecret
            var clearedAccount = account
            if originalSecret.certificateSerialNumber?.caseInsensitiveCompare(serialNumber) == .orderedSame {
                clearedSecret.certificateP12 = nil
                clearedSecret.certificateSerialNumber = nil
                clearedSecret.certificateMachineIdentifier = nil
                clearedAccount.certificateSerialNumber = nil
                clearedAccount.selectedCertificateSerialNumber = nil
                try await keychain.save(clearedSecret, for: account.id)
                try await accountRepository.save(clearedAccount)
            }

            let material = try await applePortalCertificateService.createLocalCertificate(
                account: clearedAccount,
                secret: clearedSecret
            )
            try await persistCreatedCertificate(
                material,
                originalSecret: clearedSecret,
                originalAccount: clearedAccount,
                keychain: keychain,
                accountRepository: accountRepository,
                certificateService: applePortalCertificateService
            )
            await load(force: true)
            if let refreshedAccount = accounts.first(where: { $0.id == account.id }) {
                await refreshCertificateInventory(for: refreshedAccount, force: true)
            }
            try? await logStore?.append(
                category: .account,
                message: "用户已明确撤销证书 Serial：\(serialNumber)，并创建本机证书 Serial：\(material.serialNumber)"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch let failure as ImportFailure {
            await load(force: true)
            await refreshCertificateInventory(for: account, force: true)
            alertFailure = failure
        } catch {
            await load(force: true)
            await refreshCertificateInventory(for: account, force: true)
            alertFailure = Self.failure(
                title: "无法完成证书处理",
                reason: "已按用户选择处理证书，但 Apple 或本地保存阶段没有返回明确失败原因。",
                recovery: "重新同步证书后确认当前状态",
                code: "SEAL-CERT-212"
            )
        }
    }

    private func persistCreatedCertificate(
        _ material: CreatedCertificateMaterial,
        originalSecret: AccountSecret,
        originalAccount: AppleAccountRecord,
        keychain: KeychainVault,
        accountRepository: any AccountRepository,
        certificateService: ApplePortalCertificateService
    ) async throws {
        do {
            try await keychain.save(material.updatedSecret, for: originalAccount.id)
            guard let reloaded = try await keychain.load(accountID: originalAccount.id),
                  reloaded.certificateSerialNumber?.caseInsensitiveCompare(material.serialNumber) == .orderedSame,
                  let p12 = reloaded.certificateP12,
                  let parsed = try? ALTCertificate(p12Data: p12, password: nil),
                  parsed.serialNumber.caseInsensitiveCompare(material.serialNumber) == .orderedSame else {
                throw Self.failure(
                    title: "本机证书校验失败",
                    reason: "证书已由 Apple 创建，但从 Keychain 重新读取后，P12 或完整 Serial 校验不一致。",
                    recovery: "重新同步证书",
                    code: "SEAL-CERT-208"
                )
            }

            var updatedAccount = originalAccount
            updatedAccount.certificateSerialNumber = material.serialNumber
            updatedAccount.selectedCertificateSerialNumber = material.serialNumber
            updatedAccount.status = .verified
            updatedAccount.verificationFailureReason = nil
            updatedAccount.lastVerifiedAt = Date()
            try await accountRepository.save(updatedAccount)
        } catch {
            let originalError = error
            var rollbackFailures: [String] = []
            do {
                try await certificateService.revokeCertificate(
                    serialNumber: material.serialNumber,
                    account: originalAccount,
                    secret: material.updatedSecret
                )
            } catch {
                rollbackFailures.append("Apple 远程证书")
            }
            do {
                try await keychain.save(originalSecret, for: originalAccount.id)
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
                    title: "证书补偿未完成",
                    reason: "证书创建后的补偿未完整完成（\(rollbackFailures.joined(separator: "、"))）。",
                    recovery: "重新同步证书并检查 Apple ID 状态",
                    code: "SEAL-CERT-215"
                )
            }
            if let failure = originalError as? ImportFailure { throw failure }
            throw Self.failure(
                title: "签名失败",
                reason: "Apple 返回：无法创建签名证书",
                recovery: "重试",
                code: "SEAL-CERT-208"
            )
        }
    }

    private func refreshedAccountDisplayNames(
        _ storedAccounts: [AppleAccountRecord]
    ) async throws -> [AppleAccountRecord] {
        guard let keychain, let accountRepository else { return storedAccounts }
        var refreshedAccounts: [AppleAccountRecord] = []

        for var account in storedAccounts {
            var changed = false
            do {
                if let secret = try await keychain.load(accountID: account.id) {
                    let readableMaskedEmail = AppleAccountClient.mask(secret.email)
                    if account.maskedEmail != readableMaskedEmail {
                        account.maskedEmail = readableMaskedEmail
                        changed = true
                    }

                    if let serial = secret.certificateSerialNumber,
                       secret.certificateP12 != nil {
                        if account.certificateSerialNumber != serial {
                            account.certificateSerialNumber = serial
                            changed = true
                        }
                        // 当前账号架构只保存一份本地 P12，因此可选证书必须
                        // 与这份私钥严格一致，避免界面显示旧 Serial。
                        if account.selectedCertificateSerialNumber != serial {
                            account.selectedCertificateSerialNumber = serial
                            changed = true
                        }
                    } else {
                        if account.certificateSerialNumber != nil {
                            account.certificateSerialNumber = nil
                            changed = true
                        }
                        if account.selectedCertificateSerialNumber != nil {
                            account.selectedCertificateSerialNumber = nil
                            changed = true
                        }
                    }
                }
            } catch {
                changed = false
            }

            if changed {
                try await accountRepository.save(account)
            }
            refreshedAccounts.append(account)
        }

        return refreshedAccounts
    }

    private func loadFullAccountEmails(
        for accounts: [AppleAccountRecord]
    ) async -> [UUID: String] {
        guard let keychain else { return [:] }
        var values: [UUID: String] = [:]
        for account in accounts {
            do {
                if let secret = try await keychain.load(accountID: account.id) {
                    values[account.id] = secret.email
                }
            } catch {
                continue
            }
        }
        return values
    }

    private func loadAppIcons(for apps: [AppRecord]) async -> [UUID: Data] {
        guard let fileStore else { return [:] }
        var values: [UUID: Data] = [:]
        for app in apps {
            guard let path = app.displayIconRelativePath,
                  let data = try? await fileStore.read(relativePath: path) else {
                continue
            }
            values[app.id] = data
        }
        return values
    }

    func signingHistory(for accountID: UUID) -> [SigningHistoryRecord] {
        signingHistory.filter { $0.accountID == accountID }
    }

    func signingHistorySummary(for accountID: UUID) -> SigningHistorySummary {
        SigningHistorySummary(records: signingHistory(for: accountID))
    }

    func certificateInventory(for accountID: UUID) -> ApplePortalInventory? {
        certificateInventories[accountID]
    }

    func certificateInventoryFailure(for accountID: UUID) -> ImportFailure? {
        certificateInventoryFailures[accountID]
    }

    func certificateHealthStatus(for accountID: UUID) -> CertificateHealthStatus? {
        certificateHealthStatuses[accountID]
    }

    func isCertificateInventoryLoading(accountID: UUID) -> Bool {
        certificateInventoryLoadingIDs.contains(accountID)
    }

    func refreshAppIDInventories() async {
        for account in accounts where AccountAvailabilityPolicy.isSelectable(account) {
            await refreshAppIDInventory(for: account, force: true)
        }
    }

    func refreshAppIDInventory(
        for account: AppleAccountRecord,
        force: Bool = true
    ) async {
        guard let keychain, let applePortalInventoryService else { return }
        if force == false, certificateInventories[account.id]?.appIDs.isEmpty == false { return }
        if certificateInventoryLoadingIDs.contains(account.id) { return }

        certificateInventoryLoadingIDs.insert(account.id)
        defer { certificateInventoryLoadingIDs.remove(account.id) }

        do {
            guard let secret = try await keychain.load(accountID: account.id) else {
                try await persistVerificationFailure(.localCredentialsMissing, for: account)
                throw Self.failure(
                    title: "Apple ID 同步失败",
                    reason: "本机没有此 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-INVENTORY-100"
                )
            }
            let fetched = try await applePortalInventoryService.fetchInventory(
                account: account,
                secret: secret,
                scope: .appIDs
            )
            let merged = ApplePortalInventory(
                accountID: fetched.accountID,
                teamID: fetched.teamID,
                teamName: fetched.teamName,
                appIDs: fetched.appIDs,
                certificates: certificateInventories[account.id]?.certificates ?? [],
                fetchedAt: fetched.fetchedAt
            )
            certificateInventories[account.id] = merged
            certificateInventoryFailures[account.id] = nil
            saveCertificateInventoryCache(merged)
            try? await logStore?.append(
                category: .account,
                message: "Apple App ID 已同步：\(merged.usedBundleIDCount) 个可用 App ID"
            )
        } catch let failure as ImportFailure {
            certificateInventoryFailures[account.id] = failure
        } catch {
            certificateInventoryFailures[account.id] = Self.failure(
                title: "Apple ID 同步失败",
                reason: "Apple 返回：App ID 状态同步失败",
                recovery: "重新同步",
                code: "SEAL-INVENTORY-900"
            )
        }
        logs = (try? await logStore?.entries()) ?? logs
        refreshLogExportText()
    }

    func refreshCertificateInventories() async {
        for account in accounts where AccountAvailabilityPolicy.isSelectable(account) {
            await refreshCertificateInventory(for: account, force: true)
        }
    }

    func refreshCertificateInventory(
        for account: AppleAccountRecord,
        force: Bool = true
    ) async {
        guard let keychain, let applePortalInventoryService else { return }
        if force == false, certificateInventories[account.id] != nil { return }
        if certificateInventoryLoadingIDs.contains(account.id) { return }

        certificateInventoryLoadingIDs.insert(account.id)
        defer { certificateInventoryLoadingIDs.remove(account.id) }

        do {
            guard let secret = try await keychain.load(accountID: account.id) else {
                try await persistVerificationFailure(.localCredentialsMissing, for: account)
                throw Self.failure(
                    title: "Apple 侧同步失败",
                    reason: "本机没有此 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-INVENTORY-100"
                )
            }
            let fetched = try await applePortalInventoryService.fetchInventory(
                account: account,
                secret: secret,
                scope: .certificates
            )
            let inventory = ApplePortalInventory(
                accountID: fetched.accountID,
                teamID: fetched.teamID,
                teamName: fetched.teamName,
                appIDs: certificateInventories[account.id]?.appIDs ?? [],
                certificates: fetched.certificates,
                fetchedAt: fetched.fetchedAt
            )
            certificateInventories[account.id] = inventory
            certificateInventoryFailures[account.id] = nil
            certificateHealthStatuses[account.id] = await makeCertificateHealthStatus(
                account: account,
                secret: secret,
                inventory: inventory
            )
            saveCertificateInventoryCache(inventory)
            try? await logStore?.append(
                category: .account,
                message: "Apple 侧证书状态已同步"
            )
        } catch let failure as ImportFailure {
            certificateInventoryFailures[account.id] = failure
            certificateHealthStatuses[account.id] = await localCertificateHealthStatus(
                account: account,
                portalState: .unknown
            )
            try? await logStore?.append(
                category: .account,
                level: .error,
                message: failure.reason,
                code: failure.code
            )
        } catch {
            let failure = Self.failure(
                title: "Apple 侧同步失败",
                reason: "Apple 返回：证书状态同步失败",
                recovery: "重新同步",
                code: "SEAL-INVENTORY-900"
            )
            certificateInventoryFailures[account.id] = failure
            certificateHealthStatuses[account.id] = await localCertificateHealthStatus(
                account: account,
                portalState: .unknown
            )
            try? await logStore?.append(
                category: .account,
                level: .error,
                message: failure.reason,
                code: failure.code
            )
        }
        logs = (try? await logStore?.entries()) ?? logs
        refreshLogExportText()
    }

    private func localCertificateHealthStatus(
        account: AppleAccountRecord,
        portalState: CertificateHealthStatus.CheckState
    ) async -> CertificateHealthStatus? {
        guard let keychain else { return nil }
        do {
            guard let secret = try await keychain.load(accountID: account.id) else {
                return nil
            }
            return await makeCertificateHealthStatus(
                account: account,
                secret: secret,
                inventory: nil,
                portalStateOverride: portalState
            )
        } catch {
            guard let serial = account.selectedCertificateSerialNumber
                    ?? account.certificateSerialNumber else {
                return nil
            }
            return CertificateHealthStatus(
                serialNumber: serial,
                portalPresence: portalState,
                p12Readable: .unknown,
                localPrivateKey: .unknown,
                keychainReadable: .invalid,
                appleIDMatch: .unknown,
                teamMatch: .unknown,
                expirationDate: nil,
                lastSignedAt: nil,
                relatedAppCount: 0
            )
        }
    }

    private func makeCertificateHealthStatus(
        account: AppleAccountRecord,
        secret: AccountSecret,
        inventory: ApplePortalInventory?,
        portalStateOverride: CertificateHealthStatus.CheckState? = nil
    ) async -> CertificateHealthStatus? {
        guard let serial = account.selectedCertificateSerialNumber
                ?? account.certificateSerialNumber
                ?? secret.certificateSerialNumber,
              serial.isEmpty == false else {
            return nil
        }

        let localCertificate: ALTCertificate? = {
            guard let p12 = secret.certificateP12 else { return nil }
            return try? ALTCertificate(p12Data: p12, password: nil)
        }()
        let localSerialMatches = localCertificate?.serialNumber.caseInsensitiveCompare(serial) == .orderedSame
        let storedSerialMatches = secret.certificateSerialNumber?.caseInsensitiveCompare(serial) == .orderedSame
        let portalCertificate = inventory?.certificates.first {
            $0.serialNumber.caseInsensitiveCompare(serial) == .orderedSame
        }

        let portalPresence = portalStateOverride
            ?? (portalCertificate == nil ? .invalid : .valid)
        let localValidity = localCertificate?.data
            .flatMap(X509CertificateValidityReader.validity(from:))
        let expirationDate = portalCertificate?.expirationDate ?? localValidity?.notAfter

        var relatedApps: [AppRecord] = []
        if let appStore {
            do {
                relatedApps = try await appStore.fetchAll().filter { app in
                    app.accountID == account.id
                        && app.signingTeamID == account.teamID
                        && app.certificateSerialNumber?.caseInsensitiveCompare(serial) == .orderedSame
                }
            } catch {
                try? await logStore?.append(
                    category: .account,
                    level: .error,
                    message: "无法读取使用当前 Serial 的应用记录",
                    code: "SEAL-CERT-HEALTH-001"
                )
            }
        }

        return CertificateHealthStatus(
            serialNumber: serial,
            portalPresence: portalPresence,
            p12Readable: localCertificate == nil ? .invalid : .valid,
            localPrivateKey: localCertificate?.privateKey != nil
                && localSerialMatches
                && storedSerialMatches ? .valid : .invalid,
            keychainReadable: .valid,
            appleIDMatch: secret.accountIdentifier == account.accountIdentifier ? .valid : .invalid,
            teamMatch: inventory.map { $0.teamID == account.teamID ? .valid : .invalid } ?? .unknown,
            expirationDate: expirationDate,
            lastSignedAt: relatedApps.compactMap(\AppRecord.lastSignedAt).max(),
            relatedAppCount: relatedApps.count
        )
    }

    private func loadCertificateInventoryCache(for accounts: [AppleAccountRecord]) {
        let validIDs = Set(accounts.map(\.id))
        var cached: [UUID: ApplePortalInventory] = [:]
        for account in accounts {
            guard let data = UserDefaults.standard.data(forKey: certificateInventoryCacheKey(account.id)),
                  let inventory = try? JSONDecoder().decode(ApplePortalInventory.self, from: data) else {
                continue
            }
            cached[account.id] = inventory
        }
        certificateInventories = certificateInventories.filter { validIDs.contains($0.key) }
        for (id, inventory) in cached where certificateInventories[id] == nil {
            certificateInventories[id] = inventory
        }
    }

    private func saveCertificateInventoryCache(_ inventory: ApplePortalInventory) {
        guard let data = try? JSONEncoder().encode(inventory) else { return }
        UserDefaults.standard.set(data, forKey: certificateInventoryCacheKey(inventory.accountID))
    }

    private func certificateInventoryCacheKey(_ accountID: UUID) -> String {
        "settings.applePortalInventory.\(accountID.uuidString)"
    }

    func clearSigningHistory(for accountID: UUID) async {
        guard let signingHistoryStore else { return }
        do {
            try await signingHistoryStore.clear(accountID: accountID)
            signingHistory = (try? await signingHistoryStore.records()) ?? []
            signingHistoryIconData = await loadSigningHistoryIcons(for: signingHistory)
            try? await logStore?.append(
                category: .system,
                message: "已清除 Apple ID 的签名历史"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法清除签名历史",
                reason: "本地历史记录不可写入",
                recovery: "重试",
                code: "SEAL-HISTORY-001"
            )
        }
    }

    private func loadSigningHistoryIcons(
        for records: [SigningHistoryRecord]
    ) async -> [UUID: Data] {
        guard let fileStore else { return [:] }
        var values: [UUID: Data] = [:]
        for record in records {
            guard let path = record.iconRelativePath,
                  let data = try? await fileStore.read(relativePath: path) else {
                continue
            }
            values[record.id] = data
        }
        return values
    }

    func requestInitialPermissionsIfNeeded() async {
        // 通知权限只在用户主动开启“到期前 24 小时提醒”时请求。
    }

    func selectAnisetteServer(id: String) async {
        guard let anisetteEnvironment,
              anisetteServers.contains(where: { $0.id == id }) else { return }
        await anisetteEnvironment.selectServer(id: id)
        selectedAnisetteServerID = id
    }

    func resetSigningEnvironment() async {
        guard let anisetteEnvironment else { return }
        guard let operationLease = acquireOperation(.managingAccount) else { return }
        defer { releaseOperation(operationLease) }
        await anisetteEnvironment.resetProvisioning()
        try? await logStore?.append(
            category: .system,
            message: "Signing environment reset"
        )
        logs = (try? await logStore?.entries()) ?? logs
    }

    func addAccount(
        email: String,
        password: String,
        replacing existingAccount: AppleAccountRecord? = nil
    ) async -> Bool {
        guard accountPhase == .idle,
              let accountClient else { return false }
        guard let operationLease = acquireOperation(.managingAccount) else { return false }
        defer { releaseOperation(operationLease) }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.isEmpty == false, password.isEmpty == false else {
            alertFailure = Self.failure(
                title: "信息不完整",
                reason: "请输入 Apple ID 和密码",
                recovery: "知道了",
                code: "SEAL-AUTH-100"
            )
            return false
        }

        pendingTeamSelection = nil
        accountPhase = .authenticating
        defer { accountPhase = .idle }
        do {
            let authenticated = try await accountClient.authenticate(
                email: normalizedEmail,
                password: password,
                verificationCode: { [weak self] in
                    await self?.verificationBroker.request()
                }
            )
            try Task.checkCancellation()

            guard authenticated.teams.isEmpty == false else {
                throw Self.failure(
                    title: "没有可用 Team",
                    reason: "Apple 返回的账号信息中没有可用于签名的 Team。",
                    recovery: "重新验证",
                    code: "SEAL-AUTH-107"
                )
            }

            if let existingAccount {
                guard existingAccount.accountIdentifier == authenticated.accountIdentifier else {
                    throw Self.failure(
                        title: "Apple ID 不匹配",
                        reason: "重新验证返回的账号与原账号记录不一致。",
                        recovery: "重新验证 Apple ID",
                        code: "SEAL-AUTH-108"
                    )
                }
                guard let existingTeam = authenticated.teams.first(where: { $0.id == existingAccount.teamID }) else {
                    throw Self.failure(
                        title: "原 Team 不可用",
                        reason: "重新验证后没有找到原 Team（\(existingAccount.teamName) / \(existingAccount.teamID)）。Seal 不会静默切换到其他 Team。",
                        recovery: "重新验证 Apple ID",
                        code: "SEAL-AUTH-109"
                    )
                }
                return try await persistAuthenticatedAccount(
                    authenticated,
                    team: existingTeam,
                    replacing: existingAccount
                )
            }

            if authenticated.teams.count == 1, let team = authenticated.teams.first {
                return try await persistAuthenticatedAccount(authenticated, team: team, replacing: nil)
            }

            pendingTeamSelection = PendingTeamSelection(authenticated: authenticated)
            return false
        } catch is CancellationError {
            pendingTeamSelection = nil
            return false
        } catch let failure as ImportFailure {
            pendingTeamSelection = nil
            alertFailure = failure
            try? await logStore?.append(
                category: .account,
                level: .error,
                message: failure.reason,
                code: failure.code
            )
            logs = (try? await logStore?.entries()) ?? logs
            return false
        } catch {
            pendingTeamSelection = nil
            let failure = AppleServiceFailurePolicy.isNetworkError(error)
                ? AppleServiceFailurePolicy.networkFailure(underlying: error)
                : Self.failure(
                    title: "无法添加账号",
                    reason: "Apple ID 验证失败",
                    recovery: "重试",
                    code: "SEAL-AUTH-102"
                )
            alertFailure = failure
            try? await logStore?.append(
                category: .account,
                level: .error,
                message: failure.reason,
                code: failure.code
            )
            logs = (try? await logStore?.entries()) ?? logs
            return false
        }
    }

    func completeTeamSelection(_ team: AppleTeamRecord) async -> Bool {
        guard accountPhase == .idle,
              let pending = pendingTeamSelection,
              pending.teams.contains(team) else { return false }
        guard let operationLease = acquireOperation(.managingAccount) else { return false }
        defer { releaseOperation(operationLease) }
        accountPhase = .authenticating
        defer { accountPhase = .idle }
        do {
            let result = try await persistAuthenticatedAccount(
                pending.authenticated,
                team: team,
                replacing: nil
            )
            if result { pendingTeamSelection = nil }
            return result
        } catch let failure as ImportFailure {
            alertFailure = failure
            return false
        } catch {
            alertFailure = Self.failure(
                title: "无法保存 Team",
                reason: "账号信息保存失败，请重试。",
                recovery: "重试",
                code: "SEAL-AUTH-110"
            )
            return false
        }
    }

    func cancelTeamSelection() {
        pendingTeamSelection = nil
    }

    private func persistAuthenticatedAccount(
        _ authenticated: AuthenticatedAppleAccount,
        team: AppleTeamRecord,
        replacing existingAccount: AppleAccountRecord?
    ) async throws -> Bool {
        guard let accountRepository, let keychain else { return false }
        let storedAccounts = try await accountRepository.fetchAll()
        let canReplaceExisting = existingAccount.map { account in
            account.accountIdentifier == authenticated.accountIdentifier && account.teamID == team.id
        } ?? false
        let replacingAccountID = canReplaceExisting ? existingAccount?.id : nil
        let duplicateAccount = storedAccounts.first { candidate in
            if let replacingAccountID, candidate.id == replacingAccountID { return false }
            return candidate.accountIdentifier == authenticated.accountIdentifier && candidate.teamID == team.id
        }
        let baseAccount = canReplaceExisting ? existingAccount : duplicateAccount
        let baseRecord = authenticated.record(team: team, id: baseAccount?.id ?? UUID())
        let record = baseAccount.map { old in
            AppleAccountRecord(
                id: old.id,
                maskedEmail: baseRecord.maskedEmail,
                accountIdentifier: baseRecord.accountIdentifier,
                teamID: baseRecord.teamID,
                teamName: baseRecord.teamName,
                isFreeTeam: baseRecord.isFreeTeam,
                status: .verified,
                certificateSerialNumber: old.certificateSerialNumber,
                selectedCertificateSerialNumber: old.selectedCertificateSerialNumber,
                lastVerifiedAt: baseRecord.lastVerifiedAt
            )
        } ?? baseRecord

        let previousSecret = try await keychain.load(accountID: record.id)
        var mergedSecret = authenticated.secret
        if let previousSecret,
           previousSecret.accountIdentifier == authenticated.secret.accountIdentifier {
            mergedSecret.certificateP12 = previousSecret.certificateP12
            mergedSecret.certificateSerialNumber = previousSecret.certificateSerialNumber
            mergedSecret.certificateMachineIdentifier = previousSecret.certificateMachineIdentifier
        }
        try await keychain.save(mergedSecret, for: record.id)
        do {
            try await accountRepository.save(record)
        } catch {
            let originalError = error
            do {
                if let previousSecret {
                    try await keychain.save(previousSecret, for: record.id)
                } else {
                    try await keychain.delete(accountID: record.id)
                }
            } catch {
                throw Self.failure(
                    title: "账号保存补偿未完成",
                    reason: "账号记录保存失败，且 Keychain 无法恢复到修改前状态。",
                    recovery: "重新验证 Apple ID 后检查账号状态",
                    code: "SEAL-AUTH-DB-002"
                )
            }
            throw originalError
        }

        await load(force: true)
        if let saved = accounts.first(where: { $0.id == record.id }) {
            await refreshCertificateInventory(for: saved, force: true)
            if activeAccountID == nil || existingAccount == nil && duplicateAccount == nil {
                await selectActiveAccount(saved)
            }
        }
        try? await logStore?.append(
            category: .account,
            message: duplicateAccount == nil ? "Apple ID 已添加（Team: \(team.name)）" : "Apple ID 已重新绑定到现有账号记录（Team: \(team.name)）"
        )
        return true
    }

    func deleteAccount(_ account: AppleAccountRecord) async {
        guard let accountRepository, let keychain else { return }
        guard let operationLease = acquireOperation(.managingAccount) else { return }
        defer { releaseOperation(operationLease) }
        let relatedApps = (try? await appStore?.fetchAll())?
            .filter { $0.accountID == account.id } ?? []
        let storedSecret: AccountSecret?
        do {
            storedSecret = try await keychain.load(accountID: account.id)
        } catch {
            alertFailure = Self.failure(
                title: "无法删除 Apple ID",
                reason: "删除前无法读取本机 Keychain 凭据，因此未修改账号记录。",
                recovery: "稍后重试",
                code: "SEAL-AUTH-DB-003"
            )
            return
        }
        do {
            try await accountRepository.delete(id: account.id)
            try await keychain.delete(accountID: account.id)
            if activeAccountID == account.id {
                activeAccountID = nil
                await signingPreferenceStore?.setActiveAccountID(nil)
            }
            await load(force: true)
            try? await logStore?.append(
                category: .account,
                message: "Apple ID 已移除；关联应用保留原账号绑定，用于防止误用其他账号续签。关联应用数：\(relatedApps.count)"
            )
        } catch {
            var rollbackFailures: [String] = []
            do {
                try await accountRepository.save(account)
            } catch {
                rollbackFailures.append("账号记录")
            }
            if let storedSecret {
                do {
                    try await keychain.save(storedSecret, for: account.id)
                } catch {
                    rollbackFailures.append("Keychain")
                }
            }
            await load(force: true)
            alertFailure = Self.failure(
                title: "无法移除账号",
                reason: rollbackFailures.isEmpty
                    ? "本地数据未能更新，原账号已恢复。"
                    : "删除失败，且本地补偿未完整完成（\(rollbackFailures.joined(separator: "、"))）。",
                recovery: rollbackFailures.isEmpty ? "重试" : "重新验证 Apple ID 后检查账号状态",
                code: rollbackFailures.isEmpty ? "SEAL-AUTH-106" : "SEAL-AUTH-DB-002"
            )
        }
    }

    func email(for account: AppleAccountRecord) async -> String {
        guard let keychain else { return "" }
        return (try? await keychain.load(accountID: account.id))?.email ?? ""
    }

    @discardableResult
    func importPairingAssistantInboxIfPresent() async -> Bool {
        guard let pairingStore else { return false }
        guard let operationLease = acquireOperation(.resettingPairing) else { return false }
        defer { releaseOperation(operationLease) }
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }

        let inboxURL = documentsURL.appendingPathComponent(
            Self.pairingAssistantInboxFileName,
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: inboxURL.path) else {
            return false
        }

        do {
            pairingRecord = try await pairingStore.importFile(at: inboxURL)
            await installChannel?.reset()
            diagnosticState = .idle
            installDiagnostics = .empty
            try? FileManager.default.removeItem(at: inboxURL)
            try? await logStore?.append(
                category: .pairing,
                message: "\(Self.pairingAssistantSource)已自动写入配对信息，等待真实设备连接验证"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
            await runInstallChannelCheck(successMessage: "配对助手和安装通道正常")
            return true
        } catch let failure as ImportFailure {
            try? FileManager.default.removeItem(at: inboxURL)
            alertFailure = failure
            try? await logStore?.append(
                category: .pairing,
                level: .error,
                message: "\(Self.pairingAssistantSource)写入的配对信息无法导入",
                code: failure.code
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
            return false
        } catch {
            try? FileManager.default.removeItem(at: inboxURL)
            alertFailure = Self.failure(
                title: "无法接收配对信息",
                reason: "Seal 配对助手已发送数据，但本机无法读取。",
                recovery: "重新配对",
                code: "SEAL-PAIR-207"
            )
            try? await logStore?.append(
                category: .pairing,
                level: .error,
                message: "\(Self.pairingAssistantSource)写入的配对信息读取失败",
                code: "SEAL-PAIR-207"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
            return false
        }
    }

    func importPairingFile(_ url: URL) async {
        guard let pairingStore else { return }
        guard let operationLease = acquireOperation(.resettingPairing) else { return }
        defer { releaseOperation(operationLease) }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            pairingRecord = try await pairingStore.importFile(at: url)
            await installChannel?.reset()
            diagnosticState = .idle
            installDiagnostics = .empty
            try? await logStore?.append(
                category: .pairing,
                message: "配对文件已导入，等待真实设备连接验证"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch let failure as ImportFailure {
            pairingRecord = PairingRecord(
                deviceIdentifier: nil,
                isRemotePairing: false,
                validationStatus: .fileUnreadable
            )
            alertFailure = failure
        } catch {
            pairingRecord = PairingRecord(
                deviceIdentifier: nil,
                isRemotePairing: false,
                validationStatus: .fileUnreadable
            )
            alertFailure = Self.failure(
                title: "配对文件无效",
                reason: "无法读取设备配对信息",
                recovery: "重新导入",
                code: "SEAL-PAIR-201"
            )
        }
    }

    func removePairingFile() async {
        guard let pairingStore else { return }
        guard let operationLease = acquireOperation(.resettingPairing) else { return }
        defer { releaseOperation(operationLease) }
        do {
            try await pairingStore.remove()
            await installChannel?.reset()
            pairingRecord = nil
            diagnosticState = .idle
            installDiagnostics = .empty
            try? await logStore?.append(
                category: .pairing,
                message: "配对文件已移除"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法移除配对",
                reason: "配对文件仍在使用",
                recovery: "重试",
                code: "SEAL-PAIR-202"
            )
        }
    }

    func testConnection() async {
        await load(force: true)
        guard diagnosticState != .running, installChannel != nil else { return }
        guard accounts.isEmpty == false,
              let accountClient,
              let keychain,
              let accountRepository else {
            diagnosticState = .failed(
                Self.failure(
                    title: "缺少签名账号",
                    reason: "尚未添加 Apple ID",
                    recovery: "添加账号",
                    code: "SEAL-AUTH-104"
                )
            )
            return
        }
        guard pairingRecord != nil else {
            diagnosticState = .failed(
                Self.failure(
                    title: "缺少配对文件",
                    reason: "尚未导入本机配对文件",
                    recovery: "导入配对文件",
                    code: "SEAL-PAIR-203"
                )
            )
            return
        }

        let selected = activeAccount
            ?? accounts.first(where: { AccountAvailabilityPolicy.isSelectable($0) })
            ?? accounts.first
        guard var account = selected else { return }
        if activeAccountID != account.id {
            activeAccountID = account.id
            await signingPreferenceStore?.setActiveAccountID(account.id)
        }

        diagnosticState = .running
        do {
            guard let secret = try await keychain.load(accountID: account.id) else {
                try await persistVerificationFailure(.localCredentialsMissing, for: account)
                throw Self.failure(
                    title: "账号需要验证",
                    reason: "本机没有当前 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-AUTH-105"
                )
            }

            do {
                try await accountClient.validate(account: account, secret: secret)
                account.status = .verified
                account.verificationFailureReason = nil
                account.maskedEmail = AppleAccountClient.mask(secret.email)
                account.lastVerifiedAt = Date()
                try await accountRepository.save(account)
            } catch let failure as ImportFailure {
                if let reason = AppleServiceFailurePolicy.verificationFailureReason(for: failure) {
                    account.status = .needsVerification
                    account.verificationFailureReason = reason
                    try await accountRepository.save(account)
                }
                throw failure
            } catch {
                if AppleServiceFailurePolicy.isNetworkError(error) {
                    throw AppleServiceFailurePolicy.networkFailure(
                        title: "无法连接 Apple",
                        reason: "当前网络或 Apple 服务不可用。Apple ID 状态未改变。"
                    )
                }
                throw Self.failure(
                    title: "无法验证 Apple ID",
                    reason: "Apple 验证返回了无法分类的错误。账号状态未改变。",
                    recovery: "稍后重试；如持续失败再重新验证 Apple ID",
                    code: "SEAL-VERIFY-500"
                )
            }

            await refreshCertificateInventory(for: account, force: true)
            if let failure = certificateInventoryFailures[account.id] {
                throw failure
            }
            await runInstallChannelCheck(successMessage: "签名环境检测正常")
        } catch let failure as ImportFailure {
            await finishInstallChannelCheckWithFailure(
                failure,
                logMessage: "签名环境检测失败"
            )
        } catch {
            await finishInstallChannelCheckWithFailure(
                Self.localDevVPNUnavailableFailure,
                logMessage: "签名环境检测失败"
            )
        }
    }

    private func persistVerificationFailure(
        _ reason: AccountVerificationFailureReason,
        for account: AppleAccountRecord
    ) async throws {
        guard let accountRepository else { return }
        var updated = account
        updated.status = .needsVerification
        updated.verificationFailureReason = reason
        try await accountRepository.save(updated)
    }

    private func repairLegacyAccountStatuses(
        _ records: [AppleAccountRecord]
    ) async throws -> [AppleAccountRecord] {
        guard let accountRepository, let keychain else { return records }
        var repaired = records
        for index in repaired.indices where repaired[index].status == .needsVerification {
            let hasLocalSecret = try await keychain.load(accountID: repaired[index].id) != nil
            let status = AccountAvailabilityPolicy.repairedStatus(
                for: repaired[index],
                hasLocalSecret: hasLocalSecret
            )
            guard status != repaired[index].status else { continue }
            repaired[index].status = status
            try await accountRepository.save(repaired[index])
        }
        return repaired
    }

    func testLocalDevVPN() async {
        await load(force: true)
        guard diagnosticState != .running, installChannel != nil else { return }
        guard pairingRecord != nil else {
            diagnosticState = .failed(
                Self.failure(
                    title: "缺少配对文件",
                    reason: "检测 LocalDevVPN 前需要先导入当前设备的配对文件",
                    recovery: "导入配对文件",
                    code: "SEAL-PAIR-203"
                )
            )
            return
        }
        await runInstallChannelCheck(successMessage: "LocalDevVPN 和安装通道正常")
    }

    private func runInstallChannelCheck(successMessage: String) async {
        guard let installChannel else { return }
        diagnosticState = .running
        if let pairingStore, pairingRecord != nil {
            do {
                pairingRecord = try await pairingStore.markValidating()
            } catch {
                let failure = Self.failure(
                    title: "配对验证失败",
                    reason: "无法保存配对文件的验证中状态。",
                    recovery: "重新导入配对文件",
                    code: "SEAL-PAIR-206"
                )
                diagnosticState = .failed(failure)
                alertFailure = failure
                return
            }
        }
        let diagnostics = await installChannel.diagnose()
        installDiagnostics = diagnostics
        if diagnostics.isReady, let deviceIdentifier = diagnostics.deviceIdentifier {
            if let pairingStore {
                do {
                    pairingRecord = try await pairingStore.markValidated(
                        deviceIdentifier: deviceIdentifier
                    )
                } catch let failure as ImportFailure {
                    await finishInstallChannelCheckWithFailure(
                        failure,
                        diagnostics: diagnostics,
                        logMessage: "配对文件设备校验失败"
                    )
                    return
                } catch {
                    await finishInstallChannelCheckWithFailure(
                        Self.failure(
                            title: "配对验证失败",
                            reason: "无法保存当前设备的配对验证结果。",
                            recovery: "重新导入配对文件",
                            code: "SEAL-PAIR-207"
                        ),
                        diagnostics: diagnostics,
                        logMessage: "配对文件设备校验失败"
                    )
                    return
                }
            }
            diagnosticState = .ready(deviceIdentifier: deviceIdentifier)
            await load(force: true)
            installDiagnostics = diagnostics
            try? await logStore?.append(
                category: .installation,
                message: successMessage
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
            return
        }
        await finishInstallChannelCheckWithFailure(
            diagnostics.failure ?? Self.localDevVPNUnavailableFailure,
            diagnostics: diagnostics,
            logMessage: "LocalDevVPN 或安装通道检测失败"
        )
    }

    private static func shouldRollbackPairing(after failure: ImportFailure) -> Bool {
        ["SEAL-PAIR-205", "SEAL-PAIR-206", "SEAL-INSTALL-703"].contains(failure.code)
    }

    private func finishInstallChannelCheckWithFailure(
        _ failure: ImportFailure,
        diagnostics: InstallChannelDiagnostics? = nil,
        logMessage: String
    ) async {
        var effectiveFailure = failure
        var effectiveDiagnostics = diagnostics
        if Self.shouldRollbackPairing(after: failure), let pairingStore {
            do {
                if let restored = try await pairingStore.restoreBackupIfPresent() {
                    pairingRecord = restored
                    await installChannel?.reset()
                    try? await logStore?.append(
                        category: .pairing,
                        message: "新配对信息验证失败，已自动恢复上一份可用配对信息"
                    )
                    if let installChannel {
                        let recoveryDiagnostics = await installChannel.diagnose()
                        effectiveDiagnostics = recoveryDiagnostics
                        if recoveryDiagnostics.isReady,
                           let deviceIdentifier = recoveryDiagnostics.deviceIdentifier {
                            do {
                                pairingRecord = try await pairingStore.markValidated(
                                    deviceIdentifier: deviceIdentifier
                                )
                                diagnosticState = .ready(deviceIdentifier: deviceIdentifier)
                                installDiagnostics = recoveryDiagnostics
                                try? await logStore?.append(
                                    category: .pairing,
                                    message: "上一份配对信息已恢复并重新验证成功"
                                )
                                logs = (try? await logStore?.entries()) ?? logs
                                refreshLogExportText()
                                return
                            } catch let restoreFailure as ImportFailure {
                                effectiveFailure = restoreFailure
                            } catch {
                                effectiveFailure = Self.failure(
                                    title: "配对恢复验证失败",
                                    reason: "上一份配对信息已恢复，但验证结果无法保存。",
                                    recovery: "重新检测",
                                    code: "SEAL-PAIR-210"
                                )
                            }
                        } else if let recoveryFailure = recoveryDiagnostics.failure {
                            effectiveFailure = recoveryFailure
                        }
                    }
                }
            } catch {
                effectiveFailure = Self.failure(
                    title: "配对恢复失败",
                    reason: "新配对信息不可用，且上一份配对信息未能自动恢复。",
                    recovery: "重新配对",
                    code: "SEAL-PAIR-209"
                )
                alertFailure = effectiveFailure
            }
        }
        if let pairingStore {
            do {
                if let deviceIdentifier = effectiveDiagnostics?.deviceIdentifier {
                    pairingRecord = try await pairingStore.markValidated(
                        deviceIdentifier: deviceIdentifier
                    )
                } else {
                    pairingRecord = try await pairingStore.markPendingValidation()
                }
            } catch {
                alertFailure = Self.failure(
                    title: "配对状态保存失败",
                    reason: "LocalDevVPN 检测失败后，配对状态未能写入本机存储。",
                    recovery: "重新导入配对文件后再检测",
                    code: "SEAL-PAIR-208"
                )
            }
        }
        await load(force: true)
        if let effectiveDiagnostics { installDiagnostics = effectiveDiagnostics }
        diagnosticState = .failed(effectiveFailure)
        try? await logStore?.append(
            category: .installation,
            level: .error,
            message: logMessage,
            code: effectiveFailure.code
        )
        logs = (try? await logStore?.entries()) ?? logs
        refreshLogExportText()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard let notificationScheduler,
              let notificationPreferences,
              let appStore else { return }
        do {
            if enabled {
                let granted = try await notificationScheduler.requestAuthorization()
                guard granted else {
                    notificationPreferences.isEnabled = true
                    notificationsEnabled = true
                    notificationStatus = await notificationScheduler.status(sealEnabled: true)
                    throw Self.failure(
                        title: "通知未开启",
                        reason: "Seal 内提醒已开启，但系统没有授予通知权限。",
                        recovery: "检查系统通知权限",
                        code: "SEAL-NOTIFY-001"
                    )
                }
            }
            notificationPreferences.isEnabled = enabled
            notificationsEnabled = enabled
            try await notificationScheduler.reschedule(
                apps: try await appStore.fetchAll(),
                enabled: enabled,
                leadHours: reminderHours
            )
            notificationStatus = await notificationScheduler.status(sealEnabled: enabled)
        } catch let failure as ImportFailure {
            notificationStatus = await notificationScheduler.status(
                sealEnabled: notificationPreferences.isEnabled,
                schedulingFailure: failure.reason
            )
            alertFailure = failure
            try? await logStore?.append(category: .system, level: .error, message: failure.reason, code: failure.code)
        } catch {
            let failure = Self.failure(
                title: "无法设置提醒",
                reason: "通知调度失败",
                recovery: "重试",
                code: "SEAL-NOTIFY-002"
            )
            notificationStatus = await notificationScheduler.status(
                sealEnabled: notificationPreferences.isEnabled,
                schedulingFailure: failure.reason
            )
            alertFailure = failure
            try? await logStore?.append(category: .system, level: .error, message: failure.reason, code: failure.code)
        }
    }

    func setReminderHours(_ hours: Int) async {
        guard let notificationPreferences,
              let notificationScheduler,
              let appStore else { return }
        reminderHours = NotificationPreferences.fixedLeadHours
        notificationPreferences.leadHours = NotificationPreferences.fixedLeadHours
        do {
            try await notificationScheduler.reschedule(
                apps: try await appStore.fetchAll(),
                enabled: notificationsEnabled,
                leadHours: NotificationPreferences.fixedLeadHours
            )
            notificationStatus = await notificationScheduler.status(sealEnabled: notificationsEnabled)
        } catch {
            alertFailure = Self.failure(
                title: "无法设置提醒",
                reason: "通知配置失败",
                recovery: "重试",
                code: "SEAL-NOTIFY-002"
            )
        }
    }

    func refreshStorageUsage() async {
        guard let fileStore else {
            storageUsage = .empty
            return
        }
        do {
            storageUsage = try await fileStore.storageUsage()
        } catch {
            storageUsage = .empty
        }
    }

    func clearTemporaryFiles() async {
        guard let fileStore else { return }
        guard let operationLease = acquireOperation(.maintainingStorage) else { return }
        defer { releaseOperation(operationLease) }
        do {
            try await fileStore.clearTemporaryFiles()
            await refreshStorageUsage()
            try? await logStore?.append(
                category: .system,
                message: "临时缓存与签名工作区已清理"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法清理缓存",
                reason: "临时文件仍在使用",
                recovery: "稍后重试",
                code: "SEAL-STORAGE-001"
            )
        }
    }

    func clearIPAAndSigningCache() async {
        guard let fileStore, let appStore else { return }
        guard let operationLease = acquireOperation(.maintainingStorage) else { return }
        defer { releaseOperation(operationLease) }
        do {
            let apps = try await appStore.fetchAll()
            var historyUpdateFailures = 0
            // A persisted Signed.ipa is a user-visible artifact, not cache. Only
            // unsigned imports and true temporary workspaces may be removed here.
            let removableImportedApps = apps.filter { app in
                app.isSeal == false
                    && app.state != .installed
                    && app.hasSignedArtifact == false
            }
            for app in removableImportedApps {
                try await appStore.delete(id: app.id)
                try await fileStore.removeApp(appID: app.id)
                if let signingHistoryStore {
                    do {
                        try await signingHistoryStore.markDeleted(appID: app.id)
                    } catch {
                        historyUpdateFailures += 1
                    }
                }
            }

            let remainingApps = try await appStore.fetchAll()
            try await fileStore.clearTemporaryFiles()
            try await fileStore.clearOrphanedAppFiles(validAppIDs: Set(remainingApps.map(\.id)))

            if let signingHistoryStore {
                signingHistory = try await signingHistoryStore.records()
            }
            signingHistoryIconData = await loadSigningHistoryIcons(for: signingHistory)
            await refreshStorageUsage()
            try? await logStore?.append(
                category: .system,
                message: "待签名 IPA 与临时签名工作区已清理；正式 Signed.ipa 已保留"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
            if historyUpdateFailures > 0 {
                alertFailure = Self.failure(
                    title: "缓存已清理",
                    reason: "IPA 文件已清理，但有 \(historyUpdateFailures) 个签名历史状态未能同步。",
                    recovery: "稍后重新打开 Seal 检查日志",
                    code: "SEAL-HISTORY-002"
                )
            }
        } catch {
            alertFailure = Self.failure(
                title: "无法清理 IPA 与临时缓存",
                reason: "本地文件仍在使用或存储记录无法更新",
                recovery: "关闭正在进行的签名任务后重试",
                code: "SEAL-STORAGE-003"
            )
        }
    }

    /// Legacy API retained for call-site compatibility. Formal Signed.ipa files
    /// are never considered cache; this now only clears transient workspaces.
    func clearSignedIPACache() async {
        await clearTemporaryFiles()
    }

    func clearLogs() async {
        guard let logStore else { return }
        do {
            try await logStore.clear()
            logs = []
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法清理日志",
                reason: "日志文件仍在使用",
                recovery: "重试",
                code: "SEAL-LOG-001"
            )
        }
    }

    func resetCertificate(for account: AppleAccountRecord) async {
        guard let accountRepository else { return }
        guard let operationLease = acquireOperation(.managingCertificate) else { return }
        defer { releaseOperation(operationLease) }
        var updated = account
        updated.certificateSerialNumber = nil
        updated.selectedCertificateSerialNumber = nil
        do {
            try await accountRepository.save(updated)
            try await keychain?.clearSigningMaterial(accountID: account.id)
            certificateInventories[account.id] = nil
            await load(force: true)
            try? await logStore?.append(
                category: .account,
                message: "本地签名证书缓存已清除，下次签名会重新申请证书"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法更新证书",
                reason: "证书状态或 Keychain 缓存保存失败",
                recovery: "重新验证 Apple ID",
                code: "SEAL-CERT-101"
            )
        }
    }

    private func acquireOperation(
        _ kind: OperationCoordinator.Kind,
        appID: UUID? = nil
    ) -> OperationCoordinator.Lease? {
        guard let operationCoordinator else {
            return .uncoordinated(kind, appID: appID)
        }
        guard let lease = operationCoordinator.begin(kind, appID: appID) else {
            alertFailure = operationCoordinator.conflictFailure(requested: kind)
            return nil
        }
        return lease
    }

    private func releaseOperation(_ lease: OperationCoordinator.Lease) {
        operationCoordinator?.end(lease)
    }

    private func refreshLogExportText() {
        let formatter = ISO8601DateFormatter()
        logExportText = logs.map { entry in
            let code = entry.code.map { " [\($0)]" } ?? ""
            return "\(formatter.string(from: entry.timestamp)) \(entry.level.rawValue.uppercased()) \(entry.category.rawValue)\(code) \(entry.message)"
        }.joined(separator: "\n")
    }

    func handlePairingImporterFailure(_ error: Error) {
        let cocoaError = error as? CocoaError
        guard cocoaError?.code != .userCancelled else { return }
        alertFailure = Self.failure(
            title: "无法选择文件",
            reason: "文件选择失败",
            recovery: "重试",
            code: "SEAL-PAIR-204"
        )
    }

    static func preview() -> SettingsViewModel {
        let model = SettingsViewModel()
        model.accounts = [
            AppleAccountRecord(
                maskedEmail: "d***@icloud.com",
                accountIdentifier: "preview-account",
                teamID: "PREVIEWTEAM",
                teamName: "个人团队",
                isFreeTeam: true,
                status: .verified,
                certificateSerialNumber: "PREVIEW-CERTIFICATE",
                selectedCertificateSerialNumber: "PREVIEW-CERTIFICATE",
                lastVerifiedAt: Date()
            )
        ]
        model.activeAccountID = model.accounts.first?.id
        model.fullAccountEmails[model.accounts[0].id] = "demo@icloud.com"
        model.pairingRecord = PairingRecord(
            deviceIdentifier: "PREVIEW-DEVICE",
            isRemotePairing: true
        )
        return model
    }

    private static let localDevVPNUnavailableFailure = ImportFailure(
        title: "安装通道未就绪",
        reason: "未检测到可用的本机安装通道。",
        recovery: "一键检测",
        code: "SEAL-INSTALL-706"
    )


    private static func failure(
        title: String,
        reason: String,
        recovery: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(
            title: title,
            reason: reason,
            recovery: recovery,
            code: code
        )
    }
}

import Combine
import Foundation

enum SettingsRoute: Hashable {
    case account
    case addAccount
    case certificates
    case accountDetail(UUID)
    case signingHistory(UUID)
    case pairing
    case localDevVPN
    case storage
    case logs
}

@MainActor
final class SettingsViewModel: ObservableObject {
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
    @Published private(set) var notificationsEnabled = false
    @Published private(set) var reminderHours = 24
    @Published private(set) var anisetteServers: [AnisetteServer] = []
    @Published private(set) var selectedAnisetteServerID: String?
    @Published private(set) var storageUsage: SettingsStorageUsage = .empty
    @Published private(set) var logExportText = ""
    @Published var isPairingImporterPresented = false
    @Published var alertFailure: ImportFailure?
    @Published var requestedRoute: SettingsRoute?

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
    private let notificationScheduler: ExpiryNotificationScheduler?
    private let notificationPreferences: NotificationPreferences?
    private let anisetteEnvironment: (any AnisetteEnvironmentManaging)?
    private var hasLoaded = false

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
        anisetteEnvironment: any AnisetteEnvironmentManaging
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
        self.notificationScheduler = notificationScheduler
        self.notificationPreferences = notificationPreferences
        self.anisetteEnvironment = anisetteEnvironment
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
        notificationScheduler = nil
        notificationPreferences = nil
        anisetteEnvironment = nil
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
        notificationScheduler = nil
        notificationPreferences = nil
        anisetteEnvironment = nil
        hasLoaded = true
    }

    var environment: EnvironmentSnapshot {
        EnvironmentSnapshot(
            accountCount: accounts.count,
            verifiedAccountCount: accounts.filter { $0.status == .verified }.count,
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
        do {
            async let storedAccounts = accountRepository.fetchAll()
            async let storedPairing = pairingStore.current()
            accounts = await refreshedAccountDisplayNames(try await storedAccounts)
            pairingRecord = try await storedPairing
            logs = (try? await logStore?.entries()) ?? []
            signingHistory = (try? await signingHistoryStore?.records()) ?? []
            signingHistoryIconData = await loadSigningHistoryIcons(for: signingHistory)
            if let anisetteEnvironment {
                async let availableServers = anisetteEnvironment.availableServers()
                async let selectedServerID = anisetteEnvironment.selectedServerID()
                anisetteServers = await availableServers
                selectedAnisetteServerID = (await selectedServerID) ?? anisetteServers.first?.id
            }
            if let notificationPreferences {
                notificationsEnabled = notificationPreferences.isEnabled
                reminderHours = notificationPreferences.leadHours
            }
            refreshLogExportText()
            await refreshStorageUsage()
            hasLoaded = true
        } catch {
            alertFailure = Self.failure(
                title: "无法读取设置",
                reason: "本地配置不可用",
                recovery: "重试",
                code: "SEAL-SET-001"
            )
        }
    }

    private func refreshedAccountDisplayNames(_ storedAccounts: [AppleAccountRecord]) async -> [AppleAccountRecord] {
        guard let keychain, let accountRepository else { return storedAccounts }
        var refreshedAccounts: [AppleAccountRecord] = []

        for var account in storedAccounts {
            if let secret = try? await keychain.load(accountID: account.id) {
                let readableMaskedEmail = AppleAccountClient.mask(secret.email)
                if account.maskedEmail != readableMaskedEmail {
                    account.maskedEmail = readableMaskedEmail
                    try? await accountRepository.save(account)
                }
            }
            refreshedAccounts.append(account)
        }

        return refreshedAccounts
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

    func isCertificateInventoryLoading(accountID: UUID) -> Bool {
        certificateInventoryLoadingIDs.contains(accountID)
    }

    func refreshCertificateInventories() async {
        for account in accounts where account.status == .verified {
            await refreshCertificateInventory(for: account, force: false)
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
                throw Self.failure(
                    title: "Apple 侧同步失败",
                    reason: "本机没有此 Apple ID 的登录凭据。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-INVENTORY-100"
                )
            }
            let inventory = try await applePortalInventoryService.fetchInventory(
                account: account,
                secret: secret
            )
            certificateInventories[account.id] = inventory
            certificateInventoryFailures[account.id] = nil
            try? await logStore?.append(
                category: .account,
                message: "Apple 侧证书与 App ID 已同步：\(inventory.usedBundleIDCount) 个 Bundle ID"
            )
        } catch let failure as ImportFailure {
            certificateInventories[account.id] = nil
            certificateInventoryFailures[account.id] = failure
            try? await logStore?.append(
                category: .account,
                level: .error,
                message: failure.reason,
                code: failure.code
            )
        } catch {
            let nsError = error as NSError
            let failure = Self.failure(
                title: "Apple 侧同步失败",
                reason: "Apple 返回：[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)",
                recovery: "重新同步",
                code: "SEAL-INVENTORY-900"
            )
            certificateInventories[account.id] = nil
            certificateInventoryFailures[account.id] = failure
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
        guard let notificationScheduler,
              let notificationPreferences,
              let appStore,
              await notificationScheduler.authorizationStatus() == .notDetermined else {
            return
        }
        do {
            let granted = try await notificationScheduler.requestAuthorization()
            guard granted else { return }
            notificationPreferences.isEnabled = true
            notificationsEnabled = true
            try await notificationScheduler.reschedule(
                apps: try await appStore.fetchAll(),
                enabled: true,
                leadHours: reminderHours
            )
        } catch {
            return
        }
    }

    func selectAnisetteServer(id: String) async {
        guard let anisetteEnvironment,
              anisetteServers.contains(where: { $0.id == id }) else { return }
        await anisetteEnvironment.selectServer(id: id)
        selectedAnisetteServerID = id
    }

    func resetSigningEnvironment() async {
        guard let anisetteEnvironment else { return }
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
              let accountRepository,
              let keychain,
              let accountClient else { return false }
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

            if let existingAccount,
               existingAccount.accountIdentifier != authenticated.record.accountIdentifier
                    || existingAccount.teamID != authenticated.record.teamID {
                throw Self.failure(
                    title: "账号不匹配",
                    reason: "重新验证必须使用原来的 Apple ID 和 Team。当前输入的账号属于另一组 Apple ID / Team，Seal 已阻止覆盖原账号绑定。",
                    recovery: "返回后选择添加新账号",
                    code: "SEAL-AUTH-110"
                )
            }

            let storedAccounts = (try? await accountRepository.fetchAll()) ?? []
            let replacingAccountID = existingAccount?.id
            let duplicateAccount = storedAccounts.first { candidate in
                if let replacingAccountID, candidate.id == replacingAccountID { return false }
                return candidate.accountIdentifier == authenticated.record.accountIdentifier
                    && candidate.teamID == authenticated.record.teamID
            }
            let baseAccount = existingAccount ?? duplicateAccount
            let record = baseAccount.map {
                AppleAccountRecord(
                    id: $0.id,
                    maskedEmail: authenticated.record.maskedEmail,
                    accountIdentifier: authenticated.record.accountIdentifier,
                    teamID: authenticated.record.teamID,
                    teamName: authenticated.record.teamName,
                    isFreeTeam: authenticated.record.isFreeTeam,
                    status: .verified,
                    certificateSerialNumber: nil,
                    lastVerifiedAt: authenticated.record.lastVerifiedAt
                )
            } ?? authenticated.record

            let previousSecret = try? await keychain.load(accountID: record.id)
            try await keychain.save(authenticated.secret, for: record.id)
            do {
                try await accountRepository.save(record)
            } catch {
                if let previousSecret {
                    try? await keychain.save(previousSecret, for: record.id)
                } else {
                    try? await keychain.delete(accountID: record.id)
                }
                throw error
            }
            await load(force: true)
            try? await logStore?.append(
                category: .account,
                message: duplicateAccount == nil ? "Apple ID 已添加" : "Apple ID 已重新绑定到现有账号记录"
            )
            return true
        } catch is CancellationError {
            return false
        } catch let failure as ImportFailure {
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
            let failure = Self.failure(
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

    func deleteAccount(_ account: AppleAccountRecord) async {
        guard let accountRepository, let keychain else { return }
        let relatedApps = (try? await appStore?.fetchAll())?
            .filter { $0.accountID == account.id } ?? []
        let storedSecret = try? await keychain.load(accountID: account.id)
        do {
            try await accountRepository.delete(id: account.id)
            try await keychain.delete(accountID: account.id)
            await load(force: true)
            try? await logStore?.append(
                category: .account,
                message: "Apple ID 已移除；关联应用保留原账号绑定，用于防止误用其他账号续签。关联应用数：\(relatedApps.count)"
            )
        } catch {
            try? await accountRepository.save(account)
            if let storedSecret {
                try? await keychain.save(storedSecret, for: account.id)
            }
            await load(force: true)
            alertFailure = Self.failure(
                title: "无法移除账号",
                reason: "本地数据未能更新",
                recovery: "重试",
                code: "SEAL-AUTH-106"
            )
        }
    }

    func email(for account: AppleAccountRecord) async -> String {
        guard let keychain else { return "" }
        return (try? await keychain.load(accountID: account.id))?.email ?? ""
    }

    func importPairingFile(_ url: URL) async {
        guard let pairingStore else { return }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            pairingRecord = try await pairingStore.importFile(at: url)
            diagnosticState = .idle
            installDiagnostics = .empty
            try? await logStore?.append(
                category: .pairing,
                message: "配对文件已导入"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch let failure as ImportFailure {
            alertFailure = failure
        } catch {
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
        do {
            try await pairingStore.remove()
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
        diagnosticState = .running
        do {
            for var account in accounts {
                guard let secret = try await keychain.load(accountID: account.id) else {
                    throw Self.failure(
                        title: "账号需要验证",
                        reason: "本机凭据不存在",
                        recovery: "重新验证账号",
                        code: "SEAL-AUTH-105"
                    )
                }
                do {
                    try await accountClient.validate(account: account, secret: secret)
                    account.status = .verified
                    account.maskedEmail = AppleAccountClient.mask(secret.email)
                    account.lastVerifiedAt = Date()
                    try await accountRepository.save(account)
                } catch let failure as ImportFailure {
                    account.status = .needsVerification
                    try? await accountRepository.save(account)
                    throw failure
                } catch {
                    account.status = .needsVerification
                    try? await accountRepository.save(account)
                    throw Self.failure(
                        title: "Apple ID 需要重新验证",
                        reason: "登录状态已失效，请重新验证后重试",
                        recovery: "重新验证 Apple ID",
                        code: "SEAL-AUTH-102"
                    )
                }
            }
            await runInstallChannelCheck(successMessage: "签名环境检测正常")
        } catch let failure as ImportFailure {
            await finishInstallChannelCheckWithFailure(failure, logMessage: "签名环境检测失败")
        } catch {
            await finishInstallChannelCheckWithFailure(Self.localDevVPNUnavailableFailure, logMessage: "签名环境检测失败")
        }
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
        let diagnostics = await installChannel.diagnose()
        installDiagnostics = diagnostics
        if diagnostics.isReady, let deviceIdentifier = diagnostics.deviceIdentifier {
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

    private func finishInstallChannelCheckWithFailure(
        _ failure: ImportFailure,
        diagnostics: InstallChannelDiagnostics? = nil,
        logMessage: String
    ) async {
        await load(force: true)
        if let diagnostics { installDiagnostics = diagnostics }
        diagnosticState = .failed(failure)
        try? await logStore?.append(
            category: .installation,
            level: .error,
            message: logMessage,
            code: failure.code
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
                    throw Self.failure(
                        title: "通知未开启",
                        reason: "系统未授予通知权限",
                        recovery: "知道了",
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
        } catch let failure as ImportFailure {
            notificationsEnabled = false
            notificationPreferences.isEnabled = false
            alertFailure = failure
        } catch {
            notificationsEnabled = false
            notificationPreferences.isEnabled = false
            alertFailure = Self.failure(
                title: "无法设置提醒",
                reason: "通知配置失败",
                recovery: "重试",
                code: "SEAL-NOTIFY-002"
            )
        }
    }

    func setReminderHours(_ hours: Int) async {
        guard let notificationPreferences,
              let notificationScheduler,
              let appStore else { return }
        reminderHours = hours
        notificationPreferences.leadHours = hours
        do {
            try await notificationScheduler.reschedule(
                apps: try await appStore.fetchAll(),
                enabled: notificationsEnabled,
                leadHours: hours
            )
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
        do {
            var apps = try await appStore.fetchAll()
            let removableImportedApps = apps.filter { app in
                app.isSeal == false && app.state != .installed
            }
            for app in removableImportedApps {
                try await appStore.delete(id: app.id)
                try await fileStore.removeApp(appID: app.id)
                try? await signingHistoryStore?.markDeleted(appID: app.id)
            }

            apps = try await appStore.fetchAll()
            try await fileStore.clearSignedIPAs()
            try await fileStore.clearTemporaryFiles()
            try await fileStore.clearOrphanedAppFiles(validAppIDs: Set(apps.map(\.id)))

            for index in apps.indices where apps[index].signedIPARelativePath != nil {
                apps[index].signedIPARelativePath = nil
                try await appStore.save(apps[index])
            }

            signingHistory = (try? await signingHistoryStore?.records()) ?? signingHistory
            signingHistoryIconData = await loadSigningHistoryIcons(for: signingHistory)
            await refreshStorageUsage()
            try? await logStore?.append(
                category: .system,
                message: "IPA 与签名缓存已真实清理"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法清理 IPA 与签名缓存",
                reason: "本地文件仍在使用或存储记录无法更新",
                recovery: "关闭正在进行的签名任务后重试",
                code: "SEAL-STORAGE-003"
            )
        }
    }

    func clearSignedIPACache() async {
        guard let fileStore, let appStore else { return }
        do {
            try await fileStore.clearSignedIPAs()
            var apps = try await appStore.fetchAll()
            for index in apps.indices where apps[index].signedIPARelativePath != nil {
                apps[index].signedIPARelativePath = nil
                try await appStore.save(apps[index])
            }
            await refreshStorageUsage()
            try? await logStore?.append(
                category: .system,
                message: "签名产物缓存已清理"
            )
            logs = (try? await logStore?.entries()) ?? logs
            refreshLogExportText()
        } catch {
            alertFailure = Self.failure(
                title: "无法清理签名产物",
                reason: "本地文件清理失败",
                recovery: "重试",
                code: "SEAL-STORAGE-002"
            )
        }
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
        var updated = account
        updated.certificateSerialNumber = nil
        do {
            try await accountRepository.save(updated)
            try await keychain?.clearSigningMaterial(accountID: account.id)
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
                lastVerifiedAt: Date()
            )
        ]
        model.pairingRecord = PairingRecord(
            deviceIdentifier: "PREVIEW-DEVICE",
            isRemotePairing: true
        )
        return model
    }

    private static let localDevVPNUnavailableFailure = ImportFailure(
        title: "安装通道未就绪",
        reason: "未检测到可用的本机安装通道。请确认 iOS 设置中的 LocalDevVPN 状态为已连接，然后返回 Seal 重新检测。",
        recovery: "重新检测",
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

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
    @Published private(set) var isCertificateOperationRunning = false
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
    private let applePortalCertificateService: ApplePortalCertificateService?
    private let notificationScheduler: ExpiryNotificationScheduler?
    private let notificationPreferences: NotificationPreferences?
    private let anisetteEnvironment: (any AnisetteEnvironmentManaging)?
    private let signingPreferenceStore: SigningPreferenceStore?
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
        anisetteEnvironment: any AnisetteEnvironmentManaging,
        signingPreferenceStore: SigningPreferenceStore
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
            let fetchedAccounts = try await storedAccounts
            accounts = await refreshedAccountDisplayNames(fetchedAccounts)
            pairingRecord = try await storedPairing
            fullAccountEmails = await loadFullAccountEmails(for: accounts)
            loadCertificateInventoryCache(for: accounts)

            let storedApps = (try? await appStore?.fetchAll()) ?? []
            appIconData = await loadAppIcons(for: storedApps)

            let preferredAccountID: UUID?
            if let signingPreferenceStore {
                preferredAccountID = await signingPreferenceStore.activeAccountID()
            } else {
                preferredAccountID = nil
            }
            let verifiedAccounts = accounts.filter { $0.status == .verified }
            if let preferredAccountID,
               verifiedAccounts.contains(where: { $0.id == preferredAccountID }) {
                activeAccountID = preferredAccountID
            } else {
                activeAccountID = verifiedAccounts.first?.id
                await signingPreferenceStore?.setActiveAccountID(activeAccountID)
            }

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

    var activeAccount: AppleAccountRecord? {
        guard let activeAccountID else { return nil }
        return accounts.first { $0.id == activeAccountID }
    }

    func fullEmail(for account: AppleAccountRecord) -> String {
        fullAccountEmails[account.id] ?? account.maskedEmail
    }

    func selectActiveAccount(_ account: AppleAccountRecord) async {
        guard account.status == .verified,
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

        isCertificateOperationRunning = true
        defer { isCertificateOperationRunning = false }

        do {
            guard let originalSecret = try await keychain.load(accountID: account.id) else {
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
            let nsError = error as NSError
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

        isCertificateOperationRunning = true
        defer { isCertificateOperationRunning = false }

        do {
            guard let originalSecret = try await keychain.load(accountID: account.id) else {
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
            let nsError = error as NSError
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

        isCertificateOperationRunning = true
        defer { isCertificateOperationRunning = false }

        do {
            guard let originalSecret = try await keychain.load(accountID: account.id) else {
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
            let nsError = error as NSError
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
            updatedAccount.lastVerifiedAt = Date()
            try await accountRepository.save(updatedAccount)
        } catch {
            let rollbackSucceeded: Bool
            do {
                try await certificateService.revokeCertificate(
                    serialNumber: material.serialNumber,
                    account: originalAccount,
                    secret: material.updatedSecret
                )
                rollbackSucceeded = true
            } catch {
                rollbackSucceeded = false
            }
            try? await keychain.save(originalSecret, for: originalAccount.id)
            try? await accountRepository.save(originalAccount)
            guard rollbackSucceeded else {
                throw Self.failure(
                    title: "签名失败",
                    reason: "Apple 返回：无法创建签名证书",
                    recovery: "重试",
                    code: "SEAL-CERT-215"
                )
            }
            if let failure = error as? ImportFailure { throw failure }
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
    ) async -> [AppleAccountRecord] {
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
                try? await accountRepository.save(account)
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
            guard let path = app.iconRelativePath,
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

    func isCertificateInventoryLoading(accountID: UUID) -> Bool {
        certificateInventoryLoadingIDs.contains(accountID)
    }

    func refreshCertificateInventories() async {
        for account in accounts where account.status == .verified {
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
            saveCertificateInventoryCache(inventory)
            try? await logStore?.append(
                category: .account,
                message: "Apple 侧证书与 App ID 已同步：\(inventory.usedBundleIDCount) 个 Bundle ID"
            )
        } catch let failure as ImportFailure {
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
                reason: "来源：\(nsError.domain) \(nsError.code)；\(nsError.localizedDescription)",
                recovery: "重新同步",
                code: "SEAL-INVENTORY-900"
            )
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

            let canReplaceExistingAccount = existingAccount.map { account in
                account.accountIdentifier == authenticated.record.accountIdentifier
                    && account.teamID == authenticated.record.teamID
            } ?? false

            let storedAccounts = (try? await accountRepository.fetchAll()) ?? []
            let replacingAccountID = canReplaceExistingAccount ? existingAccount?.id : nil
            let duplicateAccount = storedAccounts.first { candidate in
                if let replacingAccountID, candidate.id == replacingAccountID { return false }
                return candidate.accountIdentifier == authenticated.record.accountIdentifier
                    && candidate.teamID == authenticated.record.teamID
            }
            let baseAccount = canReplaceExistingAccount ? existingAccount : duplicateAccount
            let record = baseAccount.map {
                AppleAccountRecord(
                    id: $0.id,
                    maskedEmail: authenticated.record.maskedEmail,
                    accountIdentifier: authenticated.record.accountIdentifier,
                    teamID: authenticated.record.teamID,
                    teamName: authenticated.record.teamName,
                    isFreeTeam: authenticated.record.isFreeTeam,
                    status: .verified,
                    certificateSerialNumber: $0.certificateSerialNumber,
                    selectedCertificateSerialNumber: $0.selectedCertificateSerialNumber,
                    lastVerifiedAt: authenticated.record.lastVerifiedAt
                )
            } ?? authenticated.record

            let previousSecret = try? await keychain.load(accountID: record.id)
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
                if let previousSecret {
                    try? await keychain.save(previousSecret, for: record.id)
                } else {
                    try? await keychain.delete(accountID: record.id)
                }
                throw error
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
            diagnosticState = .running
            installDiagnostics = .empty

            if let installChannel {
                let diagnostics = await installChannel.diagnose()
                installDiagnostics = diagnostics
                if let deviceIdentifier = diagnostics.deviceIdentifier {
                    pairingRecord = try await pairingStore.markValidated(
                        deviceIdentifier: deviceIdentifier
                    )
                } else {
                    pairingRecord = try await pairingStore.markConnectionFailed()
                }

                if diagnostics.isReady, let deviceIdentifier = diagnostics.deviceIdentifier {
                    diagnosticState = .ready(deviceIdentifier: deviceIdentifier)
                } else if let failure = diagnostics.failure {
                    diagnosticState = .failed(failure)
                    alertFailure = failure
                } else {
                    diagnosticState = .idle
                }
            } else {
                diagnosticState = .idle
            }

            try? await logStore?.append(
                category: .pairing,
                message: pairingRecord?.isVerifiedForCurrentDevice == true
                    ? "配对文件已导入并通过当前设备验证。完整 UDID：\(pairingRecord?.effectiveDeviceIdentifier ?? "")"
                    : "配对文件已导入，等待真实设备连接验证"
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

        let selected = activeAccount
            ?? accounts.first(where: { $0.status == .verified })
            ?? accounts.first
        guard var account = selected else { return }
        if activeAccountID != account.id {
            activeAccountID = account.id
            await signingPreferenceStore?.setActiveAccountID(account.id)
        }

        diagnosticState = .running
        do {
            guard let secret = try await keychain.load(accountID: account.id) else {
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
                    reason: "当前签名 Apple ID 的登录状态已失效。",
                    recovery: "重新验证 Apple ID",
                    code: "SEAL-AUTH-102"
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

    private func finishInstallChannelCheckWithFailure(
        _ failure: ImportFailure,
        diagnostics: InstallChannelDiagnostics? = nil,
        logMessage: String
    ) async {
        if let pairingStore {
            if let deviceIdentifier = diagnostics?.deviceIdentifier {
                pairingRecord = try? await pairingStore.markValidated(
                    deviceIdentifier: deviceIdentifier
                )
            } else {
                pairingRecord = try? await pairingStore.markConnectionFailed()
            }
        }
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

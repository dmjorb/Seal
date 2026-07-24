import Combine
import Foundation

@MainActor
final class AppsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case committing
    }

    enum SigningChannelStatus: Equatable {
        case idle
        case connecting
        case ready
        case unavailable
    }

    @Published private(set) var apps: [AppRecord]
    @Published private(set) var accounts: [AppleAccountRecord]
    @Published private(set) var fullAccountEmails: [UUID: String] = [:]
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var iconData: [UUID: Data]
    @Published private(set) var phase: Phase
    @Published var isImporterPresented = false
    @Published var isImportSheetPresented: Bool
    @Published private(set) var sheetDraft: ImportDraft?
    @Published private(set) var sheetFailure: ImportFailure?
    @Published var alertFailure: ImportFailure?
    @Published var accountSelectionApp: AppRecord?
    @Published var selectedOperationApp: AppRecord?
    @Published var signingSession: SigningSession?
    @Published var batchRefreshSession: BatchRefreshSession?
    @Published private(set) var importCompletionCount = 0
    @Published private(set) var pendingRefreshCount = 0
    @Published var shouldOpenSettings = false
    @Published var requestedSettingsRoute: SettingsRoute?
    @Published private(set) var signingChannelStatus: SigningChannelStatus = .idle
    @Published private(set) var autoRenewInProgress = false
    @Published private(set) var installingSignedAppID: UUID?

    private let workflow: ImportWorkflow?
    private let appStore: (any AppStore)?
    private let fileStore: AppFileStore?
    private let accountRepository: (any AccountRepository)?
    private let keychain: KeychainVault?
    private let signingCoordinator: SigningCoordinator?
    private let installChannel: (any InstallChannel)?
    private let renewalCoordinator: RenewalCoordinator?
    private let appRecordRecovery: AppRecordRecovery?
    private let selfAppRegistrar: SelfAppRegistrar?
    private let logStore: SealLogStore?
    private let signingHistoryStore: SigningHistoryStore?
    private let notificationScheduler: ExpiryNotificationScheduler?
    private let notificationPreferences: NotificationPreferences?
    private let signingPreferenceStore: SigningPreferenceStore?
    private let operationCoordinator: OperationCoordinator?
    private let dailyAutoRenewStateStore: DailyAutoRenewStateStore
    private var signingTask: Task<Void, Never>?
    private var batchRefreshTask: Task<Void, Never>?
    private var channelTask: Task<Bool, Never>?
    private var pendingVPNAction: PendingVPNAction?
    private var currentAutoRenewDayKey: String?
    private var hasLoaded = false
    private var loadGeneration = 0

    private enum PendingVPNAction {
        case signing(
            AppRecord,
            accountID: UUID?,
            requestedBundleIdentifier: String?,
            completionMode: SigningCompletionMode
        )
        case batch(
            resume: Bool,
            dueLeadHours: Int?,
            dueCutoff: Date?,
            enforceCooldown: Bool,
            dailyAutoRenewDayKey: String?
        )
    }

    init(
        workflow: ImportWorkflow,
        appStore: any AppStore,
        fileStore: AppFileStore,
        accountRepository: any AccountRepository,
        keychain: KeychainVault,
        signingCoordinator: SigningCoordinator,
        installChannel: any InstallChannel,
        renewalCoordinator: RenewalCoordinator,
        appRecordRecovery: AppRecordRecovery,
        selfAppRegistrar: SelfAppRegistrar?,
        logStore: SealLogStore,
        signingHistoryStore: SigningHistoryStore,
        notificationScheduler: ExpiryNotificationScheduler,
        notificationPreferences: NotificationPreferences,
        signingPreferenceStore: SigningPreferenceStore,
        operationCoordinator: OperationCoordinator? = nil
    ) {
        self.workflow = workflow
        self.appStore = appStore
        self.fileStore = fileStore
        self.accountRepository = accountRepository
        self.keychain = keychain
        self.signingCoordinator = signingCoordinator
        self.installChannel = installChannel
        self.renewalCoordinator = renewalCoordinator
        self.appRecordRecovery = appRecordRecovery
        self.selfAppRegistrar = selfAppRegistrar
        self.logStore = logStore
        self.signingHistoryStore = signingHistoryStore
        self.notificationScheduler = notificationScheduler
        self.notificationPreferences = notificationPreferences
        self.signingPreferenceStore = signingPreferenceStore
        self.operationCoordinator = operationCoordinator
        self.dailyAutoRenewStateStore = DailyAutoRenewStateStore()
        apps = []
        accounts = []
        iconData = [:]
        phase = .idle
        isImportSheetPresented = false
    }

    init(startupFailure: ImportFailure) {
        workflow = nil
        appStore = nil
        fileStore = nil
        accountRepository = nil
        keychain = nil
        signingCoordinator = nil
        installChannel = nil
        renewalCoordinator = nil
        appRecordRecovery = nil
        selfAppRegistrar = nil
        logStore = nil
        signingHistoryStore = nil
        notificationScheduler = nil
        notificationPreferences = nil
        signingPreferenceStore = nil
        operationCoordinator = nil
        dailyAutoRenewStateStore = DailyAutoRenewStateStore()
        apps = []
        accounts = []
        iconData = [:]
        phase = .idle
        isImportSheetPresented = false
        alertFailure = startupFailure
    }

    private init(apps: [AppRecord], draft: ImportDraft?) {
        workflow = nil
        appStore = nil
        fileStore = nil
        accountRepository = nil
        keychain = nil
        signingCoordinator = nil
        installChannel = nil
        renewalCoordinator = nil
        appRecordRecovery = nil
        selfAppRegistrar = nil
        logStore = nil
        signingHistoryStore = nil
        notificationScheduler = nil
        notificationPreferences = nil
        signingPreferenceStore = nil
        operationCoordinator = nil
        dailyAutoRenewStateStore = DailyAutoRenewStateStore()
        self.apps = apps
        accounts = []
        iconData = [:]
        phase = .idle
        sheetDraft = draft
        isImportSheetPresented = draft != nil
        hasLoaded = true
    }

    var unsignedApps: [AppRecord] {
        apps
            .filter {
                $0.isSeal == false
                    && $0.state != .installed
                    && $0.state != .signed
                    && $0.hasSignedArtifact == false
            }
            .sorted { lhs, rhs in
                if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }


    var signedApps: [AppRecord] {
        apps
            .filter { $0.isSeal == false && $0.state != .installed && ($0.state == .signed || $0.hasSignedArtifact) }
            .sorted { lhs, rhs in
                let left = lhs.lastSignedAt ?? lhs.importedAt
                let right = rhs.lastSignedAt ?? rhs.importedAt
                if left != right { return left > right }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    var installedApps: [AppRecord] {
        apps.filter { $0.state == .installed || $0.isSeal }
            .sorted { lhs, rhs in
                if lhs.isSeal != rhs.isSeal { return lhs.isSeal }
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }

                let lhsRank = installedSortRank(for: lhs)
                let rhsRank = installedSortRank(for: rhs)
                if lhsRank != rhsRank { return lhsRank > rhsRank }

                let lhsExpiry = lhs.expiryDate ?? .distantPast
                let rhsExpiry = rhs.expiryDate ?? .distantPast
                if lhsExpiry != rhsExpiry { return lhsExpiry > rhsExpiry }

                if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var hasPendingVPNRecovery: Bool {
        pendingVPNAction != nil
    }

    var availableAccounts: [AppleAccountRecord] {
        accounts.filter { AccountAvailabilityPolicy.isSelectable($0) }
    }

    // Kept for existing call sites; locally available accounts remain selectable
    // while offline even if a fresh Portal validation has not run yet.
    var verifiedAccounts: [AppleAccountRecord] { availableAccounts }

    func selectActiveAccount(id: UUID) async {
        guard availableAccounts.contains(where: { $0.id == id }) else { return }
        activeAccountID = id
        await signingPreferenceStore?.setActiveAccountID(id)
    }

    func refreshActiveAccountSelection() async {
        guard let signingPreferenceStore else { return }
        let storedID = await signingPreferenceStore.activeAccountID()
        if let storedID, accounts.contains(where: { $0.id == storedID }) {
            activeAccountID = storedID
        } else if let current = activeAccountID, accounts.contains(where: { $0.id == current }) {
            // Keep the in-memory choice. Do not clear it because connectivity changed.
        } else if activeAccountID == nil {
            activeAccountID = availableAccounts.first?.id
            if storedID == nil {
                await signingPreferenceStore.setActiveAccountID(activeAccountID)
            }
        }
    }

    private func installedSortRank(for app: AppRecord, now: Date = Date()) -> Int {
        guard let expiryDate = app.expiryDate else { return 1 }
        return expiryDate > now ? 2 : 0
    }

    func presentOperation(for app: AppRecord) {
        selectedOperationApp = app
    }

    func dismissOperation() {
        guard signingTask == nil else { return }
        selectedOperationApp = nil
        signingSession = nil
    }

    @discardableResult
    func refreshSigningChannel() async -> Bool {
        if let channelTask {
            return await channelTask.value
        }
        guard let installChannel else {
            signingChannelStatus = .unavailable
            return false
        }

        signingChannelStatus = .connecting
        let task = Task {
            do {
                _ = try await installChannel.start()
                return true
            } catch {
                return false
            }
        }
        channelTask = task
        let ready = await task.value
        channelTask = nil
        signingChannelStatus = ready ? .ready : .unavailable
        return ready
    }

    func load(force: Bool = false) async {
        guard force || hasLoaded == false, let appStore else { return }
        loadGeneration &+= 1
        let generation = loadGeneration

        do {
            if let selfAppRegistrar {
                do {
                    try await selfAppRegistrar.ensureRegistered()
                } catch {
                    try? await logStore?.append(
                        category: .system,
                        level: .error,
                        message: "Seal 自身记录同步失败",
                        code: "SEAL-SELF-REG-001"
                    )
                }
            }
            guard generation == loadGeneration else { return }
            try await appRecordRecovery?.restoreMissingRecords()
            guard generation == loadGeneration else { return }

            let fetched = try await appStore.fetchAll()
            guard generation == loadGeneration else { return }
            var fetchedAccounts = try await accountRepository?.fetchAll() ?? []
            guard generation == loadGeneration else { return }
            fetchedAccounts = try await repairLegacyAccountStatuses(fetchedAccounts)
            guard generation == loadGeneration else { return }

            let loadedFullAccountEmails = await loadFullAccountEmails(for: fetchedAccounts)
            guard generation == loadGeneration else { return }

            var loadedIcons: [UUID: Data] = [:]
            if let fileStore {
                for app in fetched {
                    guard generation == loadGeneration else { return }
                    guard let path = app.displayIconRelativePath,
                          let data = try? await fileStore.read(relativePath: path) else {
                        continue
                    }
                    loadedIcons[app.id] = data
                }
            }
            guard generation == loadGeneration else { return }

            await seedSigningHistoryIfNeeded(apps: fetched, accounts: fetchedAccounts)
            guard generation == loadGeneration else { return }

            let preferredAccountID: UUID?
            if let signingPreferenceStore {
                preferredAccountID = await signingPreferenceStore.activeAccountID()
            } else {
                preferredAccountID = nil
            }
            guard generation == loadGeneration else { return }

            let selectableAccounts = fetchedAccounts.filter { AccountAvailabilityPolicy.isSelectable($0) }
            let resolvedAccountID: UUID?
            if let preferredAccountID, fetchedAccounts.contains(where: { $0.id == preferredAccountID }) {
                resolvedAccountID = preferredAccountID
            } else if let current = activeAccountID, fetchedAccounts.contains(where: { $0.id == current }) {
                resolvedAccountID = current
            } else {
                resolvedAccountID = selectableAccounts.first?.id
                if preferredAccountID == nil {
                    await signingPreferenceStore?.setActiveAccountID(resolvedAccountID)
                    guard generation == loadGeneration else { return }
                }
            }

            let refreshedPendingCount: Int
            if let renewalCoordinator {
                refreshedPendingCount = try await renewalCoordinator.pendingCount()
            } else {
                refreshedPendingCount = 0
            }
            guard generation == loadGeneration else { return }

            if let notificationScheduler, let notificationPreferences {
                do {
                    try await notificationScheduler.reschedule(
                        apps: fetched,
                        enabled: notificationPreferences.isEnabled,
                        leadHours: notificationPreferences.leadHours
                    )
                } catch {
                    try? await logStore?.append(
                        category: .system,
                        level: .error,
                        message: "通知调度失败",
                        code: "SEAL-NOTIFY-002"
                    )
                }
                guard generation == loadGeneration else { return }
            }

            apps = fetched
            accounts = fetchedAccounts
            fullAccountEmails = loadedFullAccountEmails
            activeAccountID = resolvedAccountID
            iconData = loadedIcons
            pendingRefreshCount = refreshedPendingCount
            hasLoaded = true
        } catch let failure as ImportFailure {
            guard generation == loadGeneration else { return }
            alertFailure = failure
        } catch {
            guard generation == loadGeneration else { return }
            alertFailure = Self.dataFailure
        }
    }

    func fullEmail(for account: AppleAccountRecord) -> String {
        fullAccountEmails[account.id] ?? "未记录"
    }

    private func loadFullAccountEmails(
        for accounts: [AppleAccountRecord]
    ) async -> [UUID: String] {
        guard let keychain else { return [:] }
        var values: [UUID: String] = [:]
        for account in accounts {
            guard let secret = try? await keychain.load(accountID: account.id) else { continue }
            values[account.id] = secret.email
        }
        return values
    }

    func performLightweightLaunchCheck() async {
        await load(force: true)
        dailyAutoRenewStateStore.reconcilePendingSelfRenewal(
            currentExpiry: SelfAppMetadata.current()?.expirationDate
        )
    }

    func startDailyAutoRenewIfNeeded(now: Date = Date()) async {
        guard autoRenewInProgress == false,
              signingTask == nil,
              batchRefreshTask == nil,
              dailyAutoRenewStateStore.shouldRun(on: now) else { return }

        let dayKey = dailyAutoRenewStateStore.dayKey(for: now)
        autoRenewInProgress = true
        startBatchRefresh(
            resume: false,
            dailyAutoRenewDayKey: dayKey
        )
        if batchRefreshTask == nil {
            autoRenewInProgress = false
        }
    }

    private func seedSigningHistoryIfNeeded(
        apps: [AppRecord],
        accounts: [AppleAccountRecord]
    ) async {
        guard let signingHistoryStore else { return }
        let existingRecords: [SigningHistoryRecord]
        do {
            existingRecords = try await signingHistoryStore.records()
        } catch {
            surfaceHistoryWarning(
                title: "签名历史读取失败",
                reason: "无法读取历史记录，已跳过本次历史回填。",
                code: "SEAL-HISTORY-004"
            )
            return
        }
        let existingKeys = Set(
            existingRecords.compactMap { record -> String? in
                guard let appID = record.appID else { return nil }
                return "\(record.accountID.uuidString)-\(appID.uuidString)"
            }
        )

        for app in apps where app.state == .installed {
            guard let accountID = app.accountID,
                  let account = accounts.first(where: { $0.id == accountID }) else {
                continue
            }
            let key = "\(accountID.uuidString)-\(app.id.uuidString)"
            guard existingKeys.contains(key) == false else { continue }
            let record = SigningHistoryRecord(
                app: app,
                account: account,
                action: .imported,
                result: .success,
                signedAt: app.importedAt,
                attemptedBundleIdentifier: app.preferredBundleIdentifier,
                finalSignedBundleIdentifier: app.mappedBundleIdentifier,
                lifecycleStatus: .active
            )
            do {
                try await signingHistoryStore.append(record)
            } catch {
                surfaceHistoryWarning(
                    title: "签名历史回填未完成",
                    reason: "部分已有应用的历史记录无法保存。",
                    code: "SEAL-HISTORY-004"
                )
                return
            }
        }
    }

    func presentImporter() {
        guard phase == .idle else { return }
        isImporterPresented = true
    }

    func importSelectedFile(_ url: URL) async {
        guard let workflow, phase == .idle else { return }
        guard let operationLease = acquireOperation(.importing) else { return }
        defer { releaseOperation(operationLease) }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        alertFailure = nil
        sheetFailure = nil
        isImportSheetPresented = false
        phase = .preparing
        await workflow.prepare(sourceURL: url)
        await consumeWorkflowState()
    }

    func confirmImport() async {
        guard let workflow else { return }
        guard let operationLease = acquireOperation(.importing) else { return }
        defer { releaseOperation(operationLease) }
        guard let draft = sheetDraft else {
            sheetFailure = ImportFailure(
                title: "无法导入 IPA",
                reason: "导入确认信息已失效，请重新选择 IPA。",
                recovery: "重新选择",
                code: "SEAL-IPA-211"
            )
            isImportSheetPresented = true
            phase = .idle
            return
        }

        phase = .committing
        sheetFailure = nil
        isImportSheetPresented = true
        await workflow.confirm(preferredDraft: draft)
        await consumeWorkflowState()
    }

    func retryImport() async {
        guard let workflow, sheetDraft != nil else { return }
        guard let operationLease = acquireOperation(.importing) else { return }
        defer { releaseOperation(operationLease) }
        phase = .committing
        sheetFailure = nil
        await workflow.retry()
        await consumeWorkflowState()
    }

    func cancelImport() async {
        var cleanupFailure: ImportFailure?
        if let workflow {
            await workflow.cancel()
            cleanupFailure = await workflow.takeCleanupFailure()
        }
        sheetDraft = nil
        sheetFailure = nil
        isImportSheetPresented = false
        phase = .idle
        if let cleanupFailure {
            alertFailure = cleanupFailure
        }
    }

    func handleImporterFailure(_ error: Error) {
        let cocoaError = error as? CocoaError
        guard cocoaError?.code != .userCancelled else { return }
        alertFailure = ImportFailure(
            title: "无法选择 IPA",
            reason: "文件选择失败",
            recovery: "重试",
            code: "SEAL-IPA-206"
        )
    }

    func performAlertRecovery(for failure: ImportFailure) {
        alertFailure = nil
        let recovery = failure.recovery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recovery != "知道了" else { return }
        if failure.code.hasPrefix("SEAL-IPA-") {
            presentImporter()
        } else if let route = settingsRoute(for: failure) {
            openSettings(route: route)
        }
    }

    func openSettings(route: SettingsRoute) {
        requestedSettingsRoute = route
        shouldOpenSettings = true
    }

    func requestSigning(for app: AppRecord) async {
        guard signingTask == nil, batchRefreshTask == nil else { return }
        await load(force: true)
        let availableAccounts = accounts.filter { AccountAvailabilityPolicy.isSelectable($0) }
        guard availableAccounts.isEmpty == false else {
            alertFailure = ImportFailure(
                title: "缺少签名账号",
                reason: accounts.isEmpty ? "尚未添加 Apple ID" : "Apple ID 需要重新验证",
                recovery: "前往设置",
                code: "SEAL-AUTH-104"
            )
            return
        }

        let boundAccountID = (app.state == .installed || app.isSeal) ? app.accountID : nil
        if (app.state == .installed || app.isSeal), boundAccountID == nil {
            alertFailure = ImportFailure(
                title: "续签记录不完整",
                reason: "未记录上次签名此 App 的 Apple ID。",
                recovery: "重新导入 IPA 签名并安装",
                code: "SEAL-AUTH-110"
            )
            return
        }

        guard await refreshSigningChannel() else {
            presentVPNRecovery(for: .signing(
                app,
                accountID: boundAccountID,
                requestedBundleIdentifier: nil,
                completionMode: .signAndInstall
            ))
            return
        }

        continueSigningRequest(for: app, availableAccounts: availableAccounts)
    }

    func beginSigning(
        for app: AppRecord,
        accountID: UUID,
        requestedBundleIdentifier: String? = nil,
        completionMode: SigningCompletionMode = .signAndInstall
    ) async {
        guard signingTask == nil, batchRefreshTask == nil else { return }
        await load(force: true)
        let isRenewal = app.state == .installed || app.isSeal
        let resolvedAccountID = isRenewal ? app.accountID : accountID
        guard let resolvedAccountID,
              let account = verifiedAccounts.first(where: { $0.id == resolvedAccountID }) else {
            alertFailure = ImportFailure(
                title: "Apple ID 不可用",
                reason: isRenewal ? "上次签名此 App 的 Apple ID 不可用。" : "请选择一个已验证的 Apple ID",
                recovery: "前往设置",
                code: "SEAL-AUTH-104"
            )
            return
        }
        guard await refreshSigningChannel() else {
            presentVPNRecovery(for: .signing(
                app,
                accountID: resolvedAccountID,
                requestedBundleIdentifier: isRenewal ? nil : requestedBundleIdentifier,
                completionMode: completionMode
            ))
            return
        }
        if isRenewal == false {
            await selectActiveAccount(id: account.id)
        }
        startSigning(
            app: app,
            account: account,
            requestedBundleIdentifier: isRenewal ? nil : requestedBundleIdentifier,
            completionMode: completionMode
        )
    }

    private func continueSigningRequest(
        for app: AppRecord,
        availableAccounts: [AppleAccountRecord]
    ) {
        if app.state == .installed || app.isSeal {
            guard let accountID = app.accountID,
                  let account = availableAccounts.first(where: { $0.id == accountID }) else {
                alertFailure = ImportFailure(
                    title: "Apple ID 不可用",
                    reason: "上次签名此 App 的 Apple ID 不可用。",
                    recovery: "前往设置",
                    code: "SEAL-AUTH-104"
                )
                return
            }
            startSigning(app: app, account: account)
        } else if let activeAccountID,
                  let account = availableAccounts.first(where: { $0.id == activeAccountID }) {
            startSigning(app: app, account: account)
        } else if availableAccounts.count == 1, let account = availableAccounts.first {
            startSigning(app: app, account: account)
        } else {
            accountSelectionApp = app
        }
    }

    func resumePendingVPNAction() async {
        guard let action = pendingVPNAction else {
            _ = await refreshSigningChannel()
            return
        }
        alertFailure = nil
        guard await refreshSigningChannel() else {
            presentVPNRecovery(for: action)
            return
        }
        pendingVPNAction = nil
        switch action {
        case .signing(
            let app,
            let accountID,
            let requestedBundleIdentifier,
            let completionMode
        ):
            if let accountID {
                await beginSigning(
                    for: app,
                    accountID: accountID,
                    requestedBundleIdentifier: requestedBundleIdentifier,
                    completionMode: completionMode
                )
            } else {
                await requestSigning(for: app)
            }
        case .batch(
            let resume,
            let dueLeadHours,
            let dueCutoff,
            let enforceCooldown,
            let dailyAutoRenewDayKey
        ):
            startBatchRefresh(
                resume: resume,
                dueLeadHours: dueLeadHours,
                dueCutoff: dueCutoff,
                enforceCooldown: enforceCooldown,
                dailyAutoRenewDayKey: dailyAutoRenewDayKey
            )
        }
    }

    func cancelPendingVPNRecovery() {
        pendingVPNAction = nil
        alertFailure = nil
    }

    func selectAccount(_ account: AppleAccountRecord, for app: AppRecord) {
        accountSelectionApp = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard Task.isCancelled == false else { return }
            await self?.selectActiveAccount(id: account.id)
            self?.startSigning(app: app, account: account)
        }
    }

    func chooseAnotherAccount(for app: AppRecord) async {
        await load(force: true)
        guard accounts.contains(where: { AccountAvailabilityPolicy.isSelectable($0) }) else {
            alertFailure = ImportFailure(
                title: "缺少签名账号",
                reason: accounts.isEmpty ? "尚未添加 Apple ID" : "Apple ID 需要重新验证",
                recovery: "前往设置",
                code: "SEAL-AUTH-104"
            )
            return
        }
        accountSelectionApp = app
    }

    func retrySigning() {
        guard let session = signingSession else { return }
        restartSigning(
            session,
            allowDroppingExtensions: session.allowsDroppingExtensions
        )
    }

    func retryWithoutExtensions() {
        guard let session = signingSession else { return }
        restartSigning(
            session,
            allowDroppingExtensions: true
        )
    }


    func cancelSigning() {
        signingTask?.cancel()
        signingSession = nil
        selectedOperationApp = nil
    }

    func dismissSigningResult() {
        guard let signingSession else { return }
        if case .running = signingSession.status { return }
        self.signingSession = nil
        selectedOperationApp = nil
    }

    @discardableResult
    func updatePreferredBundleIdentifier(for app: AppRecord, value: String) async -> Bool {
        guard let appStore, BundleIDPolicy.isEditable(app) else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationError = BundleIDPolicy.validationError(for: trimmed) {
            alertFailure = ImportFailure(
                title: "Bundle ID 无效",
                reason: validationError,
                recovery: "修改 Bundle ID",
                code: "SEAL-BUNDLE-001"
            )
            return false
        }
        do {
            var updated = app
            updated.preferredBundleIdentifier = trimmed
            try await appStore.save(updated)
            await load(force: true)
            return true
        } catch {
            alertFailure = ImportFailure(
                title: "无法保存 Bundle ID",
                reason: "本地草稿保存失败。",
                recovery: "重试",
                code: "SEAL-BUNDLE-003"
            )
            return false
        }
    }

    @discardableResult
    func updatePreferredDisplayName(for app: AppRecord, name: String) async -> Bool {
        guard let appStore, app.state != .installed, app.hasSignedArtifact == false else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            alertFailure = ImportFailure(
                title: "App 名称无效",
                reason: "App 名称不能为空。",
                recovery: "修改 App 名称",
                code: "SEAL-CUSTOM-001"
            )
            return false
        }
        do {
            var updated = app
            updated.preferredDisplayName = trimmed == app.name ? nil : trimmed
            try await appStore.save(updated)
            await load(force: true)
            return true
        } catch {
            alertFailure = ImportFailure(
                title: "无法保存 App 名称",
                reason: "本地记录保存失败。",
                recovery: "重试",
                code: "SEAL-CUSTOM-002"
            )
            return false
        }
    }

    @discardableResult
    func updatePreferredIcon(for app: AppRecord, data: Data?) async -> Bool {
        guard let appStore, let fileStore, app.state != .installed, app.hasSignedArtifact == false else { return false }
        do {
            var updated = app
            if let data {
                updated.preferredIconRelativePath = try await fileStore.storePreferredIcon(data: data, appID: app.id)
            } else {
                try await fileStore.removePreferredIcon(appID: app.id)
                updated.preferredIconRelativePath = nil
            }
            try await appStore.save(updated)
            if let path = updated.displayIconRelativePath,
               let data = try? await fileStore.read(relativePath: path) {
                iconData[updated.id] = data
            } else {
                iconData[updated.id] = nil
            }
            await load(force: true)
            return true
        } catch {
            alertFailure = ImportFailure(
                title: "无法保存 App 图标",
                reason: "图标文件无法写入本机存储。",
                recovery: "重试",
                code: "SEAL-CUSTOM-003"
            )
            return false
        }
    }

    func retryInstallationForCurrentSigningSession() async {
        guard let session = signingSession else { return }
        await load(force: true)
        guard let signedApp = apps.first(where: { $0.id == session.app.id && $0.hasSignedArtifact }) else {
            alertFailure = ImportFailure(
                title: "无法重新安装",
                reason: "本机没有可用的已签名 IPA。",
                recovery: "重新签名",
                code: "SEAL-INSTALL-715"
            )
            return
        }
        let succeeded = await installSignedArtifact(signedApp)
        guard succeeded, let installed = apps.first(where: { $0.id == signedApp.id }) else { return }
        var updatedSession = session
        updatedSession.status = .succeeded(installed)
        signingSession = updatedSession
    }

    func installSignedArtifact(_ app: AppRecord) async -> Bool {
        guard signingTask == nil, batchRefreshTask == nil, installingSignedAppID == nil,
              let signingCoordinator else { return false }
        guard let operationLease = acquireOperation(.installing, appID: app.id) else { return false }
        defer { releaseOperation(operationLease) }
        installingSignedAppID = app.id
        defer { installingSignedAppID = nil }
        do {
            let installed = try await signingCoordinator.installSignedArtifact(
                appID: app.id,
                progress: { _ in }
            )
            try? await logStore?.append(
                category: .signing,
                message: "已使用本机保存的已签名 IPA 重新安装：\(installed.displayName)"
            )
            await cleanTemporaryFilesIfNeeded(appID: app.id)
            await load(force: true)
            return true
        } catch let failure as ImportFailure {
            alertFailure = failure
            try? await logStore?.append(
                category: .signing,
                level: .error,
                message: "已签名 IPA 安装失败：\(failure.reason)",
                code: failure.code
            )
        } catch {
            alertFailure = Self.unexpectedSigningFailure(error)
        }
        await load(force: true)
        return false
    }

    func exportSignedIPAURL(for app: AppRecord) async -> URL? {
        guard let fileStore,
              let path = app.signedIPARelativePath,
              let expectedSHA256 = app.signedIPASHA256 else {
            alertFailure = ImportFailure(
                title: "无法导出",
                reason: "已签名 IPA 记录不完整。",
                recovery: "重新签名",
                code: "SEAL-EXPORT-001"
            )
            return nil
        }
        do {
            guard try await fileStore.validateSHA256(relativePath: path, expected: expectedSHA256) else {
                throw ImportFailure(
                    title: "无法导出",
                    reason: "已签名 IPA 的 SHA-256 校验不一致。",
                    recovery: "重新签名",
                    code: "SEAL-EXPORT-002"
                )
            }
            return try await fileStore.makeSignedIPAExportCopy(
                relativePath: path,
                fileName: Self.exportFileName(for: app),
                appID: app.id
            )
        } catch let failure as ImportFailure {
            alertFailure = failure
        } catch {
            alertFailure = ImportFailure(
                title: "无法导出",
                reason: "本机无法读取已签名 IPA。",
                recovery: "重试",
                code: "SEAL-EXPORT-003"
            )
        }
        return nil
    }

    func deleteSignedArtifact(_ app: AppRecord) async -> Bool {
        guard let fileStore, let appStore else { return false }
        guard let operationLease = acquireOperation(.maintainingStorage, appID: app.id) else { return false }
        defer { releaseOperation(operationLease) }
        do {
            try await fileStore.removeSignedIPA(appID: app.id)
            var updated = app
            updated.signedIPARelativePath = nil
            updated.signedIPASHA256 = nil
            updated.signedArtifactStatus = nil
            updated.lastInstallFailureCode = nil
            updated.lastInstallFailureReason = nil
            if updated.state != .installed {
                updated.state = .imported
                // Keep the historical Apple ID / Team / Serial and extension handling
                // preference. Deleting a Signed.ipa removes the artifact, not the user's
                // signing identity or successful customization memory.
                updated.signedDeviceIdentifier = nil
                updated.provisioningProfileUUID = nil
                updated.provisioningProfileName = nil
                updated.provisioningProfileCreationDate = nil
                updated.provisioningProfileExpirationDate = nil
                updated.signingTargets = []
                if let mapped = updated.mappedBundleIdentifier {
                    updated.preferredBundleIdentifier = mapped
                }
                updated.mappedBundleIdentifier = nil
            }
            try await appStore.save(updated)
            await load(force: true)
            return true
        } catch {
            alertFailure = ImportFailure(
                title: "无法删除已签名 IPA",
                reason: "本机签名文件没有被删除。",
                recovery: "重试",
                code: "SEAL-STORAGE-004"
            )
            return false
        }
    }

    func delete(_ app: AppRecord) async -> Bool {
        guard let appStore, let fileStore else { return false }
        guard let operationLease = acquireOperation(.maintainingStorage, appID: app.id) else { return false }
        defer { releaseOperation(operationLease) }
        do {
            try await appStore.delete(id: app.id)
            do {
                try await fileStore.removeApp(appID: app.id)
            } catch {
                do {
                    try await appStore.save(app)
                } catch {
                    alertFailure = ImportFailure(
                        title: "应用删除未完整回滚",
                        reason: "本地文件删除失败，并且应用数据库记录未能恢复。",
                        recovery: "重新打开 Seal 让启动恢复检查本地文件",
                        code: "SEAL-APP-ROLLBACK-001"
                    )
                    await load(force: true)
                    return false
                }
                throw error
            }

            var historyFailure: ImportFailure?
            if let signingHistoryStore {
                do {
                    try await signingHistoryStore.markDeleted(appID: app.id)
                } catch {
                    historyFailure = ImportFailure(
                        title: "应用已删除",
                        reason: "应用和本地文件已删除，但签名历史状态未能同步。",
                        recovery: "稍后重新打开 Seal 检查日志",
                        code: "SEAL-HISTORY-003"
                    )
                }
            }
            await load(force: true)
            if let historyFailure {
                alertFailure = historyFailure
            }
            return true
        } catch {
            alertFailure = ImportFailure(
                title: "无法移除应用",
                reason: "本地文件删除失败",
                recovery: "重试",
                code: "SEAL-APP-003"
            )
            return false
        }
    }

    func refreshAll() {
        startBatchRefresh(resume: false)
    }

    func refreshDueApps(leadHours: Int, enforceCooldown: Bool = false) {
        startBatchRefresh(
            resume: false,
            dueLeadHours: leadHours,
            enforceCooldown: enforceCooldown
        )
    }

    func hasCycleRenewalCompanions(for seal: AppRecord) -> Bool {
        guard seal.isSeal, let cutoff = seal.expiryDate else { return false }
        return apps.contains { app in
            guard app.isSeal == false,
                  app.state == .installed,
                  app.accountID != nil,
                  let expiryDate = app.expiryDate else { return false }
            return expiryDate <= cutoff
        }
    }

    func refreshSealCycle(for seal: AppRecord) {
        guard seal.isSeal, let cutoff = seal.expiryDate else { return }
        startBatchRefresh(
            resume: false,
            dueCutoff: cutoff
        )
    }

    func resumeRefresh() {
        startBatchRefresh(resume: true)
    }

    func cancelBatchRefresh() {
        batchRefreshTask?.cancel()
        batchRefreshSession = nil
        autoRenewInProgress = false
        currentAutoRenewDayKey = nil
        Task { await load(force: true) }
    }

    func dismissBatchRefresh() {
        guard let batchRefreshSession else { return }
        if case .running = batchRefreshSession.status { return }
        self.batchRefreshSession = nil
    }

    private func startBatchRefresh(
        resume: Bool,
        dueLeadHours: Int? = nil,
        dueCutoff: Date? = nil,
        enforceCooldown: Bool = false,
        dailyAutoRenewDayKey: String? = nil
    ) {
        guard batchRefreshTask == nil,
              signingTask == nil,
              renewalCoordinator != nil else { return }
        batchRefreshTask = Task { [weak self] in
            guard let self else { return }
            guard await self.refreshSigningChannel() else {
                self.batchRefreshTask = nil
                self.autoRenewInProgress = false
                self.currentAutoRenewDayKey = nil
                self.presentVPNRecovery(
                    for: .batch(
                        resume: resume,
                        dueLeadHours: dueLeadHours,
                        dueCutoff: dueCutoff,
                        enforceCooldown: enforceCooldown,
                        dailyAutoRenewDayKey: dailyAutoRenewDayKey
                    )
                )
                return
            }
            self.currentAutoRenewDayKey = dailyAutoRenewDayKey
            self.autoRenewInProgress = dailyAutoRenewDayKey != nil
            self.batchRefreshSession = BatchRefreshSession()
            await self.runBatchRefresh(
                resume: resume,
                dueLeadHours: dueLeadHours,
                dueCutoff: dueCutoff,
                enforceCooldown: enforceCooldown,
                dailyAutoRenewDayKey: dailyAutoRenewDayKey
            )
        }
    }

    private func presentVPNRecovery(for action: PendingVPNAction) {
        pendingVPNAction = action
        alertFailure = ImportFailure(
            title: "安装通道未就绪",
            reason: "安装通道不可用。",
            recovery: "知道了",
            code: "SEAL-INSTALL-706"
        )
    }

    private func runBatchRefresh(
        resume: Bool,
        dueLeadHours: Int? = nil,
        dueCutoff: Date? = nil,
        enforceCooldown: Bool = false,
        dailyAutoRenewDayKey: String? = nil
    ) async {
        guard let renewalCoordinator else { return }
        guard let operationLease = acquireOperation(.renewing) else {
            batchRefreshSession = nil
            autoRenewInProgress = false
            currentAutoRenewDayKey = nil
            batchRefreshTask = nil
            return
        }
        defer { releaseOperation(operationLease) }
        do {
            let progress: @Sendable (BatchRefreshEvent) async -> Void = { [weak self] event in
                await self?.consumeBatchEvent(event)
            }
            let result = if let dueCutoff {
                try await renewalCoordinator.refreshDue(
                    until: dueCutoff,
                    enforceCooldown: enforceCooldown,
                    progress: progress
                )
            } else if let dueLeadHours {
                try await renewalCoordinator.refreshDue(
                    leadHours: dueLeadHours,
                    enforceCooldown: enforceCooldown,
                    progress: progress
                )
            } else if resume {
                try await renewalCoordinator.resume(progress: progress)
            } else {
                try await renewalCoordinator.refreshAll(progress: progress)
            }
            if result.total == 0 {
                if let dailyAutoRenewDayKey {
                    dailyAutoRenewStateStore.markCompleted(dayKey: dailyAutoRenewDayKey)
                }
                batchRefreshSession = nil
                if dueLeadHours == nil, dueCutoff == nil, dailyAutoRenewDayKey == nil {
                    alertFailure = ImportFailure(
                        title: "没有可刷新的应用",
                        reason: "已安装应用尚未绑定账号",
                        recovery: "知道了",
                        code: "SEAL-RENEW-001"
                    )
                } else if enforceCooldown == false {
                    alertFailure = ImportFailure(
                        title: "暂无临期应用",
                        reason: "没有应用进入当前提醒窗口，或应用尚未绑定签名账号",
                        recovery: "知道了",
                        code: "SEAL-RENEW-002"
                    )
                }
            } else {
                batchRefreshSession?.status = .completed(result)
                if let dailyAutoRenewDayKey, result.failed == 0 {
                    dailyAutoRenewStateStore.markCompleted(dayKey: dailyAutoRenewDayKey)
                }
                try? await logStore?.append(
                    category: .renewal,
                    level: result.failed == 0 ? .info : .warning,
                    message: dailyAutoRenewDayKey != nil
                        ? "每日首次打开自动续签完成"
                        : (dueLeadHours == nil ? "批量续签完成" : "临期应用续签完成")
                )
                await cleanTemporaryFilesIfNeeded()
            }
            await load(force: true)
        } catch is CancellationError {
            batchRefreshSession = nil
            await load(force: true)
        } catch let failure as ImportFailure {
            batchRefreshSession?.status = .failed(failure)
        } catch {
            batchRefreshSession?.status = .failed(
                ImportFailure(
                    title: "无法刷新应用",
                    reason: "刷新队列执行失败",
                    recovery: "重试",
                    code: "SEAL-RENEW-500"
                )
            )
        }
        batchRefreshTask = nil
        autoRenewInProgress = false
        currentAutoRenewDayKey = nil
    }

    private func consumeBatchEvent(_ event: BatchRefreshEvent) {
        guard batchRefreshSession != nil else { return }
        switch event {
        case .started(let total):
            batchRefreshSession?.total = total
        case .appProgress(let index, let total, let app, let stage):
            batchRefreshSession?.currentIndex = index
            batchRefreshSession?.total = total
            batchRefreshSession?.currentAppName = app.name
            batchRefreshSession?.currentStage = stage
            if app.isSeal,
               stage == .installing,
               batchRefreshSession?.failed == 0,
               let currentAutoRenewDayKey {
                dailyAutoRenewStateStore.markPendingSelfRenewal(
                    dayKey: currentAutoRenewDayKey,
                    previousExpiry: SelfAppMetadata.current()?.expirationDate
                )
            }
        case .appSucceeded(let index, let total, let app):
            batchRefreshSession?.currentIndex = index
            batchRefreshSession?.total = total
            batchRefreshSession?.currentAppName = app.name
            batchRefreshSession?.succeeded += 1
            Task { [weak self] in
                await self?.recordSigningHistory(
                    app: app,
                    action: .renew,
                    result: .success,
                    attemptedBundleIdentifier: app.preferredBundleIdentifier ?? app.mappedBundleIdentifier,
                    finalSignedBundleIdentifier: app.mappedBundleIdentifier,
                    lifecycleStatus: .active
                )
            }
        case .appFailed(let index, let total, let app, let failure):
            batchRefreshSession?.currentIndex = index
            batchRefreshSession?.total = total
            batchRefreshSession?.currentAppName = app.name
            batchRefreshSession?.failed += 1
            Task { [weak self] in
                await self?.recordSigningHistory(
                    app: app,
                    action: .renew,
                    result: .failed,
                    attemptedBundleIdentifier: app.preferredBundleIdentifier ?? app.mappedBundleIdentifier,
                    lifecycleStatus: app.state == .installed ? .active : .unknown,
                    failure: failure
                )
            }
        }
    }

    private func startSigning(
        app: AppRecord,
        account: AppleAccountRecord,
        requestedBundleIdentifier: String? = nil,
        completionMode: SigningCompletionMode = .signAndInstall,
        allowDroppingExtensions: Bool = false
    ) {
        guard signingTask == nil,
              batchRefreshTask == nil,
              signingCoordinator != nil else { return }
        let selectedCertificateSerialNumber = try? SigningCertificateSelectionPolicy
            .resolvedSerialNumber(for: app, account: account)
        let resolvedAllowDroppingExtensions = allowDroppingExtensions
            || app.removedExtensionBundleIdentifiers.isEmpty == false
        signingSession = SigningSession(
            app: app,
            account: account,
            requestedBundleIdentifier: requestedBundleIdentifier,
            selectedCertificateSerialNumber: selectedCertificateSerialNumber,
            completionMode: completionMode,
            allowsDroppingExtensions: resolvedAllowDroppingExtensions,
            status: .running(.waitingForChannel)
        )
        let targetBundleIdentifier = (try? BundleIDPolicy.targetBundleIdentifier(
            for: app,
            requestedBundleIdentifier: requestedBundleIdentifier
        )) ?? app.mappedBundleIdentifier ?? app.originalBundleIdentifier
        Task { [weak self] in
            try? await self?.logStore?.append(
                category: .signing,
                message: "准备签名：\(app.name)，Apple ID：\(account.maskedEmail)，Team：\(account.teamID)，证书：\(selectedCertificateSerialNumber ?? "签名时申请")，Bundle ID：\(targetBundleIdentifier)"
            )
        }
        signingTask = Task { [weak self] in
            await self?.runSigning(
                app: app,
                account: account,
                requestedBundleIdentifier: requestedBundleIdentifier,
                selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                completionMode: completionMode,
                allowDroppingExtensions: resolvedAllowDroppingExtensions
            )
        }
    }

    private func restartSigning(
        _ session: SigningSession,
        allowDroppingExtensions: Bool
    ) {
        guard signingTask == nil,
              batchRefreshTask == nil,
              signingCoordinator != nil else { return }
        signingSession?.allowsDroppingExtensions = allowDroppingExtensions
        signingSession?.status = .running(.waitingForChannel)
        signingTask = Task { [weak self] in
            await self?.runSigning(
                app: session.app,
                account: session.account,
                requestedBundleIdentifier: session.requestedBundleIdentifier,
                selectedCertificateSerialNumber: session.selectedCertificateSerialNumber,
                completionMode: session.completionMode,
                allowDroppingExtensions: allowDroppingExtensions
            )
        }
    }

    private func runSigning(
        app: AppRecord,
        account: AppleAccountRecord,
        requestedBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String?,
        completionMode: SigningCompletionMode,
        allowDroppingExtensions: Bool
    ) async {
        guard let signingCoordinator else { return }
        let operationKind: OperationCoordinator.Kind = (app.state == .installed || app.isSeal) ? .renewing : .signing
        guard let operationLease = acquireOperation(operationKind, appID: app.id) else {
            signingTask = nil
            return
        }
        defer { releaseOperation(operationLease) }
        let attemptedBundleIdentifier = try? BundleIDPolicy.targetBundleIdentifier(
            for: app,
            requestedBundleIdentifier: requestedBundleIdentifier
        )
        do {
            let completed: AppRecord
            switch completionMode {
            case .signAndInstall:
                completed = try await signingCoordinator.signAndInstall(
                    appID: app.id,
                    accountID: account.id,
                    requestedBundleIdentifier: requestedBundleIdentifier,
                    selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                    allowDroppingExtensions: allowDroppingExtensions,
                    progress: { [weak self] stage in
                        await self?.updateSigningStage(stage)
                    }
                )
            case .signOnly:
                completed = try await signingCoordinator.signOnly(
                    appID: app.id,
                    accountID: account.id,
                    requestedBundleIdentifier: requestedBundleIdentifier,
                    selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                    allowDroppingExtensions: allowDroppingExtensions,
                    progress: { [weak self] stage in
                        await self?.updateSigningStage(stage)
                    }
                )
            }
            let action: SigningHistoryRecord.Action = app.state == .installed ? .renew : .sign
            signingSession?.status = .succeeded(completed)
            try? await logStore?.append(
                category: .signing,
                message: completionMode == .signOnly
                    ? "应用签名完成，已保存正式已签名 IPA"
                    : (app.state == .installed ? "应用续签与安装完成" : "应用签名与安装完成")
            )
            await recordSigningHistory(
                app: completed,
                account: account,
                action: action,
                result: .success,
                attemptedBundleIdentifier: attemptedBundleIdentifier,
                finalSignedBundleIdentifier: completed.mappedBundleIdentifier,
                lifecycleStatus: completed.state == .installed ? .active : .unknown
            )
            await cleanTemporaryFilesIfNeeded(appID: completed.id)
            await load(force: true)
        } catch is CancellationError {
            signingSession = nil
        } catch let failure as ImportFailure {
            signingSession?.status = .failed(failure)
            try? await logStore?.append(
                category: .signing,
                level: .error,
                message: "\(failure.title)：\(failure.reason)",
                code: failure.code
            )
            let latestApp = await latestStoredApp(for: app)
            await recordSigningHistory(
                app: latestApp,
                account: account,
                action: app.state == .installed ? .renew : .sign,
                result: .failed,
                attemptedBundleIdentifier: attemptedBundleIdentifier,
                lifecycleStatus: app.state == .installed ? .active : .unknown,
                failure: failure
            )
            await load(force: true)
        } catch {
            let failure = Self.unexpectedSigningFailure(error)
            signingSession?.status = .failed(failure)
            try? await logStore?.append(
                category: .signing,
                level: .error,
                message: failure.reason,
                code: failure.code
            )
            let latestApp = await latestStoredApp(for: app)
            await recordSigningHistory(
                app: latestApp,
                account: account,
                action: app.state == .installed ? .renew : .sign,
                result: .failed,
                attemptedBundleIdentifier: attemptedBundleIdentifier,
                lifecycleStatus: app.state == .installed ? .active : .unknown,
                failure: failure
            )
            await load(force: true)
        }
        signingTask = nil
    }

    private func latestStoredApp(for fallback: AppRecord) async -> AppRecord {
        guard let appStore,
              let stored = try? await appStore.fetchAll().first(where: {
                  $0.id == fallback.id
              }) else {
            return fallback
        }
        return stored
    }

    private func updateSigningStage(_ stage: SigningStage) {
        guard signingSession != nil else { return }
        signingSession?.status = .running(stage)
    }

    private func recordSigningHistory(
        app: AppRecord,
        account explicitAccount: AppleAccountRecord? = nil,
        action: SigningHistoryRecord.Action,
        result: SigningHistoryRecord.Result,
        attemptedBundleIdentifier: String? = nil,
        finalSignedBundleIdentifier: String? = nil,
        lifecycleStatus: SigningHistoryRecord.LifecycleStatus? = nil,
        failure: ImportFailure? = nil
    ) async {
        guard let signingHistoryStore else { return }
        let account = await resolvedHistoryAccount(for: app, explicitAccount: explicitAccount)
        guard let account else { return }
        let record = SigningHistoryRecord(
            app: app,
            account: account,
            action: action,
            result: result,
            attemptedBundleIdentifier: attemptedBundleIdentifier,
            finalSignedBundleIdentifier: finalSignedBundleIdentifier,
            lifecycleStatus: lifecycleStatus,
            errorCode: failure?.code,
            errorReason: failure?.reason
        )
        do {
            try await signingHistoryStore.append(record)
        } catch {
            surfaceHistoryWarning(
                title: "签名历史未保存",
                reason: "签名结果已经完成，但历史记录无法写入。",
                code: "SEAL-HISTORY-005"
            )
        }
    }

    private func resolvedHistoryAccount(
        for app: AppRecord,
        explicitAccount: AppleAccountRecord?
    ) async -> AppleAccountRecord? {
        if let explicitAccount { return explicitAccount }
        guard let accountID = app.accountID else { return nil }
        if let account = accounts.first(where: { $0.id == accountID }) {
            return account
        }
        guard let accountRepository else { return nil }
        do {
            let fetchedAccounts = try await accountRepository.fetchAll()
            return fetchedAccounts.first { $0.id == accountID }
        } catch {
            surfaceHistoryWarning(
                title: "签名历史账号读取失败",
                reason: "无法读取历史记录关联的 Apple ID。",
                code: "SEAL-HISTORY-006"
            )
            return nil
        }
    }

    private func surfaceHistoryWarning(
        title: String,
        reason: String,
        code: String
    ) {
        guard alertFailure == nil else { return }
        alertFailure = ImportFailure(
            title: title,
            reason: reason,
            recovery: "检查本地存储空间后重试",
            code: code
        )
    }

    private func cleanTemporaryFilesIfNeeded(appID: UUID? = nil) async {
        guard UserDefaults.standard.bool(forKey: "behavior.deleteIPAAfterInstall"),
              let fileStore else { return }
        do {
            try await fileStore.clearTemporaryFiles()
            try? await logStore?.append(
                category: .system,
                message: appID == nil ? "安装完成后已清理临时签名工作区" : "安装完成后已清理当前应用临时签名工作区"
            )
        } catch {
            try? await logStore?.append(
                category: .system,
                level: .warning,
                message: "安装完成后清理签名缓存失败",
                code: "SEAL-STORAGE-001"
            )
        }
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

    private func settingsRoute(for failure: ImportFailure) -> SettingsRoute? {
        if failure.code.hasPrefix("SEAL-AUTH-") { return .account }
        if failure.code.hasPrefix("SEAL-CERT-") || failure.code.contains("CERT") { return .certificates }
        if failure.code.hasPrefix("SEAL-PAIR-") || failure.code == "SEAL-INSTALL-703" { return .pairing }
        if failure.code.hasPrefix("SEAL-INSTALL-") { return .localDevVPN }
        if failure.code.hasPrefix("SEAL-RENEW-") { return .logs }
        return nil
    }

    private static func unexpectedSigningFailure(_ error: Error) -> ImportFailure {
        return ImportFailure(
            title: "签名失败",
            reason: "签名流程遇到未预期错误。技术信息已隐藏，可在日志中心查看脱敏诊断。",
            recovery: "重试",
            code: "SEAL-SIGN-500"
        )
    }

    private func consumeWorkflowState() async {
        guard let workflow else { return }
        let workflowState = await workflow.state
        switch workflowState {
        case .idle:
            phase = .idle
        case .preparing:
            phase = .preparing
        case .awaitingConfirmation(let draft):
            sheetDraft = draft
            sheetFailure = nil
            isImportSheetPresented = false
            phase = .committing
            await workflow.confirm(preferredDraft: draft)
            await consumeWorkflowState()
        case .committing(let draft):
            phase = .committing
            sheetDraft = draft
            isImportSheetPresented = true
        case .completed:
            phase = .idle
            sheetDraft = nil
            sheetFailure = nil
            isImportSheetPresented = false
            await load(force: true)
            importCompletionCount += 1
            if let cleanupFailure = await workflow.takeCleanupFailure() {
                alertFailure = cleanupFailure
            }
        case .failed(let failure):
            phase = .idle
            if sheetDraft == nil {
                alertFailure = failure
            } else {
                sheetFailure = failure
                isImportSheetPresented = true
            }
        }
    }

    private static func exportFileName(for app: AppRecord) -> String {
        let raw = "\(app.displayName)-\(app.version)-Seal.ipa"
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return raw.components(separatedBy: invalid).joined(separator: "-")
    }

    static func uiTestModel(arguments: [String]) -> AppsViewModel? {
        if arguments.contains("--ui-testing-empty") {
            return AppsViewModel(apps: [], draft: nil)
        }

        let appID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let record = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 1_234_567,
            state: .preflightPassed,
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        if arguments.contains("--ui-testing-imported") {
            return AppsViewModel(apps: [record], draft: nil)
        }
        if arguments.contains("--ui-testing-confirmation") {
            let draft = ImportDraft(
                appID: appID,
                parsedIPA: ParsedIPA(
                    name: "Demo",
                    bundleIdentifier: "com.example.demo",
                    version: "1.0",
                    buildNumber: "1",
                    fileSize: 1_234_567,
                    iconData: nil,
                    extensions: [
                        AppExtensionRecord(
                            name: "Share",
                            originalBundleIdentifier: "com.example.demo.share",
                            kind: .share
                        )
                    ],
                    entitlementKeys: []
                ),
                stagedIPA: StagedIPA(
                    id: appID,
                    url: FileManager.default.temporaryDirectory.appending(path: "Demo.ipa")
                )
            )
            return AppsViewModel(apps: [], draft: draft)
        }
        return nil
    }

    private static let dataFailure = ImportFailure(
        title: "无法读取应用",
        reason: "本地数据读取失败",
        recovery: "重试",
        code: "SEAL-APP-002"
    )
}

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
    @Published private(set) var pendingRefreshCount = 0
    @Published var shouldOpenSettings = false
    @Published var requestedSettingsRoute: SettingsRoute?
    @Published private(set) var signingChannelStatus: SigningChannelStatus = .idle

    private let workflow: ImportWorkflow?
    private let appStore: (any AppStore)?
    private let fileStore: AppFileStore?
    private let accountRepository: (any AccountRepository)?
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
    private var signingTask: Task<Void, Never>?
    private var batchRefreshTask: Task<Void, Never>?
    private var channelTask: Task<Bool, Never>?
    private var pendingVPNAction: PendingVPNAction?
    private var hasLoaded = false

    private enum PendingVPNAction {
        case signing(AppRecord, accountID: UUID?)
        case batch(resume: Bool, dueLeadHours: Int?, enforceCooldown: Bool)
    }

    init(
        workflow: ImportWorkflow,
        appStore: any AppStore,
        fileStore: AppFileStore,
        accountRepository: any AccountRepository,
        signingCoordinator: SigningCoordinator,
        installChannel: any InstallChannel,
        renewalCoordinator: RenewalCoordinator,
        appRecordRecovery: AppRecordRecovery,
        selfAppRegistrar: SelfAppRegistrar?,
        logStore: SealLogStore,
        signingHistoryStore: SigningHistoryStore,
        notificationScheduler: ExpiryNotificationScheduler,
        notificationPreferences: NotificationPreferences,
        signingPreferenceStore: SigningPreferenceStore
    ) {
        self.workflow = workflow
        self.appStore = appStore
        self.fileStore = fileStore
        self.accountRepository = accountRepository
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
            .filter { $0.state != .installed && $0.isSeal == false }
            .sorted { lhs, rhs in
                if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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

    var verifiedAccounts: [AppleAccountRecord] {
        accounts.filter { $0.status == .verified }
    }

    func selectActiveAccount(id: UUID) async {
        guard verifiedAccounts.contains(where: { $0.id == id }) else { return }
        activeAccountID = id
        await signingPreferenceStore?.setActiveAccountID(id)
    }

    func refreshActiveAccountSelection() async {
        guard let signingPreferenceStore else { return }
        let storedID = await signingPreferenceStore.activeAccountID()
        if let storedID,
           verifiedAccounts.contains(where: { $0.id == storedID }) {
            activeAccountID = storedID
        } else if activeAccountID == nil {
            activeAccountID = verifiedAccounts.first?.id
            await signingPreferenceStore.setActiveAccountID(activeAccountID)
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
        do {
            try? await selfAppRegistrar?.ensureRegistered()
            try? await appRecordRecovery?.restoreMissingRecords()
            let fetched = try await appStore.fetchAll()
            let fetchedAccounts = try await accountRepository?.fetchAll() ?? []
            var loadedIcons: [UUID: Data] = [:]
            if let fileStore {
                for app in fetched {
                    guard let path = app.iconRelativePath,
                          let data = try? await fileStore.read(relativePath: path) else {
                        continue
                    }
                    loadedIcons[app.id] = data
                }
            }
            await seedSigningHistoryIfNeeded(apps: fetched, accounts: fetchedAccounts)
            apps = fetched
            accounts = fetchedAccounts
            let preferredAccountID: UUID?
            if let signingPreferenceStore {
                preferredAccountID = await signingPreferenceStore.activeAccountID()
            } else {
                preferredAccountID = nil
            }
            let verifiedAccounts = fetchedAccounts.filter { $0.status == .verified }
            if let preferredAccountID,
               verifiedAccounts.contains(where: { $0.id == preferredAccountID }) {
                activeAccountID = preferredAccountID
            } else {
                activeAccountID = verifiedAccounts.first?.id
                await signingPreferenceStore?.setActiveAccountID(activeAccountID)
            }
            iconData = loadedIcons
            pendingRefreshCount = (try? await renewalCoordinator?.pendingCount()) ?? 0
            if let notificationScheduler, let notificationPreferences {
                try? await notificationScheduler.reschedule(
                    apps: fetched,
                    enabled: notificationPreferences.isEnabled,
                    leadHours: notificationPreferences.leadHours
                )
            }
            hasLoaded = true
        } catch {
            alertFailure = Self.dataFailure
        }
    }

    private func seedSigningHistoryIfNeeded(
        apps: [AppRecord],
        accounts: [AppleAccountRecord]
    ) async {
        guard let signingHistoryStore else { return }
        let existingRecords = (try? await signingHistoryStore.records()) ?? []
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
            try? await signingHistoryStore.append(record)
        }
    }

    func presentImporter() {
        guard phase == .idle else { return }
        isImporterPresented = true
    }

    func importSelectedFile(_ url: URL) async {
        guard let workflow, phase == .idle else { return }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        alertFailure = nil
        sheetFailure = nil
        phase = .preparing
        await workflow.prepare(sourceURL: url)
        await consumeWorkflowState()
    }

    func confirmImport() async {
        guard let workflow else { return }
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
        phase = .committing
        sheetFailure = nil
        await workflow.retry()
        await consumeWorkflowState()
    }

    func cancelImport() async {
        if let workflow {
            await workflow.cancel()
        }
        sheetDraft = nil
        sheetFailure = nil
        isImportSheetPresented = false
        phase = .idle
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
        let availableAccounts = accounts.filter { $0.status == .verified }
        guard availableAccounts.isEmpty == false else {
            alertFailure = ImportFailure(
                title: "缺少签名账号",
                reason: accounts.isEmpty ? "尚未添加 Apple ID" : "Apple ID 需要重新验证",
                recovery: "前往设置",
                code: "SEAL-AUTH-104"
            )
            return
        }

        guard await refreshSigningChannel() else {
            presentVPNRecovery(for: .signing(app, accountID: nil))
            return
        }

        continueSigningRequest(for: app, availableAccounts: availableAccounts)
    }

    func beginSigning(
        for app: AppRecord,
        accountID: UUID,
        requestedBundleIdentifier: String? = nil
    ) async {
        guard signingTask == nil, batchRefreshTask == nil else { return }
        await load(force: true)
        guard let account = verifiedAccounts.first(where: { $0.id == accountID }) else {
            alertFailure = ImportFailure(
                title: "Apple ID 不可用",
                reason: "请选择一个已验证的 Apple ID",
                recovery: "前往设置",
                code: "SEAL-AUTH-104"
            )
            return
        }
        guard await refreshSigningChannel() else {
            presentVPNRecovery(for: .signing(app, accountID: accountID))
            return
        }
        if app.requiresLockedSigningIdentity == false && app.isSeal == false {
            await selectActiveAccount(id: account.id)
        }
        startSigning(
            app: app,
            account: account,
            requestedBundleIdentifier: requestedBundleIdentifier
        )
    }

    private func continueSigningRequest(
        for app: AppRecord,
        availableAccounts: [AppleAccountRecord]
    ) {
        if let accountID = app.accountID,
           let account = availableAccounts.first(where: { $0.id == accountID }) {
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
        case .signing(let app, let accountID):
            if let accountID {
                await beginSigning(for: app, accountID: accountID)
            } else {
                await requestSigning(for: app)
            }
        case .batch(let resume, let dueLeadHours, let enforceCooldown):
            startBatchRefresh(
                resume: resume,
                dueLeadHours: dueLeadHours,
                enforceCooldown: enforceCooldown
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
            if app.requiresLockedSigningIdentity == false && app.isSeal == false {
                await self?.selectActiveAccount(id: account.id)
            }
            self?.startSigning(app: app, account: account)
        }
    }

    func chooseAnotherAccount(for app: AppRecord) async {
        await load(force: true)
        guard accounts.contains(where: { $0.status == .verified }) else {
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


    func confirmCertificateMigrationAndSign(
        app: AppRecord,
        accountID: UUID,
        requestedBundleIdentifier: String? = nil
    ) async {
        guard signingTask == nil,
              batchRefreshTask == nil,
              let appStore,
              let fileStore,
              let account = accounts.first(where: { $0.id == accountID }) else { return }

        do {
            guard app.accountID == account.id else {
                throw ImportFailure(
                    title: "证书迁移账号不匹配",
                    reason: "应用绑定的 Apple ID 与当前选择不一致。Seal 没有迁移账号。",
                    recovery: "选择首次签名使用的 Apple ID",
                    code: "SEAL-AUTH-111"
                )
            }
            if let originalTeamID = app.signingTeamID,
               originalTeamID.caseInsensitiveCompare(account.teamID) != .orderedSame {
                throw ImportFailure(
                    title: "证书迁移 Team 不匹配",
                    reason: "应用绑定 Team：\(originalTeamID)，当前 Team：\(account.teamID)。Seal 没有迁移 Team。",
                    recovery: "选择首次签名使用的 Apple ID / Team",
                    code: "SEAL-AUTH-112"
                )
            }
            guard let newSerial = account.selectedCertificateSerialNumber
                    ?? account.certificateSerialNumber,
                  account.certificateSerialNumber?.caseInsensitiveCompare(newSerial) == .orderedSame else {
                throw ImportFailure(
                    title: "没有本机可用证书",
                    reason: "请先在签名证书页面创建或选择包含本机私钥的证书。",
                    recovery: "前往签名证书",
                    code: "SEAL-CERT-206"
                )
            }
            guard let oldSerial = app.certificateSerialNumber,
                  oldSerial.caseInsensitiveCompare(newSerial) != .orderedSame else {
                throw ImportFailure(
                    title: "无需迁移证书",
                    reason: "应用已经绑定当前本机证书 Serial：\(newSerial)。",
                    recovery: "直接重试",
                    code: "SEAL-CERT-213"
                )
            }

            var current = try await appStore.fetchAll().first(where: { $0.id == app.id }) ?? app
            current.certificateSerialNumber = newSerial
            current.provisioningProfileUUID = nil
            current.provisioningProfileName = nil
            current.provisioningProfileCreationDate = nil
            current.provisioningProfileExpirationDate = nil
            current.entitlementValidationStatus = nil
            current.capabilityValidationStatus = nil
            current.signingTargets = []
            current.signedIPARelativePath = nil
            current.lastSignedAt = nil
            for index in current.extensions.indices {
                current.extensions[index].certificateSerialNumber = nil
                current.extensions[index].provisioningProfileUUID = nil
                current.extensions[index].provisioningProfileName = nil
                current.extensions[index].provisioningProfileExpirationDate = nil
            }
            try await appStore.save(current)
            try? await fileStore.removeSignedIPA(appID: current.id)
            try? await logStore?.append(
                category: .signing,
                message: "用户明确确认应用证书迁移。原 Serial：\(oldSerial)，新 Serial：\(newSerial)，Team：\(account.teamID)，Bundle ID：\(current.mappedBundleIdentifier ?? current.originalBundleIdentifier)"
            )
            await load(force: true)
            startSigning(
                app: current,
                account: account,
                requestedBundleIdentifier: requestedBundleIdentifier
            )
        } catch let failure as ImportFailure {
            alertFailure = failure
        } catch {
            let nsError = error as NSError
            alertFailure = ImportFailure(
                title: "无法迁移证书",
                reason: "本地签名记录更新失败。[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)",
                recovery: "重试",
                code: "SEAL-CERT-214"
            )
        }
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

    func delete(_ app: AppRecord) async -> Bool {
        guard let appStore, let fileStore else { return false }
        do {
            try await appStore.delete(id: app.id)
            do {
                try await fileStore.removeApp(appID: app.id)
                try? await signingHistoryStore?.markDeleted(appID: app.id)
            } catch {
                try? await appStore.save(app)
                throw error
            }
            await load(force: true)
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

    func resumeRefresh() {
        startBatchRefresh(resume: true)
    }

    func cancelBatchRefresh() {
        batchRefreshTask?.cancel()
        batchRefreshSession = nil
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
        enforceCooldown: Bool = false
    ) {
        guard batchRefreshTask == nil,
              signingTask == nil,
              renewalCoordinator != nil else { return }
        batchRefreshTask = Task { [weak self] in
            guard let self else { return }
            guard await self.refreshSigningChannel() else {
                self.batchRefreshTask = nil
                self.presentVPNRecovery(
                    for: .batch(
                        resume: resume,
                        dueLeadHours: dueLeadHours,
                        enforceCooldown: enforceCooldown
                    )
                )
                return
            }
            self.batchRefreshSession = BatchRefreshSession()
            await self.runBatchRefresh(
                resume: resume,
                dueLeadHours: dueLeadHours,
                enforceCooldown: enforceCooldown
            )
        }
    }

    private func presentVPNRecovery(for action: PendingVPNAction) {
        pendingVPNAction = action
        alertFailure = ImportFailure(
            title: "安装通道未就绪",
            reason: "Seal 还没有读取到可用的 LocalDevVPN 安装通道。请保持 VPN 已连接后返回设置运行一键检测。",
            recovery: "打开 LocalDevVPN",
            code: "SEAL-INSTALL-706"
        )
    }

    private func runBatchRefresh(
        resume: Bool,
        dueLeadHours: Int? = nil,
        enforceCooldown: Bool = false
    ) async {
        guard let renewalCoordinator else { return }
        do {
            let progress: @Sendable (BatchRefreshEvent) async -> Void = { [weak self] event in
                await self?.consumeBatchEvent(event)
            }
            let result = if let dueLeadHours {
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
                batchRefreshSession = nil
                if dueLeadHours == nil {
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
                try? await logStore?.append(
                    category: .renewal,
                    level: result.failed == 0 ? .info : .warning,
                    message: dueLeadHours == nil ? "批量刷新完成" : "打开 Seal 后自动检查完成"
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
        allowDroppingExtensions: Bool = false
    ) {
        guard signingTask == nil,
              batchRefreshTask == nil,
              signingCoordinator != nil else { return }
        let selectedCertificateSerialNumber = try? SigningCertificateSelectionPolicy
            .resolvedSerialNumber(for: app, account: account)
        signingSession = SigningSession(
            app: app,
            account: account,
            requestedBundleIdentifier: requestedBundleIdentifier,
            selectedCertificateSerialNumber: selectedCertificateSerialNumber,
            allowsDroppingExtensions: allowDroppingExtensions,
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
                allowDroppingExtensions: allowDroppingExtensions
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
                allowDroppingExtensions: allowDroppingExtensions
            )
        }
    }

    private func runSigning(
        app: AppRecord,
        account: AppleAccountRecord,
        requestedBundleIdentifier: String? = nil,
        selectedCertificateSerialNumber: String?,
        allowDroppingExtensions: Bool
    ) async {
        guard let signingCoordinator else { return }
        let attemptedBundleIdentifier = try? BundleIDPolicy.targetBundleIdentifier(
            for: app,
            requestedBundleIdentifier: requestedBundleIdentifier
        )
        do {
            let installed = try await signingCoordinator.signAndInstall(
                appID: app.id,
                accountID: account.id,
                requestedBundleIdentifier: requestedBundleIdentifier,
                selectedCertificateSerialNumber: selectedCertificateSerialNumber,
                allowDroppingExtensions: allowDroppingExtensions,
                progress: { [weak self] stage in
                    await self?.updateSigningStage(stage)
                }
            )
            let action: SigningHistoryRecord.Action = app.state == .installed ? .renew : .sign
            signingSession?.status = .succeeded(installed)
            try? await logStore?.append(
                category: .signing,
                message: app.state == .installed ? "应用续签与安装完成" : "应用签名与安装完成"
            )
            await recordSigningHistory(
                app: installed,
                account: account,
                action: action,
                result: .success,
                attemptedBundleIdentifier: attemptedBundleIdentifier,
                finalSignedBundleIdentifier: installed.mappedBundleIdentifier,
                lifecycleStatus: .active
            )
            await cleanTemporaryFilesIfNeeded(appID: installed.id)
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
        try? await signingHistoryStore.append(record)
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
        let fetchedAccounts = try? await accountRepository.fetchAll()
        return fetchedAccounts?.first { $0.id == accountID }
    }

    private func cleanTemporaryFilesIfNeeded(appID: UUID? = nil) async {
        guard UserDefaults.standard.bool(forKey: "behavior.deleteIPAAfterInstall"),
              let fileStore else { return }
        do {
            try await fileStore.clearTemporaryFiles()

            if let appID {
                try await fileStore.removeSignedIPA(appID: appID)
                try await clearStoredSignedIPAPath(appID: appID)
            } else {
                try await fileStore.clearSignedIPAs()
                try await clearAllStoredSignedIPAPaths()
            }

            try? await logStore?.append(
                category: .system,
                message: appID == nil ? "安装完成后已清理签名缓存" : "安装完成后已清理当前应用签名缓存"
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

    private func clearStoredSignedIPAPath(appID: UUID) async throws {
        guard let appStore else { return }
        var apps = try await appStore.fetchAll()
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[index].signedIPARelativePath = nil
        try await appStore.save(apps[index])
    }

    private func clearAllStoredSignedIPAPaths() async throws {
        guard let appStore else { return }
        var apps = try await appStore.fetchAll()
        for index in apps.indices where apps[index].signedIPARelativePath != nil {
            apps[index].signedIPARelativePath = nil
            try await appStore.save(apps[index])
        }
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
        let nsError = error as NSError
        return ImportFailure(
            title: "无法完成签名",
            reason: "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)",
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
            phase = .idle
            sheetDraft = draft
            sheetFailure = nil
            isImportSheetPresented = true
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

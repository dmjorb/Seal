import Foundation

@MainActor
struct AppContainer {
    let appsViewModel: AppsViewModel
    let settingsViewModel: SettingsViewModel

    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppContainer {
        if let testModel = AppsViewModel.uiTestModel(arguments: arguments) {
            return AppContainer(
                appsViewModel: testModel,
                settingsViewModel: .preview()
            )
        }

        do {
            let fileManager = FileManager.default
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw AppStoreError.invalidConfiguration
            }
            let sealDirectory = applicationSupport.appending(
                path: "Seal",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: sealDirectory,
                withIntermediateDirectories: true
            )
            try CompleteFileProtector().protect(sealDirectory)

            let appStore = try CoreDataAppStore(
                storeURL: sealDirectory.appending(path: "Seal.sqlite")
            )
            let fileStore = try AppFileStore.live()
            let accountRepository = ProtectedAccountRepository(
                fileURL: sealDirectory.appending(path: "Accounts.json")
            )
            let keychain = KeychainVault()
            let pairingStore = PairingStore(
                fileURL: sealDirectory.appending(path: "Pairing.plist")
            )
            let anisetteProvider = AnisetteV3Client()
            let installChannel = MinimuxerInstallChannel(
                pairingStore: pairingStore,
                logDirectory: sealDirectory.appending(
                    path: "Logs/Minimuxer",
                    directoryHint: .isDirectory
                )
            )
            let workflow = ImportWorkflow(
                parser: IPAParserService(),
                fileStore: fileStore,
                appStore: appStore
            )
            let signingCoordinator = SigningCoordinator(
                appStore: appStore,
                accountRepository: accountRepository,
                keychain: keychain,
                fileStore: fileStore,
                installChannel: installChannel,
                portal: ApplePortalSigningService(
                    anisetteProvider: anisetteProvider
                )
            )
            let refreshQueueStore = RefreshQueueStore(
                fileURL: sealDirectory.appending(path: "RefreshQueue.json")
            )
            let logStore = SealLogStore(
                fileURL: sealDirectory.appending(path: "Logs/Seal.json")
            )
            let signingHistoryStore = SigningHistoryStore(
                fileURL: sealDirectory.appending(path: "SigningHistory.json")
            )
            let notificationScheduler = ExpiryNotificationScheduler()
            let notificationPreferences = NotificationPreferences()
            let renewalCoordinator = RenewalCoordinator(
                appStore: appStore,
                signingCoordinator: signingCoordinator,
                queueStore: refreshQueueStore
            )
            let appRecordRecovery = AppRecordRecovery(
                appStore: appStore,
                fileStore: fileStore
            )
            let selfAppRegistrar = SelfAppMetadata.current().map {
                SelfAppRegistrar(
                    metadata: $0,
                    appStore: appStore,
                    accountRepository: accountRepository,
                    fileStore: fileStore
                )
            }

            return AppContainer(
                appsViewModel: AppsViewModel(
                    workflow: workflow,
                    appStore: appStore,
                    fileStore: fileStore,
                    accountRepository: accountRepository,
                    signingCoordinator: signingCoordinator,
                    installChannel: installChannel,
                    renewalCoordinator: renewalCoordinator,
                    appRecordRecovery: appRecordRecovery,
                    selfAppRegistrar: selfAppRegistrar,
                    logStore: logStore,
                    signingHistoryStore: signingHistoryStore,
                    notificationScheduler: notificationScheduler,
                    notificationPreferences: notificationPreferences
                ),
                settingsViewModel: SettingsViewModel(
                    accountRepository: accountRepository,
                    keychain: keychain,
                    accountClient: AppleAccountClient(
                        anisetteProvider: anisetteProvider
                    ),
                    pairingStore: pairingStore,
                    installChannel: installChannel,
                    appStore: appStore,
                    fileStore: fileStore,
                    logStore: logStore,
                    signingHistoryStore: signingHistoryStore,
                    notificationScheduler: notificationScheduler,
                    notificationPreferences: notificationPreferences,
                    anisetteEnvironment: anisetteProvider
                )
            )
        } catch {
            let failure = ImportFailure(
                title: "无法打开数据",
                reason: "本地存储不可用",
                recovery: "重新打开 Seal",
                code: "SEAL-APP-001"
            )
            return AppContainer(
                appsViewModel: AppsViewModel(startupFailure: failure),
                settingsViewModel: SettingsViewModel(startupFailure: failure)
            )
        }
    }
}

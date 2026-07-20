import SwiftUI

struct RootTabView: View {
    @ObservedObject var appsViewModel: AppsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppSection = .apps
    @State private var isNetworkPromptPresented = false
    @AppStorage("behavior.autoRenew") private var autoRenew = false
    @AppStorage("behavior.autoRenew.lastCheckAt") private var lastAutoRenewCheckAt = 0.0
    @AppStorage("onboarding.networkPromptShown") private var networkPromptShown = false
    @AppStorage("onboarding.notificationPromptRequested") private var notificationPromptRequested = false

    var body: some View {
        TabView(selection: $selection) {
            AppsRootView(
                viewModel: appsViewModel,
                settingsViewModel: settingsViewModel
            )
            .tabItem {
                Label(AppSection.apps.title, systemImage: AppSection.apps.systemImage)
            }
            .tag(AppSection.apps)

            SettingsRootView(
                viewModel: settingsViewModel,
                relatedApps: appsViewModel.apps
            )
            .tabItem {
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
            }
            .tag(AppSection.settings)
        }
        .tint(.sealAccent)
        .sealScreenBackground()
        .task {
            await runInitialPermissionFlow()
        }
        .alert("需要开启网络访问", isPresented: $isNetworkPromptPresented) {
            Button("继续") {
                networkPromptShown = true
                Task { await requestNotificationPermissionIfNeeded() }
            }
        } message: {
            Text("Seal 需要连接 Apple 签名服务、同步 App ID 和描述文件，并通过本地安装通道连接当前设备。请在后续系统弹窗中允许相关访问。")
        }
        .onChange(of: appsViewModel.shouldOpenSettings) { shouldOpen in
            guard shouldOpen else { return }
            selection = .settings
            settingsViewModel.requestedRoute = appsViewModel.requestedSettingsRoute
                ?? settingsViewModel.environment.nextSetupStep.map(SettingsRoute.init)
                ?? .account
            appsViewModel.requestedSettingsRoute = nil
            appsViewModel.shouldOpenSettings = false
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active,
                  settingsViewModel.environment.isConfigured else { return }
            Task {
                _ = await appsViewModel.refreshSigningChannel()
                if autoRenew, shouldRunAutoRenewCheck {
                    lastAutoRenewCheckAt = Date().timeIntervalSince1970
                    appsViewModel.refreshDueApps(leadHours: settingsViewModel.reminderHours, enforceCooldown: true)
                }
            }
        }
        .onOpenURL { url in
            if LocalDevVPNLink.isCallback(url) {
                selection = .apps
                Task {
                    await settingsViewModel.testLocalDevVPN()
                    await appsViewModel.resumePendingVPNAction()
                }
                return
            }

            guard url.isFileURL else { return }
            selection = .apps
            Task { await appsViewModel.importSelectedFile(url) }
        }
    }

    private var shouldRunAutoRenewCheck: Bool {
        Date().timeIntervalSince1970 - lastAutoRenewCheckAt >= 21_600
    }

    @MainActor
    private func runInitialPermissionFlow() async {
        guard networkPromptShown else {
            isNetworkPromptPresented = true
            return
        }
        await requestNotificationPermissionIfNeeded()
    }

    @MainActor
    private func requestNotificationPermissionIfNeeded() async {
        guard notificationPromptRequested == false else { return }
        notificationPromptRequested = true
        await settingsViewModel.requestInitialPermissionsIfNeeded()
    }
}

extension SettingsRoute {
    init(_ step: EnvironmentSetupStep) {
        switch step {
        case .account: self = .addAccount
        case .pairing: self = .pairing
        }
    }
}

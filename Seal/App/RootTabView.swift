import SwiftUI

struct RootTabView: View {
    @ObservedObject var appsViewModel: AppsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppSection = .apps
    @AppStorage("behavior.autoRenew") private var autoRenew = false
    @AppStorage("behavior.autoRenew.lastCheckAt") private var lastAutoRenewCheckAt = 0.0

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
            await settingsViewModel.requestInitialPermissionsIfNeeded()
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
}

extension SettingsRoute {
    init(_ step: EnvironmentSetupStep) {
        switch step {
        case .account: self = .addAccount
        case .pairing: self = .pairing
        }
    }
}

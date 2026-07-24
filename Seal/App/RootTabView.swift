import SwiftUI

struct RootTabView: View {
    @ObservedObject var appsViewModel: AppsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppSection = .apps
    @State private var launchCheckInProgress = false
    @AppStorage("behavior.autoRenew") private var autoRenew = false
    @AppStorage("appearance.mode") private var appearanceRawValue = SealAppearance.system.rawValue

    var body: some View {
        TabView(selection: $selection) {
            AppsRootView(
                viewModel: appsViewModel,
                settingsViewModel: settingsViewModel
            )
            .tabItem {
                Label(AppSection.apps.title, systemImage: AppSection.apps.systemImage)
                    .accessibilityIdentifier("root-tab-apps")
            }
            .tag(AppSection.apps)

            SettingsRootView(
                viewModel: settingsViewModel,
                relatedApps: appsViewModel.apps
            )
            .tabItem {
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                    .accessibilityIdentifier("root-tab-settings")
            }
            .tag(AppSection.settings)
        }
        .tint(.sealAccent)
        .preferredColorScheme(SealAppearance(rawValue: appearanceRawValue)?.colorScheme)
        .sealScreenBackground()
        .task {
            await LocalNetworkPermissionPrimer.requestIfNeeded()
            await performLaunchCheck()
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
            guard phase == .active else { return }
            Task { await performLaunchCheck() }
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

    @MainActor
    private func performLaunchCheck() async {
        guard launchCheckInProgress == false else { return }
        launchCheckInProgress = true
        defer { launchCheckInProgress = false }

        await settingsViewModel.performLightweightLaunchCheck()
        await appsViewModel.performLightweightLaunchCheck()
        guard autoRenew else { return }
        await appsViewModel.startDailyAutoRenewIfNeeded()
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

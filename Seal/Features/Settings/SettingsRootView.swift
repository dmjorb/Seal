import SwiftUI
import UIKit

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]

    @State private var navigationPath = NavigationPath()
    @State private var isAddingAccount = false
    @State private var isChecking = false

    @AppStorage("behavior.autoRenew") private var autoRenew = false
    @AppStorage("behavior.deleteIPAAfterInstall") private var deleteIPAAfterInstall = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    settingsSection("签名环境") {
                        NavigationLink(value: SettingsRoute.pairing) {
                            settingsRow(
                                title: "设备",
                                value: devicePairingSummary,
                                icon: "iphone",
                                showsChevron: true,
                                statusColor: pairingStatusColor
                            )
                        }
                        sectionDivider

                        NavigationLink(value: SettingsRoute.account) {
                            settingsRow(
                                title: "Apple ID",
                                value: accountSummary,
                                icon: "person.crop.circle",
                                showsChevron: true,
                                statusColor: accountStatusColor
                            )
                        }
                        sectionDivider

                        NavigationLink(value: SettingsRoute.certificates) {
                            settingsRow(
                                title: "签名证书",
                                value: certificateSummary,
                                icon: "checkmark.seal",
                                showsChevron: true,
                                statusColor: certificateStatusColor
                            )
                        }
                        sectionDivider

                        NavigationLink(value: SettingsRoute.localDevVPN) {
                            settingsRow(
                                title: "LocalDevVPN",
                                value: localDevVPNSummary,
                                icon: "network",
                                showsChevron: true,
                                statusColor: localDevVPNStatusColor
                            )
                        }
                        sectionDivider

                        Button {
                            runEnvironmentCheck()
                        } label: {
                            settingsRow(
                                title: "一键检测",
                                value: oneClickCheckSummary,
                                icon: isChecking ? "hourglass" : "waveform.path.ecg",
                                showsChevron: false,
                                statusColor: diagnosticStatusColor
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isChecking)
                    }

                    settingsSection("自动化") {
                        Toggle(isOn: $autoRenew) {
                            settingsRow(
                                title: "打开 Seal 后自动续签",
                                value: autoRenew ? "开" : "关",
                                icon: "clock.arrow.circlepath",
                                showsChevron: false
                            )
                        }
                        .tint(.sealAccent)
                        sectionDivider
                        Toggle(isOn: Binding(
                            get: { viewModel.notificationsEnabled },
                            set: { enabled in
                                viewModel.submitNotificationsEnabled(enabled)
                            }
                        )) {
                            settingsRow(
                                title: "到期前 24 小时提醒",
                                value: viewModel.notificationsEnabled ? "开" : "关",
                                icon: "bell",
                                showsChevron: false,
                                iconColor: Color.sealWarning
                            )
                        }
                        .tint(.sealAccent)
                        .disabled(viewModel.isNotificationOperationRunning)
                    }
                    Text("开启后，每天第一次打开 Seal 会自动续签全部 App。")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.top, -14)

                    settingsSection("使用教程") {
                        NavigationLink { SigningAndRenewalGuideView() } label: {
                            settingsRow(
                                title: "签名和续签",
                                value: nil,
                                icon: "book.closed",
                                showsChevron: true
                            )
                        }
                    }

                    settingsSection("存储与维护") {
                        NavigationLink(value: SettingsRoute.storage) {
                            settingsRow(
                                title: "IPA 与签名缓存",
                                value: viewModel.storageUsage.total.formattedByteCount,
                                icon: "internaldrive",
                                showsChevron: true
                            )
                        }
                        sectionDivider
                        NavigationLink(value: SettingsRoute.logs) {
                            settingsRow(
                                title: "日志中心",
                                value: latestLogSummary,
                                icon: "list.bullet.rectangle",
                                showsChevron: true,
                                statusColor: latestLogStatusColor,
                                iconColor: Color.sealTextSecondary
                            )
                        }
                        sectionDivider
                        Toggle(isOn: $deleteIPAAfterInstall) {
                            settingsRow(
                                title: "安装完成后清理签名缓存",
                                value: deleteIPAAfterInstall ? "开" : "关",
                                icon: "trash",
                                showsChevron: false,
                                iconColor: Color.sealDanger
                            )
                        }
                        .tint(.sealAccent)
                    }

                    settingsSection("安全与隐私") {
                        NavigationLink { PrivacyNoticeView() } label: {
                            settingsRow(
                                title: "本机签名与凭据说明",
                                value: nil,
                                icon: "lock.shield",
                                showsChevron: true
                            )
                        }
                    }

                    settingsSection("关于 Seal") {
                        NavigationLink { AboutView() } label: {
                            settingsRow(
                                title: "当前版本",
                                value: appVersion,
                                icon: "info.circle",
                                showsChevron: true
                            )
                        }
                        sectionDivider
                        NavigationLink { OpenSourceLicensesView() } label: {
                            settingsRow(
                                title: "开源许可",
                                value: nil,
                                icon: "doc.text",
                                showsChevron: true
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .navigationTitle("我的")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .account:
                    CertificatesRootView(viewModel: viewModel, relatedApps: relatedApps)
                case .addAccount:
                    EmptyView()
                case .certificates:
                    SigningCertificateSettingsView(viewModel: viewModel, relatedApps: relatedApps)
                case .accountDetail(let id):
                    if let account = viewModel.accounts.first(where: { $0.id == id }) {
                        AppleAccountDetailView(
                            account: account,
                            relatedApps: relatedApps,
                            viewModel: viewModel
                        )
                    }
                case .pairing:
                    PairingSettingsView(viewModel: viewModel)
                case .localDevVPN:
                    LocalDevVPNSettingsView(viewModel: viewModel)
                case .storage:
                    StorageMaintenanceView(viewModel: viewModel)
                case .logs:
                    LogsCenterView(viewModel: viewModel)
                }
            }
            .alert(item: $viewModel.alertFailure) { failure in
                Alert(
                    title: Text(failure.title),
                    message: Text(failure.userMessage),
                    dismissButton: .default(Text(failure.recovery))
                )
            }
            .task { await viewModel.load(force: true) }
            .onAppear {
                Task { await viewModel.load(force: true) }
            }
            .refreshable {
                await viewModel.load(force: true)
                await viewModel.refreshStorageUsage()
            }
            .onChange(of: viewModel.requestedRoute) { route in
                guard let route else { return }
                viewModel.requestedRoute = nil
                if route == .addAccount {
                    isAddingAccount = true
                    return
                }
                navigationPath.append(route)
            }
            .fullScreenCover(isPresented: $isAddingAccount) {
                AddAccountView(viewModel: viewModel)
            }
        }
        .sealScreenBackground()
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sealTextSecondary)
                .padding(.leading, 8)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 16)
                .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
                }
        }
    }

    private func settingsRow(
        title: String,
        value: String?,
        icon: String,
        showsChevron: Bool,
        statusColor: Color? = nil,
        iconColor: Color = Color.sealAccent
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 34)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            if let statusColor {
                Circle().fill(statusColor).frame(width: 9, height: 9)
            }
            if let value {
                Text(value)
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var sectionDivider: some View {
        Divider().padding(.leading, 50)
    }

    private func runEnvironmentCheck() {
        guard isChecking == false else { return }
        isChecking = true
        Task {
            await viewModel.testConnection()
            isChecking = false
        }
    }

    private var verifiedAccounts: [AppleAccountRecord] {
        viewModel.accounts.filter { $0.status == .verified }
    }

    private var accountSummary: String {
        if let account = viewModel.activeAccount { return account.maskedEmail }
        if viewModel.accounts.isEmpty { return "未添加" }
        return "请选择"
    }

    private var certificateSummary: String {
        guard let account = viewModel.activeAccount else { return "不可用" }
        guard CertificateSerial.canonical(account.certificateSerialNumber) != nil else {
            return "签名时创建"
        }
        if let selected = account.selectedCertificateSerialNumber,
           CertificateSerial.matches(selected, account.certificateSerialNumber) == false {
            return "私钥不可用"
        }
        return "本机可用"
    }

    private var devicePairingSummary: String {
        guard let pairing = viewModel.pairingRecord else { return "未导入" }
        return pairing.validationStatus.title
    }

    private var localDevVPNSummary: String {
        switch viewModel.diagnosticState {
        case .ready:
            return "已连接"
        case .running:
            return "检测中"
        case .failed(let failure):
            if failure.code.hasPrefix("SEAL-PAIR-") { return "待配对" }
            if failure.code.hasPrefix("SEAL-INSTALL-") { return "连接异常" }
            return "未检测"
        case .idle:
            return "未检测"
        }
    }

    private var latestLogSummary: String {
        guard let log = viewModel.logs.first else { return "暂无日志" }
        return log.level.displayTitle
    }

    private var accountStatusColor: Color {
        guard let account = viewModel.activeAccount else {
            return viewModel.accounts.isEmpty
                ? Color.sealTextSecondary.opacity(0.55)
                : Color.sealWarning
        }
        return account.status == .verified ? .sealSuccess : .sealWarning
    }

    private var certificateStatusColor: Color {
        guard let account = viewModel.activeAccount else {
            return Color.sealTextSecondary.opacity(0.55)
        }
        if let selected = account.selectedCertificateSerialNumber,
           CertificateSerial.matches(selected, account.certificateSerialNumber) == false {
            return Color.sealDanger
        }
        return account.certificateSerialNumber == nil
            ? Color.sealWarning
            : Color.sealSuccess
    }

    private var pairingStatusColor: Color {
        guard let pairing = viewModel.pairingRecord else { return .sealWarning }
        switch pairing.validationStatus {
        case .verified: return .sealSuccess
        case .deviceMismatch, .fileUnreadable: return .sealDanger
        case .unverified, .validating: return .sealWarning
        }
    }

    private var localDevVPNStatusColor: Color {
        switch viewModel.diagnosticState {
        case .ready:
            return .sealSuccess
        case .running:
            return .sealAccent
        case .failed(let failure):
            if failure.code.hasPrefix("SEAL-INSTALL-") { return .sealDanger }
            if failure.code.hasPrefix("SEAL-PAIR-") { return .sealWarning }
            return Color.sealTextSecondary.opacity(0.55)
        case .idle:
            return Color.sealTextSecondary.opacity(0.55)
        }
    }

    private var diagnosticStatusColor: Color {
        switch viewModel.diagnosticState {
        case .ready: return .sealSuccess
        case .running: return .sealAccent
        case .failed: return .sealDanger
        case .idle: return Color.sealTextSecondary.opacity(0.55)
        }
    }

    private var latestLogStatusColor: Color? {
        guard let log = viewModel.logs.first else { return nil }
        switch log.level {
        case .info: return .sealSuccess
        case .warning: return .sealWarning
        case .error: return .sealDanger
        }
    }

    private var oneClickCheckSummary: String {
        if isChecking { return "检测中…" }
        switch viewModel.diagnosticState {
        case .ready: return "环境正常"
        case .running: return "检测中…"
        case .failed: return "发现问题"
        case .idle: return "未检测"
        }
    }



    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

private extension Int64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

private extension SealLogEntry.Level {
    var displayTitle: String {
        switch self {
        case .info: return "正常"
        case .warning: return "警告"
        case .error: return "失败"
        }
    }
}

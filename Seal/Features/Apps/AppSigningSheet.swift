import SwiftUI
import UIKit

struct AppSigningSheet: View {
    let app: AppRecord
    @ObservedObject var viewModel: AppsViewModel
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedAccountID: UUID?
    @State private var targetBundleID = ""
    @State private var isBundleIDEditorPresented = false
    @State private var isPreflightDetailPresented = false
    @State private var currentSealSigningTeamID: String?

    var body: some View {
        Group {
            if viewModel.signingSession?.app.id == app.id {
                SigningProgressView(viewModel: viewModel, onFinish: onFinish)
            } else {
                configuration
            }
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isRunning)
        .task {
            currentSealSigningTeamID = SelfAppMetadata.current()?.signingTeamIdentifier
            selectDefaultAccount()
            resetBundleIDDraftIfNeeded()
        }
        .onChange(of: viewModel.verifiedAccounts) { _ in
            selectDefaultAccount()
        }
        .sheet(isPresented: $isBundleIDEditorPresented) {
            BundleIDEditorSheet(app: app, targetBundleID: $targetBundleID)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isPreflightDetailPresented) {
            SigningPreflightDetailSheet(
                app: app,
                account: selectedAccount,
                targetBundleIdentifier: displayBundleIdentifier,
                certificateSummary: certificateSummary,
                installChannelStatus: viewModel.signingChannelStatus,
                operationSummary: operationSummary,
                expectedValidity: expectedValiditySummary
            )
            .presentationDetents([.medium, .large])
        }
        .alert(item: $viewModel.alertFailure) { failure in
            vpnAwareAlert(failure)
        }
    }

    private var configuration: some View {
        let presentation = AppOperationPresentation(app: app)
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                SealSheetGrabber()

                Text(presentation.sheetTitle)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.primary)

                appIdentity(presentation: presentation)

                if presentation.kind == .expiredRenewal {
                    expiredWarningBanner
                }

                operationSummaryCard(presentation: presentation)

                preflightEntryCard

                Button(primaryActionTitle(for: presentation)) {
                    if selfAccountValidationError != nil {
                        viewModel.openSettings(route: .account)
                        dismiss()
                    } else if let selectedAccountID {
                        Task {
                            await viewModel.beginSigning(
                                for: app,
                                accountID: selectedAccountID,
                                requestedBundleIdentifier: requestedBundleIDForSigning
                            )
                        }
                    } else {
                        viewModel.openSettings(route: .account)
                        dismiss()
                    }
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(bundleIDValidationError != nil)
                .opacity(bundleIDValidationError == nil ? 1 : 0.48)
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .sealSheetBackground(.tertiary)
    }

    private func appIdentity(presentation: AppOperationPresentation) -> some View {
        HStack(spacing: 16) {
            appIcon(size: 60)
            VStack(alignment: .leading, spacing: 7) {
                Text(app.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("v\(app.version) · \(Self.fileSizeFormatter.string(fromByteCount: app.size))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let validity = presentation.validity {
                Text(validity.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(validityColor(validity.tone))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func operationSummaryCard(presentation: AppOperationPresentation) -> some View {
        VStack(spacing: 0) {
            Button {
                if BundleIDPolicy.isEditable(app) {
                    isBundleIDEditorPresented = true
                }
            } label: {
                summaryRow(
                    title: app.state == .installed ? "续签 Bundle ID" : "目标 Bundle ID",
                    value: displayBundleIdentifier,
                    caption: app.state == .installed || app.isSeal ? "已锁定" : (SelfManagedSealMigrationPolicy.isMigrationPackage(app) ? "自续签推荐 ID" : "默认使用 .seal"),
                    actionTitle: BundleIDPolicy.isEditable(app) ? "修改" : nil
                )
            }
            .buttonStyle(.plain)
            .disabled(BundleIDPolicy.isEditable(app) == false)

            if let bundleIDValidationError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sealDanger)
                    Text(bundleIDValidationError)
                        .font(.caption)
                        .foregroundStyle(Color.sealDanger)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Divider().padding(.leading, 16)

            if viewModel.verifiedAccounts.isEmpty {
                Button {
                    viewModel.openSettings(route: .account)
                    dismiss()
                } label: {
                    summaryRow(
                        title: "Apple ID",
                        value: "去添加或重新验证",
                        caption: "签名前需要可用账号",
                        actionTitle: "设置"
                    )
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(viewModel.verifiedAccounts) { account in
                        Button(accountPickerTitle(account)) { selectedAccountID = account.id }
                    }
                } label: {
                    summaryRow(
                        title: "Apple ID",
                        value: selectedAccountCompactSummary,
                        caption: selectedAccount == nil ? "请选择账号" : operationAccountCaption,
                        actionTitle: isAccountSelectionLocked ? nil : "切换"
                    )
                }
                .disabled(isAccountSelectionLocked)
            }

            Divider().padding(.leading, 16)

            summaryRow(
                title: "有效期",
                value: expectedValiditySummary,
                caption: operationSummary,
                actionTitle: nil
            )
        }
        .padding(.horizontal, 16)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private var preflightEntryCard: some View {
        Button {
            isPreflightDetailPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preflightIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(preflightColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preflightTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(preflightSubtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sealTextSecondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 68)
            .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(
        title: String,
        value: String,
        caption: String?,
        actionTitle: String?
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                if let caption, caption.isEmpty == false {
                    Text(caption)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text(value)
                    .font(.system(size: 14, weight: .regular, design: title.contains("Bundle") ? .monospaced : .default))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if let actionTitle {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sealAccent)
                }
            }
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private var expiredWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.sealDanger)
            Text("应用已过期，续签后需要重新安装")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sealDanger)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(
            Color.sealDanger.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        Group {
            if let data = viewModel.iconData[app.id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(Color.sealAccent)
                    .background(.white.opacity(0.72))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var displayBundleIdentifier: String {
        if SelfManagedSealMigrationPolicy.isMigrationPackage(app) {
            return targetBundleID.isEmpty
                ? SelfManagedSealMigrationPolicy.recommendedBundleIdentifier(teamID: selectedAccount?.teamID)
                : targetBundleID
        }
        if app.isSeal {
            return Bundle.main.bundleIdentifier
                ?? app.mappedBundleIdentifier
                ?? app.originalBundleIdentifier
        }
        if app.state == .installed {
            return app.mappedBundleIdentifier
                ?? app.preferredBundleIdentifier
                ?? app.originalBundleIdentifier
        }
        return targetBundleID.isEmpty
            ? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
            : targetBundleID
    }

    private var requestedBundleIDForSigning: String? {
        BundleIDPolicy.isEditable(app) ? targetBundleID : nil
    }

    private var bundleIDValidationError: String? {
        guard BundleIDPolicy.isEditable(app) else { return nil }
        return BundleIDPolicy.validationError(for: targetBundleID)
    }

    private var selfAccountValidationError: String? {
        guard app.isSeal,
              let currentSealSigningTeamID,
              currentSealSigningTeamID.isEmpty == false,
              let selectedAccount,
              selectedAccount.teamID.caseInsensitiveCompare(currentSealSigningTeamID) != .orderedSame else {
            return nil
        }
        return "当前 Seal 由 Team \(currentSealSigningTeamID) 签出，必须选择该 Team 对应的 Apple ID。"
    }

    private var signingValidationError: String? {
        bundleIDValidationError ?? selfAccountValidationError
    }

    private func resetBundleIDDraftIfNeeded() {
        guard targetBundleID.isEmpty else { return }
        if SelfManagedSealMigrationPolicy.isMigrationPackage(app) {
            targetBundleID = SelfManagedSealMigrationPolicy.recommendedBundleIdentifier(
                teamID: selectedAccount?.teamID
            )
            return
        }
        targetBundleID = (try? BundleIDPolicy.targetBundleIdentifier(for: app))
            ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
    }

    private var selectedAccount: AppleAccountRecord? {
        viewModel.verifiedAccounts.first { $0.id == selectedAccountID }
    }

    private var selectedAccountCompactSummary: String {
        guard let selectedAccount else { return "请选择" }
        return accountCompactTitle(selectedAccount)
    }

    private var operationAccountCaption: String {
        if app.isSeal {
            if let currentSealSigningTeamID, currentSealSigningTeamID.isEmpty == false {
                return selectedAccount?.teamID.caseInsensitiveCompare(currentSealSigningTeamID) == .orderedSame
                    ? "当前安装签名账号"
                    : "当前安装 Team：\(currentSealSigningTeamID)"
            }
            return app.accountID == nil ? "Team 将在签名前确认" : "本地续签账号"
        }
        if app.state == .installed && app.accountID != nil {
            return "续签账号已绑定"
        }
        return selectedAccount?.teamID ?? "Team 将在签名前确认"
    }

    private var isAccountSelectionLocked: Bool {
        if app.isSeal {
            guard let currentSealSigningTeamID, currentSealSigningTeamID.isEmpty == false else {
                return false
            }
            return viewModel.verifiedAccounts.contains { account in
                account.teamID.caseInsensitiveCompare(currentSealSigningTeamID) == .orderedSame
            }
        }
        return app.state == .installed && app.accountID != nil
    }

    private func accountCompactTitle(_ account: AppleAccountRecord) -> String {
        let kind = account.isFreeTeam == false ? "Developer" : "Free"
        return "\(account.maskedEmail) · \(kind)"
    }

    private func accountPickerTitle(_ account: AppleAccountRecord) -> String {
        "\(accountCompactTitle(account)) · \(account.teamID)"
    }

    private var certificateSummary: String {
        guard let selectedAccount else { return "选择 Apple ID 后自动准备" }
        guard let serial = selectedAccount.certificateSerialNumber, serial.isEmpty == false else {
            return "签名时自动准备"
        }
        return "Apple Development · \(Self.abbreviatedIdentifier(serial))"
    }

    private var operationSummary: String {
        if SelfManagedSealMigrationPolicy.isMigrationPackage(app) { return "迁移为 Seal 自续签版" }
        if app.isSeal { return "Seal 自刷新" }
        if app.state == .installed { return "续签身份已锁定" }
        return "首次签名"
    }

    private var expectedValiditySummary: String {
        if selectedAccount?.isFreeTeam == false {
            return "按开发者账号配置"
        }
        switch AppOperationPresentation(app: app).kind {
        case .signing:
            return "预计 7 天"
        case .renewal, .urgentRenewal:
            return "续期约 7 天"
        case .expiredRenewal:
            return "重新安装后约 7 天"
        }
    }

    private var preflightIcon: String {
        if selectedAccount == nil || signingValidationError != nil { return "exclamationmark.triangle.fill" }
        if viewModel.signingChannelStatus == .unavailable { return "wrench.and.screwdriver.fill" }
        return "checkmark.seal.fill"
    }

    private var preflightColor: Color {
        if selectedAccount == nil || signingValidationError != nil { return .sealWarning }
        if viewModel.signingChannelStatus == .unavailable { return .sealTextSecondary }
        return .sealSuccess
    }

    private var preflightTitle: String {
        if selectedAccount == nil { return "签名前检查需要 Apple ID" }
        if signingValidationError != nil { return app.isSeal ? "续签账号不匹配" : "Bundle ID 需要处理" }
        if viewModel.signingChannelStatus == .unavailable { return "安装通道待检测" }
        return "签名前检查"
    }

    private var preflightSubtitle: String {
        if selectedAccount == nil { return "添加或重新验证账号后再签名。" }
        if let signingValidationError { return signingValidationError }
        if viewModel.signingChannelStatus == .ready { return "账号、Bundle ID、签名身份和安装通道可继续查看。" }
        return "详细 Team、证书、设备和安装通道信息已收起到这里。"
    }

    private func primaryActionTitle(for presentation: AppOperationPresentation) -> String {
        if selfAccountValidationError != nil { return "去添加当前签名 Apple ID" }
        return selectedAccountID == nil ? "去添加 Apple ID" : presentation.primaryAction
    }

    private var isRunning: Bool {
        if case .running = viewModel.signingSession?.status { return true }
        return false
    }

    private func selectDefaultAccount() {
        let verifiedAccounts = viewModel.verifiedAccounts.sorted {
            $0.lastVerifiedAt > $1.lastVerifiedAt
        }
        if app.isSeal,
           let currentSealSigningTeamID,
           currentSealSigningTeamID.isEmpty == false,
           let matchedAccount = verifiedAccounts.first(where: {
               $0.teamID.caseInsensitiveCompare(currentSealSigningTeamID) == .orderedSame
           }) {
            selectedAccountID = matchedAccount.id
            return
        }
        guard selectedAccountID == nil else { return }
        if app.state == .installed,
           let accountID = app.accountID,
           verifiedAccounts.contains(where: { $0.id == accountID }) {
            selectedAccountID = accountID
        } else {
            selectedAccountID = verifiedAccounts.first?.id
        }
    }

    private func footerText(for kind: AppOperationKind) -> String {
        switch kind {
        case .signing:
            if SelfManagedSealMigrationPolicy.isMigrationPackage(app) {
                return "这会安装一个新的 Seal 自续签版；确认能打开后，再删除爱思助手签名的旧 Seal。"
            }
            return "抽屉只保留本次操作关键项；详细诊断可在签名前检查中查看。"
        case .renewal, .urgentRenewal, .expiredRenewal:
            return "续签沿用上一次签名身份；如需更换账号或 Bundle ID，请重新导入作为新应用。"
        }
    }

    private func validityColor(_ tone: AppValidityTone) -> Color {
        switch tone {
        case .neutral: .sealTextSecondary
        case .warning: .sealWarning
        case .danger: .sealDanger
        }
    }

    private func vpnAwareAlert(_ failure: ImportFailure) -> Alert {
        if (failure.code == "SEAL-INSTALL-701" || failure.code == "SEAL-INSTALL-706"), viewModel.hasPendingVPNRecovery {
            return Alert(
                title: Text(failure.title),
                message: Text(failure.reason),
                primaryButton: .default(Text("打开 LocalDevVPN")) { openLocalDevVPN() },
                secondaryButton: .cancel(Text("取消")) {
                    viewModel.cancelPendingVPNRecovery()
                }
            )
        }
        return Alert(
            title: Text(failure.title),
            message: Text("\(failure.reason)\n\(failure.code)"),
            dismissButton: .default(Text(failure.recovery)) {
                viewModel.performAlertRecovery(for: failure)
            }
        )
    }

    private func openLocalDevVPN() {
        openURL(LocalDevVPNLink.enableAndReturn) { accepted in
            guard accepted == false else { return }
            openURL(LocalDevVPNLink.appStore)
        }
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static func abbreviatedIdentifier(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }
}

private struct BundleIDEditorSheet: View {
    let app: AppRecord
    @Binding var targetBundleID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("原始 Bundle ID")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sealTextSecondary)
                        Text(app.originalBundleIdentifier)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("签名后 Bundle ID")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sealTextSecondary)
                        TextField("Bundle ID", text: $targetBundleID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                Color.sealSurfaceElevated,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        if let error = BundleIDPolicy.validationError(for: targetBundleID) {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Color.sealDanger)
                        } else {
                            Text("修改 Bundle ID 后，iOS 会把它视为另一个应用；续签时会锁定本次选择。")
                                .font(.caption)
                                .foregroundStyle(Color.sealTextSecondary)
                        }
                    }

                    VStack(spacing: 10) {
                        presetButton(title: "使用推荐", value: BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier), detail: "普通签名，避免和原 App 冲突。")
                        presetButton(title: "保留原始", value: app.originalBundleIdentifier, detail: "适合覆盖同一 App，可能和原版冲突。")
                        presetButton(title: "多开 1", value: "\(BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)).clone1", detail: "作为另一份 App 安装。")
                    }
                }
                .padding(24)
            }
            .background(SealBackdrop(level: .tertiary))
            .navigationTitle("修改 Bundle ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(BundleIDPolicy.validationError(for: targetBundleID) != nil)
                }
            }
        }
    }

    private func presetButton(title: String, value: String, detail: String) -> some View {
        Button {
            targetBundleID = value
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                }
                Spacer(minLength: 12)
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .background(Color.sealSurfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SigningPreflightDetailSheet: View {
    let app: AppRecord
    let account: AppleAccountRecord?
    let targetBundleIdentifier: String
    let certificateSummary: String
    let installChannelStatus: AppsViewModel.SigningChannelStatus
    let operationSummary: String
    let expectedValidity: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    diagnosticsSection("应用", rows: [
                        ("名称", app.name),
                        ("版本", "v\(app.version) (\(app.buildNumber))"),
                        ("操作", operationSummary),
                        ("有效期", expectedValidity)
                    ])

                    diagnosticsSection("Bundle ID", rows: [
                        ("原始", app.originalBundleIdentifier),
                        (app.state == .installed ? "续签" : "目标", targetBundleIdentifier),
                        ("规则", app.isSeal ? "Seal 自刷新锁定" : (app.state == .installed ? "续签锁定" : "首次签名可修改"))
                    ])

                    diagnosticsSection("Apple ID", rows: [
                        ("账号", account?.maskedEmail ?? "未选择"),
                        ("账号类型", account?.isFreeTeam == false ? "Apple Developer Program" : "个人免费账户"),
                        ("Team ID", account?.teamID ?? "未确认"),
                        ("证书", certificateSummary)
                    ])

                    diagnosticsSection("安装环境", rows: [
                        ("安装方式", app.state == .installed ? "续签后安装" : "签名后安装"),
                        ("安装通道", installChannelDescription),
                        ("扩展", extensionSummary)
                    ])
                }
                .padding(24)
            }
            .background(SealBackdrop(level: .tertiary))
            .navigationTitle("签名前检查")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var installChannelDescription: String {
        switch installChannelStatus {
        case .idle:
            return "未检测"
        case .connecting:
            return "检测中"
        case .ready:
            return "可用"
        case .unavailable:
            return "不可用"
        }
    }

    private var extensionSummary: String {
        guard app.extensions.isEmpty == false else { return "无扩展" }
        let names = app.extensions.map { extensionRecord -> String in
            switch extensionRecord.kind {
            case .widget: return "Widget"
            case .share: return "Share Extension"
            case .notificationService: return "Notification Service"
            case .unknown: return extensionRecord.name
            }
        }
        return names.joined(separator: "、")
    }

    private func diagnosticsSection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sealTextSecondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.0)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Text(row.1)
                            .font(.system(size: 13, weight: .regular, design: row.0.contains("Bundle") || row.0 == "原始" || row.0 == "目标" || row.0 == "续签" || row.0 == "Team ID" ? .monospaced : .default))
                            .foregroundStyle(Color.sealTextSecondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 46)
                    .padding(.horizontal, 14)

                    if index < rows.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color.sealSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct SealSheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.sealHairline.opacity(0.95))
            .frame(width: 40, height: 5)
            .padding(.top, 2)
    }
}

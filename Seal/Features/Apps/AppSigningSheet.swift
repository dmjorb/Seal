import SwiftUI
import UIKit

struct AppSigningSheet: View {
    let app: AppRecord
    @ObservedObject var viewModel: AppsViewModel
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccountID: UUID?
    @State private var targetBundleID = ""
    @State private var isBundleIDEditorPresented = false
    @State private var isPreflightDetailPresented = false

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
            await viewModel.load(force: true)
            await viewModel.refreshActiveAccountSelection()
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
            .presentationDetents([.height(500)])
        }
        .alert(item: $viewModel.alertFailure) { failure in
            standardAlert(failure)
        }
    }

    private var configuration: some View {
        let presentation = AppOperationPresentation(app: app)
        return VStack(spacing: 14) {
            SealSheetGrabber()

            Text(presentation.sheetTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            appIdentity(presentation: presentation)

            operationSummaryCard

            preflightEntryCard

            Button(primaryActionTitle(for: presentation)) {
                if certificateSelectionError != nil {
                    viewModel.openSettings(route: .certificates)
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
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .sealSheetBackground()
    }

    private func appIdentity(presentation: AppOperationPresentation) -> some View {
        HStack(spacing: 14) {
            appIcon(size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("v\(app.version)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
                Text(Self.fileSizeFormatter.string(fromByteCount: app.size))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let validity = presentation.validity {
                Text(validity.detailText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(validityColor(validity.tone))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var operationSummaryCard: some View {
        VStack(spacing: 0) {
            Button {
                if BundleIDPolicy.isEditable(app) {
                    isBundleIDEditorPresented = true
                }
            } label: {
                summaryRow(
                    title: "Bundle ID",
                    value: displayBundleIdentifier,
                    caption: bundleIDCaption,
                    actionTitle: "修改"
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 14)

            if viewModel.verifiedAccounts.isEmpty {
                Button {
                    viewModel.openSettings(route: .account)
                    dismiss()
                } label: {
                    summaryRow(
                        title: "Apple ID",
                        value: "去添加",
                        caption: "需要可用账号",
                        actionTitle: "设置"
                    )
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(viewModel.verifiedAccounts) { account in
                        Button(accountPickerTitle(account)) {
                            selectedAccountID = account.id
                            Task { await viewModel.selectActiveAccount(id: account.id) }
                        }
                    }
                } label: {
                    summaryRow(
                        title: "Apple ID",
                        value: selectedAccountCompactSummary,
                        caption: selectedAccount == nil ? "请选择" : operationAccountCaption,
                        actionTitle: "切换"
                    )
                }
            }

            Divider().padding(.leading, 14)

            summaryRow(
                title: "签名证书",
                value: certificateSummary,
                caption: certificateSelectionError ?? certificateCaption,
                actionTitle: certificateSelectionError == nil ? nil : "设置"
            )

            Divider().padding(.leading, 14)

            summaryRow(
                title: "有效期",
                value: expectedValiditySummary,
                caption: operationSummary,
                actionTitle: nil
            )
        }
        .padding(.horizontal, 14)
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(preflightColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preflightTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(preflightSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sealTextSecondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                if let caption, caption.isEmpty == false {
                    Text(caption)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: title.contains("Bundle") || title.contains("证书") ? .monospaced : .default))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if let actionTitle {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sealAccent)
                }
            }
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
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
                    .padding(11)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var displayBundleIdentifier: String {
        targetBundleID.isEmpty
            ? ((try? BundleIDPolicy.targetBundleIdentifier(for: app))
               ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier))
            : targetBundleID
    }

    private var requestedBundleIDForSigning: String? { targetBundleID }

    private var bundleIDValidationError: String? {
        BundleIDPolicy.validationError(for: targetBundleID)
    }

    private var signingValidationError: String? {
        bundleIDValidationError ?? certificateSelectionError
    }

    private var bundleIDCaption: String {
        if app.state == .installed || app.isSeal { return "当前 Bundle ID" }
        return "推荐 Bundle ID"
    }

    private var certificateSelectionError: String? {
        guard let selectedAccount else { return nil }
        return SigningCertificateSelectionPolicy.localAvailabilityMessage(
            for: app,
            account: selectedAccount
        )
    }

    private func resetBundleIDDraftIfNeeded() {
        guard targetBundleID.isEmpty else { return }
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
        selectedAccount?.teamID ?? "Team"
    }

    private func accountCompactTitle(_ account: AppleAccountRecord) -> String {
        let kind = account.isFreeTeam == false ? "Developer" : "Free"
        return "\(account.maskedEmail) · \(kind)"
    }

    private func accountPickerTitle(_ account: AppleAccountRecord) -> String {
        "\(accountCompactTitle(account)) · \(account.teamID)"
    }

    private var certificateSummary: String {
        guard let selectedAccount else { return "选择 Apple ID" }
        let serial = try? SigningCertificateSelectionPolicy.resolvedSerialNumber(
            for: app,
            account: selectedAccount
        )
        guard let serial, serial.isEmpty == false else { return "签名时创建" }
        return "Seal-\(serial.suffix(8))"
    }

    private var certificateCaption: String {
        if selectedAccount?.selectedCertificateSerialNumber != nil { return "当前证书" }
        return "自动使用本机证书"
    }

    private var operationSummary: String {
        if app.state == .installed || app.isSeal { return "续签并安装" }
        if app.hasPersistedSigningIdentity && app.state != .installed { return "重试安装" }
        return "首次签名"
    }

    private var expectedValiditySummary: String {
        if app.state == .installed || app.isSeal {
            return AppOperationPresentation(app: app).validity?.detailText ?? "已安装"
        }
        return "Apple 描述文件"
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
        if selectedAccount == nil { return "签名前检查" }
        if certificateSelectionError != nil { return "签名证书不可用" }
        if signingValidationError != nil { return "Bundle ID 或证书需要处理" }
        if viewModel.signingChannelStatus == .unavailable { return "安装通道不可用" }
        return "签名前检查"
    }

    private var preflightSubtitle: String {
        if selectedAccount == nil { return "需要 Apple ID" }
        if let signingValidationError { return signingValidationError }
        if viewModel.signingChannelStatus == .ready { return "可继续" }
        return "查看状态"
    }

    private func primaryActionTitle(for presentation: AppOperationPresentation) -> String {
        if certificateSelectionError != nil { return "去选择签名证书" }
        if app.hasPersistedSigningIdentity && app.state != .installed { return "重试安装" }
        return selectedAccountID == nil ? "去添加 Apple ID" : presentation.primaryAction
    }

    private var isRunning: Bool {
        if case .running = viewModel.signingSession?.status { return true }
        return false
    }

    private func selectDefaultAccount() {
        let verifiedAccounts = viewModel.verifiedAccounts.sorted { $0.lastVerifiedAt > $1.lastVerifiedAt }
        guard selectedAccountID == nil else { return }
        if let activeAccountID = viewModel.activeAccountID,
           verifiedAccounts.contains(where: { $0.id == activeAccountID }) {
            selectedAccountID = activeAccountID
        } else {
            selectedAccountID = verifiedAccounts.first?.id
        }
    }

    private func validityColor(_ tone: AppValidityTone) -> Color {
        switch tone {
        case .success: .sealSuccess
        case .neutral: .sealTextSecondary
        case .warning: .sealWarning
        case .danger: .sealDanger
        }
    }

    private func standardAlert(_ failure: ImportFailure) -> Alert {
        Alert(
            title: Text(failure.title),
            message: Text(failure.userMessage),
            dismissButton: .default(Text(failure.recovery)) {
                viewModel.performAlertRecovery(for: failure)
            }
        )
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct BundleIDEditorSheet: View {
    let app: AppRecord
    @Binding var targetBundleID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("原始 Bundle ID")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                    Text(app.originalBundleIdentifier)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
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
                    }
                }

                VStack(spacing: 10) {
                    presetButton(title: "使用推荐", value: BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier))
                    presetButton(title: "保留原始", value: app.originalBundleIdentifier)
                    presetButton(title: "多开 1", value: "\(BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)).clone1")
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(SealBackdrop())
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

    private func presetButton(title: String, value: String) -> some View {
        Button { targetBundleID = value } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
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
        VStack(spacing: 14) {
            SealSheetGrabber()
            Text("签名前检查")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            HStack(spacing: 14) {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(11)
                    .foregroundStyle(Color.sealAccent)
                    .frame(width: 52, height: 52)
                    .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    Text("v\(app.version) (\(app.buildNumber))")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(operationSummary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sealTextSecondary)
            }

            VStack(spacing: 0) {
                detailRow("Bundle ID", targetBundleIdentifier, monospaced: true)
                Divider().padding(.leading, 14)
                detailRow("Apple ID", account?.maskedEmail ?? "未选择")
                Divider().padding(.leading, 14)
                detailRow("签名证书", certificateSummary, monospaced: true)
                Divider().padding(.leading, 14)
                detailRow("有效期", expectedValidity)
                Divider().padding(.leading, 14)
                detailRow("安装通道", installChannelDescription)
                Divider().padding(.leading, 14)
                detailRow("扩展", extensionSummary)
            }
            .padding(.horizontal, 14)
            .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
            }

            Button("完成") { dismiss() }
                .sealPrimaryAction(cornerRadius: 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .sealSheetBackground()
    }

    private var installChannelDescription: String {
        switch installChannelStatus {
        case .idle: return "未检测"
        case .connecting: return "检测中"
        case .ready: return "可用"
        case .unavailable: return "不可用"
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

    private func detailRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: monospaced ? .monospaced : .default))
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(minHeight: 44)
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

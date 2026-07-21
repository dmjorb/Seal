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
                .presentationDetents([.height(260)])
        }
        .alert(item: $viewModel.alertFailure) { failure in
            standardAlert(failure)
        }
    }

    private var configuration: some View {
        let presentation = AppOperationPresentation(app: app)
        return VStack(spacing: 14) {
            SealSheetGrabber()
            appIdentity(presentation: presentation)
            operationSummaryCard
            Button(primaryActionTitle(for: presentation)) {
                if let selectedAccountID {
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
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .sealSheetBackground()
    }

    private func appIdentity(presentation: AppOperationPresentation) -> some View {
        HStack(spacing: 14) {
            appIcon(size: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("v\(app.version) · \(Self.fileSizeFormatter.string(fromByteCount: app.size))")
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
    }

    private var operationSummaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(title: "状态", value: statusText)
            Divider().padding(.leading, 14)

            Button { isBundleIDEditorPresented = true } label: {
                summaryRow(title: "Bundle ID", value: displayBundleIdentifier, monospaced: true, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 14)

            if viewModel.verifiedAccounts.isEmpty {
                Button {
                    viewModel.openSettings(route: .account)
                    dismiss()
                } label: {
                    summaryRow(title: "Apple ID", value: "去添加", showsDisclosure: true)
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
                    summaryRow(title: "Apple ID", value: selectedAccountCompactSummary, showsDisclosure: true)
                }
            }
            Divider().padding(.leading, 14)

            summaryRow(title: "签名证书", value: certificateSummary, monospaced: true)
            Divider().padding(.leading, 14)
            summaryRow(title: "有效期", value: expectedValiditySummary)
            Divider().padding(.leading, 14)
            summaryRow(title: "安装通道", value: installChannelSummary)
            Divider().padding(.leading, 14)
            summaryRow(title: "扩展", value: extensionSummary)
        }
        .padding(.horizontal, 14)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func summaryRow(
        title: String,
        value: String,
        monospaced: Bool = false,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: monospaced ? .monospaced : .default))
                .foregroundStyle(Color.sealTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sealTextSecondary.opacity(0.75))
            }
        }
        .frame(minHeight: 42)
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
            ? ((try? BundleIDPolicy.targetBundleIdentifier(for: app)) ?? app.originalBundleIdentifier)
            : targetBundleID
    }

    private var requestedBundleIDForSigning: String? {
        let trimmed = targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var bundleIDValidationError: String? {
        let trimmed = targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return BundleIDPolicy.validationError(for: trimmed)
    }

    private func resetBundleIDDraftIfNeeded() {
        guard targetBundleID.isEmpty else { return }
        targetBundleID = (try? BundleIDPolicy.targetBundleIdentifier(for: app)) ?? app.originalBundleIdentifier
    }

    private var selectedAccount: AppleAccountRecord? {
        viewModel.verifiedAccounts.first { $0.id == selectedAccountID }
    }

    private var selectedAccountCompactSummary: String {
        guard let selectedAccount else { return "请选择" }
        let kind = selectedAccount.isFreeTeam == true ? "Free" : "Developer"
        return "\(viewModelFullEmail(for: selectedAccount)) · \(kind)"
    }

    private func viewModelFullEmail(for account: AppleAccountRecord) -> String {
        account.maskedEmail
    }

    private func accountPickerTitle(_ account: AppleAccountRecord) -> String {
        let kind = account.isFreeTeam == true ? "Free" : "Developer"
        return "\(viewModelFullEmail(for: account)) · \(kind)"
    }

    private var certificateSummary: String {
        guard let selectedAccount else { return "签名时创建" }
        let serial = try? SigningCertificateSelectionPolicy.resolvedSerialNumber(
            for: app,
            account: selectedAccount
        )
        guard let serial, serial.isEmpty == false else { return "签名时创建" }
        return "Seal-\(serial.suffix(8))"
    }

    private var statusText: String {
        AppOperationPresentation(app: app).validity?.detailText ?? "待签名"
    }

    private var expectedValiditySummary: String {
        if let date = app.provisioningProfileExpirationDate ?? app.expiryDate {
            return Self.dateFormatter.string(from: date)
        }
        return "签名后生成"
    }

    private var installChannelSummary: String {
        switch viewModel.signingChannelStatus {
        case .idle: return "未检测"
        case .connecting: return "检测中"
        case .ready: return "已连接"
        case .unavailable: return "不可用"
        }
    }

    private var extensionSummary: String {
        app.extensions.isEmpty ? "无" : "\(app.extensions.count) 个"
    }

    private func primaryActionTitle(for presentation: AppOperationPresentation) -> String {
        selectedAccountID == nil ? "去添加 Apple ID" : presentation.primaryAction
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct BundleIDEditorSheet: View {
    let app: AppRecord
    @Binding var targetBundleID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SealSheetGrabber()
                .frame(maxWidth: .infinity, alignment: .center)
            Text("修改 Bundle ID")
                .font(.system(size: 20, weight: .bold))
            TextField("Bundle ID", text: $targetBundleID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(Color.sealSurfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let error = BundleIDPolicy.validationError(for: targetBundleID) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.sealDanger)
            }
            HStack(spacing: 12) {
                Button("恢复默认") { targetBundleID = app.originalBundleIdentifier }
                    .buttonStyle(.bordered)
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(BundleIDPolicy.validationError(for: targetBundleID) != nil)
            }
        }
        .padding(22)
        .sealSheetBackground()
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

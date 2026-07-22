import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AppSigningSheet: View {
    let app: AppRecord
    @ObservedObject var viewModel: AppsViewModel
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccountID: UUID?
    @State private var targetBundleID = ""
    @State private var displayName = ""
    @State private var selectedIconData: Data?
    @State private var isBundleIDEditorPresented = false
    @State private var isNameEditorPresented = false
    @State private var isIconFileImporterPresented = false
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        Group {
            if viewModel.signingSession?.app.id == app.id {
                SigningProgressView(viewModel: viewModel, onFinish: onFinish)
            } else {
                configuration
            }
        }
        .interactiveDismissDisabled(isRunning)
        .task {
            await viewModel.load(force: true)
            await viewModel.refreshActiveAccountSelection()
            selectDefaultAccount()
            resetDraftsIfNeeded()
        }
        .onChange(of: viewModel.selectableAccounts) { _ in
            selectDefaultAccount()
        }
        .onChange(of: photoPickerItem) { newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   UIImage(data: data) != nil {
                    selectedIconData = data
                }
            }
        }
        .sheet(isPresented: $isBundleIDEditorPresented) {
            BundleIDEditorSheet(targetBundleID: $targetBundleID)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isNameEditorPresented) {
            AppNameEditorSheet(
                originalName: app.name,
                displayName: $displayName
            )
            .presentationDetents([.medium])
        }
        .fileImporter(
            isPresented: $isIconFileImporterPresented,
            allowedContentTypes: [.image]
        ) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), UIImage(data: data) != nil {
                selectedIconData = data
            }
        }
        .alert(item: $viewModel.alertFailure) { failure in
            standardAlert(failure)
        }
    }

    private var configuration: some View {
        let presentation = AppOperationPresentation(app: app)
        return SealDrawer(
            title: presentation.sheetTitle,
            subtitle: isRenewal ? "续签将沿用上次的 Apple ID、Team、Serial 和 Bundle ID" : nil
        ) {
            VStack(spacing: 16) {
                appIdentity(presentation: presentation)
                operationSummaryCard

                if viewModel.hasCycleRenewalCompanions(for: app) {
                    Button("一起续签本周期到期 App") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            viewModel.refreshSealCycle(for: app)
                        }
                    }
                    .sealOutlineAction(cornerRadius: 14)
                }
            }
        } footer: {
            VStack(spacing: 12) {
                Button(primaryActionTitle(for: presentation)) {
                    startSigning(disposition: .signAndInstall)
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(actionDisabled)
                .opacity(actionDisabled ? 0.48 : 1)

                if isRenewal == false {
                    Button("仅签名") {
                        startSigning(disposition: .signOnly)
                    }
                    .sealOutlineAction(cornerRadius: 14)
                    .disabled(actionDisabled)
                    .opacity(actionDisabled ? 0.48 : 1)
                }
            }
        }
    }

    private func startSigning(disposition: AppSigningDisposition) {
        guard let selectedAccountID else {
            viewModel.openSettings(route: .account)
            dismiss()
            return
        }
        Task {
            await viewModel.beginSigning(
                for: app,
                accountID: selectedAccountID,
                requestedBundleIdentifier: requestedBundleIDForSigning,
                displayName: isRenewal ? nil : displayName,
                iconData: isRenewal ? nil : selectedIconData,
                disposition: disposition
            )
        }
    }

    private func appIdentity(presentation: AppOperationPresentation) -> some View {
        HStack(spacing: 14) {
            if isRenewal {
                appIcon(size: 58)
            } else {
                Menu {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("从照片选择", systemImage: "photo")
                    }
                    Button {
                        isIconFileImporterPresented = true
                    } label: {
                        Label("从文件选择", systemImage: "folder")
                    }
                    Button {
                        selectedIconData = nil
                    } label: {
                        Label("使用原图", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    appIcon(size: 58)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.sealAccent)
                                .background(.background, in: Circle())
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改 App 图标")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(displayNameValue)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("v\(app.version) · \(Self.fileSizeFormatter.string(fromByteCount: app.size))")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let validity = presentation.validity {
                Text(validity.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(validityColor(validity.tone))
                    .lineLimit(1)
            }
        }
    }

    private var operationSummaryCard: some View {
        VStack(spacing: 0) {
            if isRenewal == false {
                Button { isNameEditorPresented = true } label: {
                    summaryRow(title: "App 名称", value: displayNameValue, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 14)
            }

            if BundleIDPolicy.isEditable(app) {
                Button { isBundleIDEditorPresented = true } label: {
                    bundleIDSummaryRow(showsDisclosure: true)
                }
                .buttonStyle(.plain)
            } else {
                bundleIDSummaryRow(showsDisclosure: false)
            }
            Divider().padding(.leading, 14)

            if isRenewal {
                summaryRow(title: "Apple ID", value: selectedAccountCompactSummary)
            } else if viewModel.selectableAccounts.isEmpty {
                Button {
                    viewModel.openSettings(route: .account)
                    dismiss()
                } label: {
                    summaryRow(title: "Apple ID", value: "去添加", showsDisclosure: true)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(viewModel.selectableAccounts) { account in
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

            summaryRow(title: "Team", value: selectedAccount?.teamID ?? "—", monospaced: true)
            Divider().padding(.leading, 14)
            summaryRow(title: "Serial", value: certificateSummary, monospaced: true)
            Divider().padding(.leading, 14)
            summaryRow(title: "有效期", value: expectedValiditySummary)
            Divider().padding(.leading, 14)
            summaryRow(title: "LocalDevVPN", value: installChannelSummary)
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

    private func bundleIDSummaryRow(showsDisclosure: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Bundle ID")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 72, alignment: .leading)
            Spacer(minLength: 8)
            BundleIdentifierText(displayBundleIdentifier)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary.opacity(0.75))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bundle ID，\(displayBundleIdentifier)")
    }

    private func summaryRow(
        title: String,
        value: String,
        monospaced: Bool = false,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(Color.sealTextSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary.opacity(0.75))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        Group {
            if let data = selectedIconData ?? viewModel.displayIconData(for: app),
               let image = UIImage(data: data) {
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

    private var displayNameValue: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? app.name : trimmed
    }

    private var displayBundleIdentifier: String {
        targetBundleID.isEmpty
            ? ((try? BundleIDPolicy.targetBundleIdentifier(for: app)) ?? app.originalBundleIdentifier)
            : targetBundleID
    }

    private var requestedBundleIDForSigning: String? {
        guard isRenewal == false else { return nil }
        let trimmed = targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var bundleIDValidationError: String? {
        guard isRenewal == false else { return nil }
        return BundleIDPolicy.validationError(for: targetBundleID)
    }

    private var actionDisabled: Bool {
        selectedAccountID == nil || bundleIDValidationError != nil
    }

    private func resetDraftsIfNeeded() {
        if targetBundleID.isEmpty {
            targetBundleID = viewModel.rememberedBundleIdentifier(for: app)
                ?? ((try? BundleIDPolicy.targetBundleIdentifier(for: app)) ?? app.originalBundleIdentifier)
        }
        if displayName.isEmpty {
            displayName = viewModel.displayName(for: app)
        }
        if selectedIconData == nil {
            selectedIconData = viewModel.customization(for: app)?.iconData
        }
    }

    private var selectedAccount: AppleAccountRecord? {
        if isRenewal, let accountID = app.accountID {
            return viewModel.accounts.first { $0.id == accountID }
        }
        return viewModel.selectableAccounts.first { $0.id == selectedAccountID }
    }

    private var selectedAccountCompactSummary: String {
        guard let selectedAccount else { return "请选择" }
        let kind = selectedAccount.isFreeTeam == true ? "Free" : "Developer"
        let status = selectedAccount.status == .verified ? "" : " · 需验证"
        return "\(selectedAccount.maskedEmail) · \(kind)\(status)"
    }

    private func accountPickerTitle(_ account: AppleAccountRecord) -> String {
        let kind = account.isFreeTeam == true ? "Free" : "Developer"
        let status = account.status == .verified ? "" : " · 需验证"
        return "\(account.maskedEmail) · \(kind)\(status)"
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

    private var isRenewal: Bool {
        app.state == .installed || app.isSeal
    }

    private var isRunning: Bool {
        if case .running = viewModel.signingSession?.status { return true }
        return false
    }

    private func selectDefaultAccount() {
        let accounts = viewModel.selectableAccounts
        if isRenewal {
            selectedAccountID = app.accountID
            return
        }
        guard selectedAccountID == nil else { return }
        if let activeAccountID = viewModel.activeAccountID,
           accounts.contains(where: { $0.id == activeAccountID }) {
            selectedAccountID = activeAccountID
        } else {
            selectedAccountID = accounts.first?.id
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
    @Binding var targetBundleID: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        SealDrawer(title: "修改 Bundle ID") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Bundle ID", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(
                        Color.sealSurfaceElevated,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .textSelection(.enabled)

                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.sealDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .sealOutlineAction(cornerRadius: 14)
                Button("保存") {
                    targetBundleID = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(validationError != nil)
            }
        }
        .onAppear { draft = targetBundleID }
    }

    private var validationError: String? {
        BundleIDPolicy.validationError(for: draft)
    }
}

private struct AppNameEditorSheet: View {
    let originalName: String
    @Binding var displayName: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        SealDrawer(title: "修改 App 名称") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("App 名称", text: $draft)
                    .textInputAutocapitalization(.never)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(
                        Color.sealSurfaceElevated,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                Text("主屏幕可能会截断过长的名称")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
            }
        } footer: {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("取消") { dismiss() }
                        .sealOutlineAction(cornerRadius: 14)
                    Button("保存") {
                        displayName = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .sealPrimaryAction(cornerRadius: 14)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("使用原名称") {
                    displayName = originalName
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sealAccent)
            }
        }
        .onAppear { draft = displayName }
    }
}

struct BundleIdentifierText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        if value.lowercased().hasSuffix(".seal") {
            let base = String(value.dropLast(5))
            HStack(spacing: 0) {
                Text(base).foregroundStyle(Color.sealTextSecondary)
                Text(".seal").foregroundStyle(Color.sealAccent)
            }
        } else {
            Text(value).foregroundStyle(Color.sealTextSecondary)
        }
    }
}

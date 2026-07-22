import SwiftUI
import UIKit

struct SignedIPAActionSheet: View {
    let app: AppRecord
    @ObservedObject var viewModel: AppsViewModel
    let onInstalled: () -> Void
    let onDeleted: () -> Void
    let onResign: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false
    @State private var showsExportExplanation = false
    @State private var shareItem: SignedIPAExportItem?

    var body: some View {
        SealDrawer(
            title: "已签名 IPA",
            subtitle: viewModel.displayName(for: app)
        ) {
            VStack(spacing: 16) {
                identity
                detailsCard
                if let failure = viewModel.signedIPAOperationFailure {
                    failureCard(failure)
                }
            }
        } footer: {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(primaryTitle) { performPrimaryAction() }
                        .sealPrimaryAction(cornerRadius: 14)
                        .disabled(isBusy)

                    Button("导出") { showsExportExplanation = true }
                        .sealOutlineAction(cornerRadius: 14)
                        .disabled(isBusy || isSignedIPAUnavailable)
                }

                Button("删除", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.sealDanger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isBusy)
            }
        }
        .interactiveDismissDisabled(isBusy)
        .alert("删除已签名 IPA？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    if await viewModel.deleteSignedIPA(app) {
                        onDeleted()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("只会删除本机保存的签名文件，不会卸载设备上已经安装的 App。")
        }
        .confirmationDialog(
            "导出已签名 IPA",
            isPresented: $showsExportExplanation,
            titleVisibility: .visible
        ) {
            Button("继续导出") {
                Task {
                    if let url = await viewModel.prepareSignedIPAExport(app) {
                        shareItem = SignedIPAExportItem(url: url)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此 IPA 只能安装到当前描述文件包含的设备。发送给其他人不代表对方设备一定可以安装。")
        }
        .sheet(item: $shareItem, onDismiss: viewModel.clearSignedIPAExport) { item in
            ShareActivityView(items: [item.url as Any])
                .presentationDetents([.medium, .large])
                .compatiblePresentationCornerRadius(30)
        }
        .onDisappear {
            viewModel.signedIPAOperationFailure = nil
            viewModel.clearSignedIPAExport()
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(viewModel.displayName(for: app))
                        .font(.headline)
                        .lineLimit(1)
                    Text("v\(app.version)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.sealTextSecondary)
                }
                BundleIdentifierText(bundleIdentifier)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 8)
            Text(validityText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(validityColor)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Bundle ID", bundleIdentifier, monospaced: true)
            Divider().padding(.leading, 14)
            detailRow("Team", app.signingTeamID ?? "—", monospaced: true)
            Divider().padding(.leading, 14)
            detailRow("Serial", serialText, monospaced: true)
            Divider().padding(.leading, 14)
            detailRow("签名时间", signingTime)
            Divider().padding(.leading, 14)
            detailRow("到期时间", expiryTime)
            Divider().padding(.leading, 14)
            detailRow("文件大小", signedIPAByteCount.formatted(.byteCount(style: .file)))
        }
        .padding(.horizontal, 14)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func detailRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .contextMenu {
                    Button("复制") {
                        SealPasteboard.copy(value, announcement: "\(title)已复制")
                    }
                }
        }
        .frame(minHeight: 44)
    }

    private func failureCard(_ failure: ImportFailure) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(failure.title)
                .font(.headline)
                .foregroundStyle(Color.sealDanger)
            Text(failure.userReason)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sealDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var appIcon: some View {
        Group {
            if let data = viewModel.displayIconData(for: app), let image = UIImage(data: data) {
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
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var isBusy: Bool {
        viewModel.signedIPAOperationAppID == app.id
    }

    private var isExpired: Bool {
        guard let expiry = app.provisioningProfileExpirationDate ?? app.expiryDate else { return false }
        return expiry <= Date()
    }

    private var isSignedIPAUnavailable: Bool {
        switch viewModel.signedIPAFileStatus(for: app) {
        case .missing, .invalid: return true
        case .available: return false
        case .none: return app.signedIPARelativePath == nil
        }
    }

    private var signedIPAByteCount: Int64 {
        if case .available(let byteCount) = viewModel.signedIPAFileStatus(for: app) {
            return byteCount
        }
        return app.size
    }

    private var primaryTitle: String {
        if isBusy { return "处理中…" }
        return isExpired || isSignedIPAUnavailable ? "重新签名" : "安装"
    }

    private func performPrimaryAction() {
        if isExpired || isSignedIPAUnavailable {
            onResign()
            dismiss()
            return
        }
        Task {
            if await viewModel.installSignedIPA(app) {
                onInstalled()
                dismiss()
            }
        }
    }

    private var bundleIdentifier: String {
        app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier
    }

    private var validityText: String {
        AppValidityFormatter.text(
            expiryDate: app.provisioningProfileExpirationDate ?? app.expiryDate,
            fallback: "已签名"
        )
    }

    private var validityColor: Color {
        switch AppValidityFormatter.presentation(
            expiryDate: app.provisioningProfileExpirationDate ?? app.expiryDate
        )?.tone {
        case .danger: return .sealDanger
        case .warning: return .sealWarning
        case .success, .neutral, nil: return .sealTextSecondary
        }
    }

    private var serialText: String {
        guard let serial = app.certificateSerialNumber, serial.isEmpty == false else { return "—" }
        return "Seal-\(serial.suffix(8))"
    }

    private var signingTime: String {
        guard let date = app.lastSignedAt else { return "—" }
        return Self.dateTimeFormatter.string(from: date)
    }

    private var expiryTime: String {
        guard let date = app.provisioningProfileExpirationDate ?? app.expiryDate else { return "—" }
        return Self.dateTimeFormatter.string(from: date)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct SignedIPAExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

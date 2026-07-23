import SwiftUI

struct InstalledAppActionSheet: View {
    let app: AppRecord
    @ObservedObject var viewModel: AppsViewModel
    let onRenew: () -> Void
    let onShowDetail: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SealDrawer(title: app.displayName) {
            VStack(alignment: .leading, spacing: 10) {
                if let validity = AppOperationPresentation(app: app).validity {
                    Text(validity.text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(validityColor(validity.tone))
                }
                Text(app.mappedBundleIdentifier ?? app.originalBundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.bottom, 12)
        } footer: {
            VStack(spacing: 10) {
                Button("立即续签") {
                    dismiss()
                    onRenew()
                }
                .sealPrimaryAction(cornerRadius: 14)

                Button("重新安装") {
                    Task { @MainActor in
                        if await viewModel.installSignedArtifact(app) {
                            dismiss()
                        }
                    }
                }
                .sealOutlineAction(cornerRadius: 14)
                .disabled(app.hasSignedArtifact == false || viewModel.installingSignedAppID != nil)

                Button("查看详情") {
                    dismiss()
                    onShowDetail()
                }
                .frame(maxWidth: .infinity, minHeight: 44)

                Button("取消") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(Color.sealTextSecondary)
            }
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
}

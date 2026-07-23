import SwiftUI
import UIKit

struct SignedAppActionSheet: View {
    let app: AppRecord
    @ObservedObject var viewModel: AppsViewModel
    let onInstalled: () -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var shareURL: URL?
    @State private var isPreparingExport = false

    var body: some View {
        SealDrawer(title: "已签名 IPA") {
            VStack(alignment: .leading, spacing: 14) {
                Text(app.displayName)
                    .font(.title3.weight(.semibold))
                Text(app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let status = app.signedArtifactStatus {
                    Label(status.title, systemImage: status == .available ? "checkmark.seal" : "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("导出的 IPA 只能安装到当前描述文件包含的设备。发送给其他人不代表对方设备一定可以安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 12)
        } footer: {
            VStack(spacing: 10) {
                Button {
                    Task { @MainActor in
                        let installed = await viewModel.installSignedArtifact(app)
                        if installed {
                            dismiss()
                            onInstalled()
                        }
                    }
                } label: {
                    if viewModel.installingSignedAppID == app.id {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("安装")
                    }
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(viewModel.installingSignedAppID != nil)

                Button {
                    isPreparingExport = true
                    Task { @MainActor in
                        shareURL = await viewModel.exportSignedIPAURL(for: app)
                        isPreparingExport = false
                    }
                } label: {
                    if isPreparingExport { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("导出") }
                }
                .sealOutlineAction(cornerRadius: 14)
                .disabled(isPreparingExport)

                Button("删除", role: .destructive) { confirmsDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("取消") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(Color.sealTextSecondary)
            }
        }
        .alert("删除已签名 IPA？", isPresented: $confirmsDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { @MainActor in
                    if await viewModel.deleteSignedArtifact(app) {
                        dismiss()
                        onDeleted()
                    }
                }
            }
        } message: {
            Text("只会删除本机保存的签名文件，不会卸载设备上已经安装的 App。")
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if $0 == false { shareURL = nil } }
        )) {
            if let shareURL {
                SealActivityView(items: [shareURL])
            }
        }
    }
}

private struct SealActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

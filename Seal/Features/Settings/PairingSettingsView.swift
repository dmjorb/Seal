import SwiftUI
import UniformTypeIdentifiers

struct PairingSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    @State private var confirmsRemoval = false
    private let pairingGuideURL = URL(string: "https://docs.sidestore.io/docs/advanced/pairing-file")!

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                hero
                if let pairing = viewModel.pairingRecord { details(pairing) } else { emptyDetails }
                actions
            }
            .padding(20)
        }
        .navigationTitle("设备配对")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $viewModel.isPairingImporterPresented, allowedContentTypes: [.pairingRecord, .propertyListDocument, .xml]) { result in
            switch result {
            case .success(let url): Task { await viewModel.importPairingFile(url) }
            case .failure(let error): viewModel.handlePairingImporterFailure(error)
            }
        }
        .confirmationDialog(
            "移除配对文件？",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("移除配对文件", role: .destructive) {
                Task { await viewModel.removePairingFile() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除后将无法安装或续签应用，重新导入即可恢复。")
        }
        .sealScreenBackground(.secondary)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.pairingRecord == nil ? "link.badge.plus" : "checkmark.circle.fill")
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(viewModel.pairingRecord == nil ? Color.sealWarning : Color.sealSuccess)
            Text(viewModel.pairingRecord == nil ? "需要导入配对文件" : "配对文件有效")
                .font(.title2.weight(.semibold))
            Text(viewModel.pairingRecord == nil ? "导入当前 iPhone 的配对文件后即可安装和续签。" : "当前设备已完成配对")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private func details(_ pairing: PairingRecord) -> some View {
        VStack(spacing: 0) {
            detailRow("配对类型", pairing.isRemotePairing ? "远程配对" : "本机配对")
            Divider()
            detailRow("设备标识", pairing.deviceIdentifier ?? "已导入")
            Divider()
            detailRow("文件状态", "有效", valueColor: .sealSuccess)
        }
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var emptyDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配对文件用于连接本机安装通道。")
                .font(.headline)
            Text("不会上传到服务器，仅保存在这台设备。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(viewModel.pairingRecord == nil ? "导入配对文件" : "重新导入配对文件") {
                viewModel.isPairingImporterPresented = true
            }
            .sealPrimaryAction(cornerRadius: 12)

            Button("获取配对文件") { openURL(pairingGuideURL) }
                .sealOutlineAction(cornerRadius: 12)

            if viewModel.pairingRecord != nil {
                Button("移除配对文件") { confirmsRemoval = true }
                    .foregroundStyle(Color.sealDanger)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, valueColor: Color = .secondary) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minHeight: 54)
    }
}

private extension UTType {
    static let pairingRecord = UTType(filenameExtension: "mobiledevicepairing") ?? .data
    static let propertyListDocument = UTType(filenameExtension: "plist") ?? .data
}

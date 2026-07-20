import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PairingSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var confirmsRemoval = false

    private let directDownloadURL = "https://github.com/jkcoxson/idevice_pair/releases/latest/download/idevice_pair--windows-x86_64.exe"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                hero
                if let pairing = viewModel.pairingRecord {
                    details(pairing)
                } else {
                    emptyDetails
                }
                acquisitionGuide
                actions
            }
            .padding(20)
        }
        .navigationTitle("设备")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $viewModel.isPairingImporterPresented,
            allowedContentTypes: [.pairingRecord, .propertyListDocument, .xml]
        ) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.importPairingFile(url) }
            case .failure(let error):
                viewModel.handlePairingImporterFailure(error)
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
            Text("移除后将无法安装或续签应用，重新导入当前 iPhone 的 .plist 即可恢复。")
        }
        .alert(item: $viewModel.alertFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text("\(failure.reason)\n\(failure.code)"),
                dismissButton: .default(Text(failure.recovery))
            )
        }
        .sealScreenBackground(.secondary)
    }

    private var hero: some View {
        let verified = viewModel.pairingRecord?.isVerifiedForCurrentDevice == true
        return VStack(spacing: 12) {
            Image(systemName: verified ? "checkmark.circle.fill" : "iphone.badge.exclamationmark")
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(verified ? Color.sealSuccess : Color.sealWarning)
            Text(viewModel.pairingRecord?.validationStatus.title ?? "未导入配对文件")
                .font(.title2.weight(.semibold))
            Text(
                verified
                    ? "配对文件已通过当前连接 iPhone 的真实 UDID 验证。"
                    : "导入文件后，Seal 会通过安装通道读取当前设备 UDID 并验证是否匹配。"
            )
            .font(.subheadline)
            .foregroundStyle(Color.sealTextSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(cornerRadius: 24)
    }

    private func details(_ pairing: PairingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("配对方式", pairing.isRemotePairing ? "远程配对文件" : "电脑配对文件")
            Divider()
            detailRow("验证状态", pairing.validationStatus.title)

            if let fileUDID = pairing.deviceIdentifier, fileUDID.isEmpty == false {
                Divider()
                FullIdentifierRow(title: "文件内设备 UDID", value: fileUDID)
            }
            if let connectedUDID = pairing.validatedDeviceIdentifier,
               connectedUDID.isEmpty == false {
                Divider()
                FullIdentifierRow(title: "当前连接设备 UDID", value: connectedUDID)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 18)
    }

    private var emptyDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("需要当前 iPhone 的 .plist 配对文件")
                .font(.headline)
            Text("配对文件只保存在本机。Seal 不会把配对证书或私钥上传到服务器。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 18)
    }

    private var acquisitionGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("获取配对文件")
                .font(.headline)
            Text("在 Windows 电脑浏览器打开下载地址，运行 idevice_pair，连接并信任当前 iPhone，导出 .plist 配对文件，再传到手机导入 Seal。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FullIdentifierRow(
                title: "idevice_pair Windows 直接下载地址",
                value: directDownloadURL
            )
            Button {
                UIPasteboard.general.string = directDownloadURL
            } label: {
                Label("复制电脑下载地址", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .sealOutlineAction(cornerRadius: 12)
        }
        .padding(18)
        .glassSurface(cornerRadius: 18)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(viewModel.pairingRecord == nil ? "导入 .plist 配对文件" : "重新导入 .plist 配对文件") {
                viewModel.isPairingImporterPresented = true
            }
            .sealPrimaryAction(cornerRadius: 12)

            if viewModel.pairingRecord != nil {
                Button("移除配对文件") { confirmsRemoval = true }
                    .foregroundStyle(Color.sealDanger)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 54)
    }
}

private extension UTType {
    static let pairingRecord = UTType(filenameExtension: "mobiledevicepairing") ?? .data
    static let propertyListDocument = UTType(filenameExtension: "plist") ?? .data
}

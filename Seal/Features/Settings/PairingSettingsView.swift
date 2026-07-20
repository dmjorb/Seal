import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PairingSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var confirmsRemoval = false
    @State private var copiedDownloadLink = false

    private let directDownloadURL = "https://github.com/jkcoxson/idevice_pair/releases/latest/download/idevice_pair--windows-x86_64.exe"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                hero
                if let pairing = viewModel.pairingRecord, pairing.isVerifiedForCurrentDevice {
                    details(pairing)
                } else {
                    acquisitionGuide
                }
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
        .alert("移除配对文件？", isPresented: $confirmsRemoval) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                Task { await viewModel.removePairingFile() }
            }
        } message: {
            Text("移除后将无法安装或续签应用，重新导入当前 iPhone 的配对文件即可恢复。")
        }
        .alert("复制成功", isPresented: $copiedDownloadLink) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请用电脑浏览器打开下载。")
        }
        .alert(item: $viewModel.alertFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.userMessage),
                dismissButton: .default(Text(failure.recovery))
            )
        }
        .sealScreenBackground()
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: heroIcon)
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(heroColor)
            Text(heroTitle)
                .font(.title2.weight(.semibold))
            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(cornerRadius: 24)
    }

    private func details(_ pairing: PairingRecord) -> some View {
        VStack(spacing: 0) {
            detailRow("配对类型", pairing.isRemotePairing ? "远程配对" : "本机配对")
            Divider()
            detailRow("设备标识", deviceIdentifierText(pairing))
            Divider()
            detailRow("文件状态", "有效")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 18)
    }

    private var acquisitionGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何获取配对文件")
                .font(.headline)
            Text("在电脑上下载 idevice pair 工具。\n连接当前 iPhone 后，通过 CoreDeviceProxy 生成 RPPairing 文件。\n生成完成后，将该文件导入 Seal，即可用于安装和续签应用。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 18)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(importButtonTitle) {
                viewModel.isPairingImporterPresented = true
            }
            .sealPrimaryAction(cornerRadius: 12)

            if shouldShowDownloadLink {
                Button("获取下载链接") {
                    UIPasteboard.general.string = directDownloadURL
                    copiedDownloadLink = true
                }
                .sealOutlineAction(cornerRadius: 12)
            }

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

    private var heroIcon: String {
        guard let pairing = viewModel.pairingRecord else { return "iphone.badge.exclamationmark" }
        return pairing.isVerifiedForCurrentDevice ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var heroColor: Color {
        guard let pairing = viewModel.pairingRecord else { return .sealWarning }
        return pairing.isVerifiedForCurrentDevice ? .sealSuccess : .sealDanger
    }

    private var heroTitle: String {
        guard let pairing = viewModel.pairingRecord else { return "需要导入配对文件" }
        return pairing.isVerifiedForCurrentDevice ? "设备已配对" : "配对文件不可用"
    }

    private var heroSubtitle: String {
        guard let pairing = viewModel.pairingRecord else {
            return "请先在电脑上生成当前 iPhone 的 RPPairing 文件，然后导入 Seal。"
        }
        return pairing.isVerifiedForCurrentDevice
            ? "可以安装和续签应用"
            : "请重新生成当前 iPhone 的 RPPairing 文件后再导入。"
    }

    private var importButtonTitle: String {
        viewModel.pairingRecord == nil ? "导入配对文件" : "重新导入配对文件"
    }

    private var shouldShowDownloadLink: Bool {
        guard let pairing = viewModel.pairingRecord else { return true }
        return pairing.isVerifiedForCurrentDevice == false
    }

    private func deviceIdentifierText(_ pairing: PairingRecord) -> String {
        if let id = pairing.validatedDeviceIdentifier, id.isEmpty == false { return id }
        if let id = pairing.deviceIdentifier, id.isEmpty == false { return id }
        return "完整 UDID"
    }
}

private extension UTType {
    static let pairingRecord = UTType(filenameExtension: "mobiledevicepairing") ?? .data
    static let propertyListDocument = UTType(filenameExtension: "plist") ?? .data
}

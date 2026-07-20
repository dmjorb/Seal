import SwiftUI

struct SigningCertificateSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]

    @State private var certificatePendingReset: AppleAccountRecord?
    @State private var certificatePendingReplacement: ApplePortalCertificateSnapshot?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                accountCard

                Text("签名证书")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                    .padding(.leading, 8)

                certificateContent
            }
            .padding(20)
        }
        .navigationTitle("签名证书")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除本机证书？", isPresented: Binding(
            get: { certificatePendingReset != nil },
            set: { if !$0 { certificatePendingReset = nil } }
        )) {
            Button("取消", role: .cancel) { certificatePendingReset = nil }
            Button("清除", role: .destructive) {
                guard let account = certificatePendingReset else { return }
                Task { await viewModel.resetCertificate(for: account) }
                certificatePendingReset = nil
            }
        } message: {
            Text("这只会清除 Seal 本机保存的 P12 和私钥，不会撤销 Apple 端证书。")
        }
        .alert("撤销并创建本机证书？", isPresented: Binding(
            get: { certificatePendingReplacement != nil },
            set: { if !$0 { certificatePendingReplacement = nil } }
        )) {
            Button("取消", role: .cancel) { certificatePendingReplacement = nil }
            Button("撤销并创建", role: .destructive) {
                guard let account = activeAccount, let certificate = certificatePendingReplacement else { return }
                let serial = certificate.serialNumber
                certificatePendingReplacement = nil
                Task { await viewModel.revokeCertificateAndCreateLocal(serialNumber: serial, for: account) }
            }
        } message: {
            Text("请选择一张旧证书撤销后，Seal 将重新创建本机证书。")
        }
        .alert(item: $viewModel.alertFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.userMessage),
                dismissButton: .default(Text(failure.recovery))
            )
        }
        .task { await viewModel.load(force: true) }
        .sealScreenBackground()
    }

    private var activeAccount: AppleAccountRecord? { viewModel.activeAccount }

    @ViewBuilder
    private var accountCard: some View {
        VStack(spacing: 0) {
            if let account = activeAccount {
                detailRow("Apple ID", viewModel.fullEmail(for: account))
                Divider()
                detailRow("Team", account.teamName)
                Divider()
                detailRow("Team ID", account.teamID)
            } else {
                Text("请先选择已验证的 Apple ID")
                    .foregroundStyle(Color.sealTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 24)
    }

    @ViewBuilder
    private var certificateContent: some View {
        if let account = activeAccount {
            if let serial = account.certificateSerialNumber, serial.isEmpty == false {
                localCertificateCard(account: account, serial: serial)
            } else {
                missingCertificateCard(account)
                quotaResolutionCard(account)
            }
        } else {
            noAccountCard
        }
    }

    private func localCertificateCard(account: AppleAccountRecord, serial: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Seal-\(serial.suffix(8))")
                    .font(.title3.weight(.semibold))
                Text(account.teamName)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                Text("Serial：\(serial)")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("本机可用")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sealSuccess)
            }

            Divider()

            Button("重新验证证书") {
                Task {
                    await viewModel.load(force: true)
                    await viewModel.refreshCertificateInventory(for: account, force: true)
                }
            }
            .sealOutlineAction(cornerRadius: 12)
            .disabled(viewModel.isCertificateOperationRunning)

            Button("清除本机证书") { certificatePendingReset = account }
                .foregroundStyle(Color.sealDanger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(viewModel.isCertificateOperationRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private func missingCertificateCard(_ account: AppleAccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前没有本机可用证书")
                .font(.headline)
            Text("首次签名时将自动创建。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
            Button(viewModel.isCertificateOperationRunning ? "正在创建…" : "立即创建本机证书") {
                Task { await viewModel.createLocalCertificate(for: account) }
            }
            .sealPrimaryAction(cornerRadius: 12)
            .disabled(viewModel.isCertificateOperationRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 20)
    }

    @ViewBuilder
    private func quotaResolutionCard(_ account: AppleAccountRecord) -> some View {
        let certificates = viewModel.certificateInventory(for: account.id)?.certificates ?? []
        if certificates.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text("无法创建本机证书时")
                    .font(.headline)
                Text("如果 Apple 提示开发证书数量已达到上限，请选择一张旧证书撤销后重新创建。")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                ForEach(certificates) { certificate in
                    Button {
                        certificatePendingReplacement = certificate
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(certificate.displayName)
                                .font(.body.weight(.semibold))
                            Text("Serial：\(certificate.serialNumber)")
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.sealTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var noAccountCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Color.sealWarning)
            Text("未选择 Apple ID")
                .font(.headline)
            Text("返回 Apple ID 页面，选择一个已验证账号。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassSurface(cornerRadius: 24)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 15)
    }
}

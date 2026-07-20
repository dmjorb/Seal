import SwiftUI

struct SigningCertificateSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]

    @State private var certificatePendingReset: AppleAccountRecord?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                accountCard

                Text("签名证书")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                    .padding(.leading, 8)

                certificateContent

                if let account = activeAccount,
                   account.certificateSerialNumber != nil {
                    resetCard(account)
                }
            }
            .padding(20)
        }
        .navigationTitle("签名证书")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "清除本地证书？",
            isPresented: Binding(
                get: { certificatePendingReset != nil },
                set: { if !$0 { certificatePendingReset = nil } }
            ),
            titleVisibility: .visible,
            presenting: certificatePendingReset
        ) { account in
            Button("清除本地证书", role: .destructive) {
                Task { await viewModel.resetCertificate(for: account) }
                certificatePendingReset = nil
            }
            Button("取消", role: .cancel) { certificatePendingReset = nil }
        } message: { account in
            let count = boundAppCount(for: account)
            Text(
                count == 0
                    ? "这会删除 Seal 本地保存的 P12 和私钥。Apple 账号中的证书记录不会被自动撤销；下次首次签名时会重新申请 Seal 证书。"
                    : "这会删除 Seal 本地保存的 P12 和私钥。该证书已用于 \(count) 个应用；这些应用续签时必须明确选择“更换证书并重试”。Apple 账号中的证书记录不会被自动撤销。"
            )
        }
        .task {
            await viewModel.load(force: true)
            if let account = activeAccount {
                await viewModel.refreshCertificateInventory(for: account, force: true)
            }
        }
        .onChange(of: viewModel.activeAccountID) { _ in
            guard let account = activeAccount else { return }
            Task {
                await viewModel.refreshCertificateInventory(for: account, force: true)
            }
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

    private var activeAccount: AppleAccountRecord? {
        viewModel.activeAccount
    }

    private var activeAccountEmail: String {
        guard let activeAccount else { return "请先选择" }
        return viewModel.fullEmail(for: activeAccount)
    }

    private var inventory: ApplePortalInventory? {
        guard let account = activeAccount else { return nil }
        return viewModel.certificateInventory(for: account.id)
    }

    private var accountCard: some View {
        VStack(spacing: 0) {
            detailRow("Apple ID", activeAccountEmail)
            Divider()
            detailRow("Team ID", activeAccount?.teamID ?? "—")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 24)
    }

    @ViewBuilder
    private var certificateContent: some View {
        if let account = activeAccount {
            if viewModel.isCertificateInventoryLoading(accountID: account.id), inventory == nil {
                loadingCard
            } else if let failure = viewModel.certificateInventoryFailure(for: account.id),
                      inventory == nil {
                failureCard(failure, account: account)
            } else if let certificates = inventory?.certificates,
                      certificates.isEmpty == false {
                certificatesCard(certificates, account: account)
            } else {
                emptyCertificateCard(account)
            }
        } else {
            noAccountCard
        }
    }

    private func certificatesCard(
        _ certificates: [ApplePortalCertificateSnapshot],
        account: AppleAccountRecord
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(certificates.enumerated()), id: \.element.id) { index, certificate in
                certificateRow(certificate, account: account)
                if index < certificates.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 24)
    }

    private func certificateRow(
        _ certificate: ApplePortalCertificateSnapshot,
        account: AppleAccountRecord
    ) -> some View {
        let selected = account.selectedCertificateSerialNumber == certificate.serialNumber
        return Button {
            guard certificate.hasLocalPrivateKey else { return }
            Task {
                await viewModel.selectCertificate(
                    serialNumber: certificate.serialNumber,
                    for: account
                )
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        certificate.hasLocalPrivateKey
                            ? Color.sealAccent
                            : Color.sealTextSecondary.opacity(0.45)
                    )
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(certificate.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if selected {
                            Text("当前使用")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.sealAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.sealAccent.opacity(0.10), in: Capsule())
                        }
                    }
                    Text("Apple Development")
                        .font(.caption)
                        .foregroundStyle(Color.sealTextSecondary)
                    Text("Serial：\(abbreviated(certificate.serialNumber))")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.sealTextSecondary)
                    Text(
                        certificate.hasLocalPrivateKey
                            ? "本机可用"
                            : "非本机创建，无本地私钥，不可用"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        certificate.hasLocalPrivateKey
                            ? Color.sealSuccess
                            : Color.sealTextSecondary
                    )
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(certificate.hasLocalPrivateKey == false)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("正在读取当前 Apple ID 的证书")
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassSurface(cornerRadius: 24)
    }

    private func failureCard(
        _ failure: ImportFailure,
        account: AppleAccountRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("证书读取失败")
                .font(.headline)
            Text(failure.reason)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
            Button("重新同步") {
                Task {
                    await viewModel.refreshCertificateInventory(for: account, force: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private func emptyCertificateCard(_ account: AppleAccountRecord) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "seal")
                .font(.system(size: 34))
                .foregroundStyle(Color.sealTextSecondary)
            Text("暂无签名证书")
                .font(.headline)
            Text("首次签名 IPA 时，Seal 会在本机生成私钥并向 Apple 申请 Seal 证书；成功后自动设为当前证书。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
            Button("重新同步") {
                Task {
                    await viewModel.refreshCertificateInventory(for: account, force: true)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassSurface(cornerRadius: 24)
    }

    private var noAccountCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Color.sealWarning)
            Text("未选择 Apple ID")
                .font(.headline)
            Text("返回设置中的 Apple ID 页面，选择一个已验证账号。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassSurface(cornerRadius: 24)
    }


    private func boundAppCount(for account: AppleAccountRecord) -> Int {
        relatedApps.filter { app in
            guard app.accountID == account.id else { return false }
            guard let localSerial = account.certificateSerialNumber else {
                return false
            }
            return app.certificateSerialNumber == nil
                || app.certificateSerialNumber == localSerial
        }.count
    }

    private func resetCard(_ account: AppleAccountRecord) -> some View {
        Button(role: .destructive) {
            certificatePendingReset = account
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .frame(width: 30)
                Text("清除本地证书")
                Spacer()
            }
            .foregroundStyle(Color.sealDanger)
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: 18)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(Color.sealTextSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(6))"
    }
}

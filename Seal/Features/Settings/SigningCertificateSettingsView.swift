import SwiftUI

struct SigningCertificateSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]
    @State private var certificatePendingReset: AppleAccountRecord?
    @State private var certificateDetailAccount: AppleAccountRecord?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                hero

                Text("个人证书")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                    .padding(.leading, 8)

                VStack(spacing: 0) {
                    if verifiedAccounts.isEmpty {
                        certificateRow(
                            title: "Apple Development",
                            subtitle: "等待 Apple ID",
                            status: "未创建",
                            color: Color.sealTextSecondary,
                            account: nil
                        )
                    } else {
                        ForEach(Array(verifiedAccounts.enumerated()), id: \.element.id) { index, account in
                            certificateRow(
                                title: "Apple Development",
                                subtitle: account.maskedEmail,
                                status: account.certificateSerialNumber == nil ? "签名时创建" : "可用",
                                color: Color.sealSuccess,
                                account: account
                            )
                            if index < verifiedAccounts.count - 1 {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
                }

                noteCard
            }
            .padding(20)
        }
        .navigationTitle("签名证书")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $certificateDetailAccount) { account in
            AppleAccountDetailView(
                account: account,
                relatedApps: relatedApps.filter { $0.accountID == account.id },
                viewModel: viewModel
            )
        }
        .confirmationDialog(
            "清除本地证书缓存？",
            isPresented: Binding(
                get: { certificatePendingReset != nil },
                set: { if !$0 { certificatePendingReset = nil } }
            ),
            titleVisibility: .visible,
            presenting: certificatePendingReset
        ) { account in
            Button("清除并重新申请", role: .destructive) {
                Task { await viewModel.resetCertificate(for: account) }
                certificatePendingReset = nil
            }
            Button("取消", role: .cancel) { certificatePendingReset = nil }
        } message: { _ in
            Text("这会清除 Seal 本地保存的 P12、证书序列号和证书机器标识。下次签名会重新向 Apple 申请证书；如果 Apple ID 的证书额度已满，签名失败页会提供更换证书并重试。")
        }
        .task { await viewModel.load(force: true) }
        .sealScreenBackground(.secondary)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: hasVerifiedAccount ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(hasVerifiedAccount ? Color.sealSuccess : Color.sealAccent)
            Text(hasVerifiedAccount ? "证书可用" : "暂无可用证书")
                .font(.title2.weight(.semibold))
            Text(hasVerifiedAccount ? "\(verifiedAccounts.count) 个账号可用于签名" : "添加 Apple ID 后会自动准备个人签名证书")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("证书说明")
                .font(.headline)
            Text("证书只用于本机签名。遇到 CERT_EXPIRED、私钥丢失或证书不可用时，先清除本地证书缓存后再重试；如果 Apple 返回证书名额已满，请在失败页选择更换证书并重试。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var verifiedAccounts: [AppleAccountRecord] {
        viewModel.accounts.filter { $0.status == .verified }
    }

    private var hasVerifiedAccount: Bool {
        verifiedAccounts.isEmpty == false
    }

    private func certificateRow(
        title: String,
        subtitle: String,
        status: String,
        color: Color,
        account: AppleAccountRecord?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rosette")
                .font(.title2)
                .foregroundStyle(Color.sealAccent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color)
                if let account {
                    Button("详情") {
                        certificateDetailAccount = account
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sealAccent)
                    Button("清除缓存") {
                        certificatePendingReset = account
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.sealDanger)
                }
            }
        }
        .padding(.vertical, 14)
    }
}

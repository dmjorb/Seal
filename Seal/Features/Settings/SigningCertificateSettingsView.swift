import SwiftUI

struct SigningCertificateSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]

    @State private var certificatePendingReset: AppleAccountRecord?
    @State private var certificatePendingReplacement: ApplePortalCertificateSnapshot?
    @State private var certificatePendingRevocation: ApplePortalCertificateSnapshot?

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
                   hasLocalCertificate == false {
                    createCertificateCard(account)
                }

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
            "撤销证书并创建本机证书？",
            isPresented: Binding(
                get: { certificatePendingReplacement != nil },
                set: { if !$0 { certificatePendingReplacement = nil } }
            ),
            titleVisibility: .visible,
            presenting: certificatePendingReplacement
        ) { certificate in
            Button("撤销所选证书并创建本机证书", role: .destructive) {
                guard let account = activeAccount else { return }
                let serial = certificate.serialNumber
                certificatePendingReplacement = nil
                Task {
                    await viewModel.revokeCertificateAndCreateLocal(
                        serialNumber: serial,
                        for: account
                    )
                }
            }
            Button("取消", role: .cancel) {
                certificatePendingReplacement = nil
            }
        } message: { certificate in
            let affectedCount = activeAccount.map(boundAppCount) ?? 0
            Text("只会撤销你明确选择的证书。\n\n名称：\(certificate.displayName)\n完整 Serial：\(certificate.serialNumber)\n\n随后将创建并立即保存新的本机证书。使用旧证书的描述文件可能失效，当前账号关联应用数：\(affectedCount)。Seal 不会自动撤销其他证书。")
        }
        .confirmationDialog(
            "撤销所选证书？",
            isPresented: Binding(
                get: { certificatePendingRevocation != nil },
                set: { if !$0 { certificatePendingRevocation = nil } }
            ),
            titleVisibility: .visible,
            presenting: certificatePendingRevocation
        ) { certificate in
            Button("只撤销所选证书", role: .destructive) {
                guard let account = activeAccount else { return }
                let serial = certificate.serialNumber
                certificatePendingRevocation = nil
                Task {
                    await viewModel.revokeCertificate(
                        serialNumber: serial,
                        for: account
                    )
                }
            }
            Button("取消", role: .cancel) {
                certificatePendingRevocation = nil
            }
        } message: { certificate in
            Text("只会撤销你明确选择的证书。\n\n名称：\(certificate.displayName)\n完整 Serial：\(certificate.serialNumber)\n\n使用该证书的描述文件可能失效。Seal 不会创建新证书，也不会处理其他证书。")
        }
        .confirmationDialog(
            "清除本地证书？",
            isPresented: Binding(
                get: { certificatePendingReset != nil },
                set: { if !$0 { certificatePendingReset = nil } }
            ),
            titleVisibility: .visible,
            presenting: certificatePendingReset
        ) { account in
            Button("只清除 Seal 本地 P12", role: .destructive) {
                Task { await viewModel.resetCertificate(for: account) }
                certificatePendingReset = nil
            }
            Button("取消", role: .cancel) { certificatePendingReset = nil }
        } message: { account in
            let count = boundAppCount(for: account)
            Text("这只会删除 Seal 本地保存的 P12 和私钥，不会撤销 Apple 端证书。关联应用数：\(count)。之后续签必须明确完成证书迁移。")
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

    private var inventory: ApplePortalInventory? {
        guard let account = activeAccount else { return nil }
        return viewModel.certificateInventory(for: account.id)
    }

    private var hasLocalCertificate: Bool {
        inventory?.certificates.contains(where: { $0.hasLocalPrivateKey }) == true
    }

    private var accountCard: some View {
        VStack(spacing: 0) {
            if let account = activeAccount {
                FullIdentifierRow(
                    title: "Apple ID",
                    value: viewModel.fullEmail(for: account)
                )
                Divider()
                FullIdentifierRow(title: "Team ID", value: account.teamID)
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
                    Divider().padding(.leading, 16)
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
        let selected = account.selectedCertificateSerialNumber?.caseInsensitiveCompare(
            certificate.serialNumber
        ) == .orderedSame

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.seal.fill" : "seal")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(
                        certificate.hasLocalPrivateKey
                            ? Color.sealAccent
                            : Color.sealTextSecondary
                    )
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(certificate.displayName)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Apple Development")
                        .font(.caption)
                        .foregroundStyle(Color.sealTextSecondary)
                }
                Spacer(minLength: 8)
                Text(selected ? "当前使用" : certificate.hasLocalPrivateKey ? "本机可用" : "本机无私钥")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        certificate.hasLocalPrivateKey
                            ? Color.sealSuccess
                            : Color.sealTextSecondary
                    )
            }

            FullIdentifierRow(title: "Serial Number", value: certificate.serialNumber)

            if let machineIdentifier = certificate.machineIdentifier,
               machineIdentifier.isEmpty == false {
                FullIdentifierRow(
                    title: "Machine Identifier",
                    value: machineIdentifier
                )
            }

            if certificate.hasLocalPrivateKey, selected == false {
                Button("设为当前使用") {
                    Task {
                        await viewModel.selectCertificate(
                            serialNumber: certificate.serialNumber,
                            for: account
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCertificateOperationRunning)
            }

            if certificate.hasLocalPrivateKey || hasLocalCertificate == false {
                Button(
                    certificate.hasLocalPrivateKey
                        ? "撤销当前证书并重新创建"
                        : "撤销此证书并创建本机证书",
                    role: .destructive
                ) {
                    certificatePendingReplacement = certificate
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCertificateOperationRunning)
            } else {
                Button("只撤销此证书", role: .destructive) {
                    certificatePendingRevocation = certificate
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCertificateOperationRunning)
            }
        }
        .padding(.vertical, 14)
    }

    private func createCertificateCard(_ account: AppleAccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前没有本机可用证书")
                .font(.headline)
            Text("Seal 将在本机生成私钥，向 Apple 申请 Apple Development 证书，并立即保存 P12 与完整 Serial。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(viewModel.isCertificateOperationRunning ? "正在创建…" : "创建本机 Seal 证书") {
                Task { await viewModel.createLocalCertificate(for: account) }
            }
            .sealPrimaryAction(cornerRadius: 12)
            .disabled(viewModel.isCertificateOperationRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 20)
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
                .textSelection(.enabled)
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
            Text("Apple 当前没有返回开发证书")
                .font(.headline)
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
        relatedApps.filter { $0.accountID == account.id }.count
    }

    private func resetCard(_ account: AppleAccountRecord) -> some View {
        Button(role: .destructive) {
            certificatePendingReset = account
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .frame(width: 30)
                Text("只清除本地 P12")
                Spacer()
            }
            .foregroundStyle(Color.sealDanger)
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: 18)
    }
}

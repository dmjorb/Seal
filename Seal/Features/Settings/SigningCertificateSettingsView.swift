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
        .alert(item: $viewModel.alertFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.userMessage),
                dismissButton: .default(Text(failure.recovery))
            )
        }
        .task {
            await viewModel.load(force: true)
            if let account = activeAccount {
                await viewModel.refreshCertificateInventory(for: account, force: true)
            }
        }
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
                FullIdentifierRow(title: "Team ID", value: account.teamID, showsCopyButton: true)
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
            }
        } else {
            noAccountCard
        }
    }

    private func localCertificateCard(account: AppleAccountRecord, serial: String) -> some View {
        let health = viewModel.certificateHealthStatus(for: account.id)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Seal-\(serial.suffix(8))")
                    .font(.title3.weight(.semibold))
                Text(account.teamName)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                FullIdentifierRow(title: "Serial", value: serial, showsCopyButton: true)
                Text(certificateSummary(health))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(certificateSummaryColor(health))
            }

            Divider()

            VStack(spacing: 0) {
                certificateHealthRow(
                    "Apple Portal",
                    value: stateText(
                        health?.portalPresence,
                        valid: "存在",
                        invalid: "未找到（已撤销或失效）"
                    ),
                    state: health?.portalPresence
                )
                Divider()
                certificateHealthRow(
                    "证书有效期",
                    value: expirationText(health),
                    state: health?.expirationState
                )
                Divider()
                certificateHealthRow(
                    "本地私钥",
                    value: stateText(health?.localPrivateKey, valid: "可用", invalid: "缺失"),
                    state: health?.localPrivateKey
                )
                Divider()
                certificateHealthRow(
                    "P12",
                    value: stateText(health?.p12Readable, valid: "可读取", invalid: "不可读取"),
                    state: health?.p12Readable
                )
                Divider()
                certificateHealthRow(
                    "Keychain",
                    value: stateText(health?.keychainReadable, valid: "可读取", invalid: "不可读取"),
                    state: health?.keychainReadable
                )
                Divider()
                certificateHealthRow(
                    "Apple ID",
                    value: stateText(health?.appleIDMatch, valid: "匹配", invalid: "不匹配"),
                    state: health?.appleIDMatch
                )
                Divider()
                certificateHealthRow(
                    "Team",
                    value: stateText(health?.teamMatch, valid: "匹配", invalid: "不匹配"),
                    state: health?.teamMatch
                )
                Divider()
                certificateHealthRow(
                    "上次签名",
                    value: lastSignedText(health),
                    state: nil
                )
            }

            Button("刷新证书状态") {
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

    private func certificateHealthRow(
        _ title: String,
        value: String,
        state: CertificateHealthStatus.CheckState?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(Color.sealTextSecondary)
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                if let state {
                    Image(systemName: stateIcon(state))
                        .foregroundStyle(stateColor(state))
                        .accessibilityHidden(true)
                }
                Text(value)
                    .foregroundStyle(state.map { stateColor($0) } ?? Color.primary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
    }

    private func certificateSummary(_ health: CertificateHealthStatus?) -> String {
        guard let health else { return "状态待检查" }
        return health.isUsable ? "可用于签名" : "需要处理"
    }

    private func certificateSummaryColor(_ health: CertificateHealthStatus?) -> Color {
        guard let health else { return Color.sealTextSecondary }
        return health.isUsable ? Color.sealSuccess : Color.sealWarning
    }

    private func stateText(
        _ state: CertificateHealthStatus.CheckState?,
        valid: String,
        invalid: String
    ) -> String {
        switch state {
        case .valid: valid
        case .invalid: invalid
        case .unknown, .none: "无法确认"
        }
    }

    private func stateIcon(_ state: CertificateHealthStatus.CheckState) -> String {
        switch state {
        case .valid: "checkmark.circle.fill"
        case .invalid: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func stateColor(_ state: CertificateHealthStatus.CheckState) -> Color {
        switch state {
        case .valid: Color.sealSuccess
        case .invalid: Color.sealDanger
        case .unknown: Color.sealTextSecondary
        }
    }

    private func expirationText(_ health: CertificateHealthStatus?) -> String {
        guard let health, let expirationDate = health.expirationDate else {
            return "无法确认"
        }
        let formatted = expirationDate.formatted(
            date: .abbreviated,
            time: .shortened
        )
        return health.expirationState == .invalid ? "已过期 · \(formatted)" : formatted
    }

    private func lastSignedText(_ health: CertificateHealthStatus?) -> String {
        guard let health else { return "无法确认" }
        guard let lastSignedAt = health.lastSignedAt else { return "未使用" }
        let apps = health.relatedAppCount == 1 ? "1 个 App" : "\(health.relatedAppCount) 个 App"
        return "\(lastSignedAt.formatted(date: .abbreviated, time: .shortened)) · \(apps)"
    }

    private func missingCertificateCard(_ account: AppleAccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前没有本机可用证书")
                .font(.headline)
            Text("首次签名时将自动创建。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
            Button(viewModel.isCertificateOperationRunning ? "正在创建…" : "创建本机证书") {
                Task { await viewModel.createLocalCertificate(for: account) }
            }
            .sealPrimaryAction(cornerRadius: 12)
            .disabled(viewModel.isCertificateOperationRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 20)
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

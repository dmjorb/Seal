import SwiftUI

struct AppleAccountDetailView: View {
    let account: AppleAccountRecord
    let relatedApps: [AppRecord]
    @ObservedObject var viewModel: SettingsViewModel

    @State private var isReverifying = false
    @State private var isResettingCertificate = false

    private var inventory: ApplePortalInventory? {
        viewModel.certificateInventory(for: account.id)
    }

    private var syncFailure: ImportFailure? {
        viewModel.certificateInventoryFailure(for: account.id)
    }

    private var isSyncing: Bool {
        viewModel.isCertificateInventoryLoading(accountID: account.id)
    }

    private var appleSideItems: [AppleSideCertificateDetailItem] {
        AppleSideCertificateDetailItem.build(
            inventory: inventory,
            relatedApps: relatedApps
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                syncStateCard
                certificatesCard

                Text("Apple 侧 App ID / Profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                    .padding(.leading, 8)

                if isSyncing && inventory == nil {
                    loadingCard
                } else if let syncFailure, inventory == nil {
                    failureCard(syncFailure)
                } else if appleSideItems.isEmpty {
                    emptyAppsCard
                } else {
                    appsCard
                }

                actionsCard
            }
            .padding(20)
        }
        .navigationTitle("证书详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refreshCertificateInventory(for: account) }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
            }
        }
        .fullScreenCover(isPresented: $isReverifying) {
            AddAccountView(viewModel: viewModel, replacingAccount: account)
        }
        .confirmationDialog(
            "清除本地证书缓存？",
            isPresented: $isResettingCertificate,
            titleVisibility: .visible
        ) {
            Button("清除并重新申请", role: .destructive) {
                Task { await viewModel.resetCertificate(for: account) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只清除 Seal 本地保存的 P12 和证书序列号，不会伪造 Apple 侧状态。下次签名由 Apple 返回真实结果。")
        }
        .task {
            await viewModel.load(force: true)
            await viewModel.refreshCertificateInventory(for: account, force: false)
        }
        .sealScreenBackground(.secondary)
    }

    private var syncStateCard: some View {
        VStack(spacing: 0) {
            detailRow("账号", account.maskedEmail, Color.primary)
            Divider()
            detailRow("Team", account.teamName, Color.primary)
            Divider()
            detailRow("Team ID", account.teamID, Color.sealTextSecondary)
            Divider()
            detailRow("同步来源", "Apple 侧", Color.sealAccent)
            Divider()
            detailRow("App ID", inventory.map { "\($0.usedBundleIDCount) 个" } ?? (isSyncing ? "同步中" : "未同步"), inventory == nil ? Color.sealTextSecondary : Color.sealAccent)
            Divider()
            detailRow("同步时间", inventory.map { SigningHistoryDateFormatter.string(from: $0.fetchedAt) } ?? "未同步", Color.sealTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 24)
    }

    private var certificatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Development 证书")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sealTextSecondary)

            if let certificates = inventory?.certificates, certificates.isEmpty == false {
                ForEach(certificates) { certificate in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: certificate.hasLocalPrivateKey ? "key.fill" : "key")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(certificate.hasLocalPrivateKey ? Color.sealSuccess : Color.sealTextSecondary)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(certificate.machineName)
                                .font(.body.weight(.semibold))
                            Text("Serial：\(certificate.serialNumber)")
                                .font(.caption)
                                .foregroundStyle(Color.sealTextSecondary)
                                .textSelection(.enabled)
                            Text(certificate.hasLocalPrivateKey ? "本地私钥可用" : "Apple 侧存在，本地无私钥")
                                .font(.caption)
                                .foregroundStyle(certificate.hasLocalPrivateKey ? Color.sealSuccess : Color.sealWarning)
                        }
                        Spacer()
                    }
                    if certificate.id != certificates.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            } else if isSyncing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在同步 Apple 侧证书")
                        .foregroundStyle(Color.sealTextSecondary)
                }
            } else {
                Text(syncFailure == nil ? "尚未同步 Apple 侧证书" : "证书同步失败")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 24)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在从 Apple 侧同步 App ID、描述文件与过期时间")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .glassSurface(cornerRadius: 24)
    }

    private func failureCard(_ failure: ImportFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("同步失败", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.sealDanger)
            Text(failure.reason)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .textSelection(.enabled)
            Text(failure.code)
                .font(.caption.monospaced())
                .foregroundStyle(Color.sealTextSecondary)
                .textSelection(.enabled)
            Button("重新同步") {
                Task { await viewModel.refreshCertificateInventory(for: account) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private var emptyAppsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 34))
                .foregroundStyle(Color.sealTextSecondary)
            Text("Apple 侧暂无 App ID")
                .font(.headline)
            Text("这里不会使用本地历史冒充 Apple 侧数据。同步成功后才显示 Apple 返回的 App ID、Bundle ID 和描述文件过期时间。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .glassSurface(cornerRadius: 24)
    }

    private var appsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(appleSideItems.enumerated()), id: \.element.id) { index, item in
                appItemRow(item)
                if index < appleSideItems.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 24)
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button { isReverifying = true } label: {
                actionRow("重新验证 Apple ID", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.plain)
            Divider()
            Button { isResettingCertificate = true } label: {
                actionRow("清除本地证书缓存", systemImage: "trash", color: Color.sealDanger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassSurface(cornerRadius: 24)
    }

    private func appItemRow(_ item: AppleSideCertificateDetailItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.status.iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(item.status.color)
                .frame(width: 32, height: 32)
                .background(item.status.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Bundle ID：\(item.bundleIdentifier)")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
                    .textSelection(.enabled)
                Text("描述文件过期：\(item.expirationText)")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
                if let profileMessage = item.profileMessage {
                    Text(profileMessage)
                        .font(.caption2)
                        .foregroundStyle(Color.sealWarning)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            Text(item.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(item.status.color.opacity(0.10), in: Capsule())
        }
        .padding(.vertical, 14)
    }

    private func detailRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(Color.sealTextSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }

    private func actionRow(_ title: String, systemImage: String, color: Color = Color.sealAccent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 30)
                .foregroundStyle(color)
            Text(title)
                .foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sealTextSecondary)
        }
        .padding(.vertical, 14)
    }
}

private struct AppleSideCertificateDetailItem: Identifiable, Equatable {
    enum Status: Equatable {
        case active
        case expiringSoon
        case expired
        case profileUnavailable
        case unknown

        var title: String {
            switch self {
            case .active: "有效"
            case .expiringSoon: "临期"
            case .expired: "过期"
            case .profileUnavailable: "Profile 不可用"
            case .unknown: "未确认"
            }
        }

        var iconName: String {
            switch self {
            case .active: "checkmark.circle.fill"
            case .expiringSoon: "clock.badge.exclamationmark.fill"
            case .expired: "xmark.circle.fill"
            case .profileUnavailable: "exclamationmark.triangle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .active: Color.sealSuccess
            case .expiringSoon: Color.sealWarning
            case .expired, .profileUnavailable: Color.sealDanger
            case .unknown: Color.sealTextSecondary
            }
        }
    }

    let id: String
    let name: String
    let bundleIdentifier: String
    let expirationDate: Date?
    let status: Status
    let profileMessage: String?

    var expirationText: String {
        guard let expirationDate else { return "Apple 未返回" }
        return SigningHistoryDateFormatter.string(from: expirationDate)
    }

    static func build(
        inventory: ApplePortalInventory?,
        relatedApps: [AppRecord]
    ) -> [AppleSideCertificateDetailItem] {
        guard let inventory else { return [] }
        var localNames: [String: String] = [:]
        for app in relatedApps {
            let bundleID = app.mappedBundleIdentifier
                ?? app.preferredBundleIdentifier
                ?? app.originalBundleIdentifier
            localNames[bundleID.lowercased()] = app.name
        }

        return inventory.appIDs.map { snapshot in
            let key = snapshot.bundleIdentifier.lowercased()
            let itemStatus: Status
            let message: String?
            switch snapshot.profileState {
            case .available:
                itemStatus = Self.status(expirationDate: snapshot.provisioningProfileExpirationDate)
                message = nil
            case let .unavailable(code, rawMessage):
                itemStatus = .profileUnavailable
                message = "Apple 返回：\(code) \(rawMessage)"
            }
            return AppleSideCertificateDetailItem(
                id: key,
                name: localNames[key] ?? "App ID",
                bundleIdentifier: snapshot.bundleIdentifier,
                expirationDate: snapshot.provisioningProfileExpirationDate,
                status: itemStatus,
                profileMessage: message
            )
        }
        .sorted {
            if $0.status.sortPriority != $1.status.sortPriority {
                return $0.status.sortPriority < $1.status.sortPriority
            }
            return $0.bundleIdentifier < $1.bundleIdentifier
        }
    }

    private static func status(expirationDate: Date?) -> Status {
        guard let expirationDate else { return .unknown }
        let interval = expirationDate.timeIntervalSince(Date())
        if interval <= 0 { return .expired }
        if interval <= 86_400 * 2 { return .expiringSoon }
        return .active
    }
}

private extension AppleSideCertificateDetailItem.Status {
    var sortPriority: Int {
        switch self {
        case .expiringSoon: 0
        case .active: 1
        case .expired: 2
        case .profileUnavailable: 3
        case .unknown: 4
        }
    }
}

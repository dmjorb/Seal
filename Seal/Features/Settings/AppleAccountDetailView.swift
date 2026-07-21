import SwiftUI

struct AppleAccountDetailView: View {
    let account: AppleAccountRecord
    let relatedApps: [AppRecord]
    @ObservedObject var viewModel: SettingsViewModel

    @State private var isReverifying = false

    private var currentAccount: AppleAccountRecord {
        viewModel.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var inventory: ApplePortalInventory? {
        viewModel.certificateInventory(for: account.id)
    }

    private var syncFailure: ImportFailure? {
        viewModel.certificateInventoryFailure(for: account.id)
    }

    private var isSyncing: Bool {
        viewModel.isCertificateInventoryLoading(accountID: account.id)
    }

    private var appItems: [AppleAccountAppItem] {
        guard let inventory else { return [] }
        return inventory.appIDs
            .map { AppleAccountAppItem(snapshot: $0) }
            .sorted {
                if $0.status.sortPriority != $1.status.sortPriority {
                    return $0.status.sortPriority < $1.status.sortPriority
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                accountCard

                sectionTitle("签名证书")
                certificateContent

                sectionTitle("App ID")
                appsContent

                reverifyCard
            }
            .padding(20)
        }
        .navigationTitle("Apple ID 详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.refreshCertificateInventory(for: currentAccount, force: true)
                    }
                } label: {
                    if isSyncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isSyncing)
            }
        }
        .fullScreenCover(isPresented: $isReverifying) {
            AddAccountView(viewModel: viewModel, replacingAccount: currentAccount)
        }
        .task {
            await viewModel.load()
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

    private var accountCard: some View {
        VStack(spacing: 0) {
            detailRow("Apple ID", viewModel.fullEmail(for: currentAccount))
            Divider()
            detailRow("Team", currentAccount.teamName)
            Divider()
            detailRow("Team ID", currentAccount.teamID)
            Divider()
            detailRow("App ID", appIDQuotaTitle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 24)
    }

    private var appIDQuotaTitle: String {
        guard let inventory else { return currentAccount.isFreeTeam ? "— / 10" : "Developer" }
        return currentAccount.isFreeTeam ? "\(inventory.usedBundleIDCount) / 10" : "Developer"
    }

    @ViewBuilder
    private var certificateContent: some View {
        if let serial = currentAccount.certificateSerialNumber, serial.isEmpty == false {
            VStack(alignment: .leading, spacing: 7) {
                Text("Seal-\(serial.suffix(8))")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(currentAccount.teamName)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                Text("Serial：\(serial)")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("本机可用")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sealSuccess)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassSurface(cornerRadius: 24)
        } else {
            emptyCard(
                icon: "seal",
                title: "当前没有本机可用证书",
                subtitle: "首次签名时将自动创建。"
            )
        }
    }

    @ViewBuilder
    private var appsContent: some View {
        if isSyncing && inventory == nil {
            loadingCard("正在读取 App ID")
        } else if let syncFailure, inventory == nil {
            failureCard(syncFailure)
        } else if appItems.isEmpty {
            emptyCard(icon: "app.dashed", title: "暂无 App ID", subtitle: "Apple 当前没有返回 App ID。")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(appItems.enumerated()), id: \.element.id) { index, item in
                    appRow(item)
                    if index < appItems.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .padding(.horizontal, 16)
            .glassSurface(cornerRadius: 24)
        }
    }

    private func appRow(_ item: AppleAccountAppItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                Text(item.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status.color)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("Bundle ID")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
                Spacer(minLength: 12)
                Text(item.bundleIdentifier)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Text(item.expirationLabel)
                .font(.caption)
                .foregroundStyle(Color.sealTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 14)
    }

    private var reverifyCard: some View {
        Button { isReverifying = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .frame(width: 30)
                Text("重新验证 Apple ID")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.sealAccent)
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: 18)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.sealTextSecondary)
            .padding(.leading, 8)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.vertical, 15)
    }

    private func loadingCard(_ title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title).foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassSurface(cornerRadius: 24)
    }

    private func failureCard(_ failure: ImportFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("同步失败")
                .font(.headline)
                .foregroundStyle(Color.sealDanger)
            Text(failure.userMessage)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新同步") {
                Task { await viewModel.refreshCertificateInventory(for: currentAccount, force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private func emptyCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(Color.sealTextSecondary)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassSurface(cornerRadius: 24)
    }
}

private struct AppleAccountAppItem: Identifiable, Equatable {
    enum Status: Equatable {
        case active
        case expiringSoon
        case expired
        case unavailable

        var title: String {
            switch self {
            case .active: return "有效"
            case .expiringSoon: return "即将过期"
            case .expired: return "已过期"
            case .unavailable: return "缺少描述文件"
            }
        }

        var color: Color {
            switch self {
            case .active: return .sealSuccess
            case .expiringSoon: return .sealWarning
            case .expired: return .sealDanger
            case .unavailable: return .sealTextSecondary
            }
        }

        var sortPriority: Int {
            switch self {
            case .expiringSoon: return 0
            case .active: return 1
            case .expired: return 2
            case .unavailable: return 3
            }
        }
    }

    let id: String
    let name: String
    let bundleIdentifier: String
    let expiryDate: Date?
    let status: Status

    init(snapshot: ApplePortalAppIDSnapshot) {
        id = snapshot.id
        name = snapshot.name
        bundleIdentifier = snapshot.bundleIdentifier
        expiryDate = snapshot.provisioningProfileExpirationDate
        status = Self.status(
            expiryDate: snapshot.provisioningProfileExpirationDate,
            profileState: snapshot.provisioningProfileState
        )
    }

    var expirationLabel: String {
        guard let expiryDate else { return "有效期至：Apple 未返回描述文件" }
        let prefix = status == .expired ? "到期时间" : "有效期至"
        return "\(prefix)：\(SealSettingsDateFormatter.string(from: expiryDate))"
    }

    private static func status(
        expiryDate: Date?,
        profileState: ApplePortalAppIDSnapshot.ProvisioningProfileState
    ) -> Status {
        guard profileState == .available, let expiryDate else { return .unavailable }
        let interval = expiryDate.timeIntervalSinceNow
        if interval <= 0 { return .expired }
        if interval <= 86_400 * 2 { return .expiringSoon }
        return .active
    }
}

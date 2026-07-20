import SwiftUI
import UIKit

struct AppleAccountDetailView: View {
    let account: AppleAccountRecord
    let relatedApps: [AppRecord]
    @ObservedObject var viewModel: SettingsViewModel

    @State private var isReverifying = false
    @Environment(\.scenePhase) private var scenePhase

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
            .map { snapshot in
                let localApp = matchedApp(bundleIdentifier: snapshot.bundleIdentifier)
                let history = localApp == nil
                    ? matchedHistory(bundleIdentifier: snapshot.bundleIdentifier)
                    : nil
                let iconData = localApp.flatMap { viewModel.appIconData[$0.id] }
                    ?? history.flatMap { viewModel.signingHistoryIconData[$0.id] }
                return AppleAccountAppItem(
                    bundleIdentifier: snapshot.bundleIdentifier,
                    app: localApp,
                    history: history,
                    iconData: iconData
                )
            }
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
                certificatesContent

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
                        await viewModel.refreshCertificateInventory(
                            for: currentAccount,
                            force: true
                        )
                    }
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
            AddAccountView(viewModel: viewModel, replacingAccount: currentAccount)
        }
        .task {
            await viewModel.load(force: true)
            await viewModel.refreshCertificateInventory(
                for: currentAccount,
                force: false
            )
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await viewModel.load(force: true)
                await viewModel.refreshCertificateInventory(
                    for: currentAccount,
                    force: false
                )
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

    private var accountCard: some View {
        VStack(spacing: 0) {
            detailRow("Apple ID", viewModel.fullEmail(for: currentAccount))
            Divider()
            detailRow("Team", currentAccount.teamName)
            Divider()
            detailRow("Team ID", currentAccount.teamID)
            Divider()
            detailRow("账户类型", accountTypeText)
            Divider()
            detailRow("App ID 配额", appIDQuotaText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 24)
    }

    @ViewBuilder
    private var certificatesContent: some View {
        if isSyncing && inventory == nil {
            loadingCard("正在读取证书")
        } else if let syncFailure, inventory == nil {
            failureCard(syncFailure)
        } else if let certificates = inventory?.certificates,
                  certificates.isEmpty == false {
            VStack(spacing: 0) {
                ForEach(Array(certificates.enumerated()), id: \.element.id) { index, certificate in
                    certificateRow(certificate)
                    if index < certificates.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassSurface(cornerRadius: 24)
        } else {
            emptyCard(
                icon: "seal",
                title: "暂无证书",
                subtitle: "Apple 当前没有返回开发证书。首次签名时，Seal 会按需申请证书。"
            )
        }
    }

    private func certificateRow(
        _ certificate: ApplePortalCertificateSnapshot
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "rosette")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    certificate.hasLocalPrivateKey
                        ? Color.sealAccent
                        : Color.sealTextSecondary
                )
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(certificate.displayName)
                    .font(.body.weight(.semibold))
                Text("Apple Development")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
                Text("Serial：\(abbreviated(certificate.serialNumber))")
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.sealTextSecondary)
                    .textSelection(.enabled)
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
            Text(certificate.hasLocalPrivateKey ? "可用" : "不可用")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    certificate.hasLocalPrivateKey
                        ? Color.sealSuccess
                        : Color.sealTextSecondary
                )
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var appsContent: some View {
        if isSyncing && inventory == nil {
            loadingCard("正在读取 App ID")
        } else if let syncFailure, inventory == nil {
            failureCard(syncFailure)
        } else if appItems.isEmpty {
            emptyCard(
                icon: "app.dashed",
                title: "暂无 App ID",
                subtitle: "Apple 当前没有返回 App ID。"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(appItems.enumerated()), id: \.element.id) { index, item in
                    appRow(item)
                    if index < appItems.count - 1 {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassSurface(cornerRadius: 24)
        }
    }

    private func appRow(_ item: AppleAccountAppItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            appIcon(item)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.status.color)
                }

                Text("Bundle ID：")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
                Text(item.bundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.sealTextSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Text("描述文件过期：\(item.expirationText)")
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func appIcon(_ item: AppleAccountAppItem) -> some View {
        Group {
            if let data = item.iconData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(Color.sealTextSecondary)
                    .background(Color.sealHairline.opacity(0.35))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(Color.sealTextSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }

    private func loadingCard(_ title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .foregroundStyle(Color.sealTextSecondary)
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
            Text(failure.reason)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .textSelection(.enabled)
            Button("重新同步") {
                Task {
                    await viewModel.refreshCertificateInventory(
                        for: currentAccount,
                        force: true
                    )
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private func emptyCard(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(Color.sealTextSecondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassSurface(cornerRadius: 24)
    }

    private var accountTypeText: String {
        switch currentAccount.isFreeTeam {
        case true: return "个人免费团队"
        case false: return "Apple Developer 团队"
        case nil: return "未确认"
        }
    }

    private var appIDQuotaText: String {
        guard let inventory else {
            return isSyncing ? "同步中" : "暂无法确认"
        }
        switch currentAccount.isFreeTeam {
        case true:
            return "\(inventory.usedBundleIDCount) / 10"
        case false:
            return "已注册 \(inventory.usedBundleIDCount) 个"
        case nil:
            return "暂无法确认"
        }
    }

    private func matchedApp(bundleIdentifier: String) -> AppRecord? {
        let matches = relatedApps.filter { app in
            [
                app.mappedBundleIdentifier,
                app.preferredBundleIdentifier,
                app.originalBundleIdentifier
            ]
            .compactMap { $0 }
            .contains {
                $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }
        }
        return matches.first { $0.accountID == currentAccount.id }
            ?? matches.first { $0.accountID == nil }
    }

    private func matchedHistory(
        bundleIdentifier: String
    ) -> SigningHistoryRecord? {
        viewModel.signingHistory
            .filter {
                $0.accountID == currentAccount.id
                    && $0.result == .success
            }
            .filter {
                $0.displayBundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }
            .sorted { $0.signedAt > $1.signedAt }
            .first
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(6))"
    }
}

private struct AppleAccountAppItem: Identifiable, Equatable {
    enum Status: Equatable {
        case active
        case expiringSoon
        case expired
        case unlinked

        var title: String {
            switch self {
            case .active: return "有效"
            case .expiringSoon: return "临期"
            case .expired: return "过期"
            case .unlinked: return "未关联"
            }
        }

        var color: Color {
            switch self {
            case .active: return .sealSuccess
            case .expiringSoon: return .sealWarning
            case .expired: return .sealDanger
            case .unlinked: return .sealTextSecondary
            }
        }

        var sortPriority: Int {
            switch self {
            case .expiringSoon: return 0
            case .active: return 1
            case .expired: return 2
            case .unlinked: return 3
            }
        }
    }

    let id: String
    let name: String
    let bundleIdentifier: String
    let expiryDate: Date?
    let iconData: Data?
    let status: Status

    init(
        bundleIdentifier: String,
        app: AppRecord?,
        history: SigningHistoryRecord?,
        iconData: Data?
    ) {
        id = bundleIdentifier.lowercased()
        name = app?.name ?? history?.appName ?? "未关联本地应用"
        self.bundleIdentifier = bundleIdentifier
        expiryDate = app?.expiryDate ?? history?.expiryDate
        self.iconData = iconData
        status = Self.status(
            expiryDate: app?.expiryDate ?? history?.expiryDate,
            hasLocalRecord: app != nil || history != nil
        )
    }

    var expirationText: String {
        guard let expiryDate else { return "未关联本机描述文件" }
        return SigningHistoryDateFormatter.string(from: expiryDate)
    }

    private static func status(
        expiryDate: Date?,
        hasLocalRecord: Bool
    ) -> Status {
        guard hasLocalRecord, let expiryDate else { return .unlinked }
        let interval = expiryDate.timeIntervalSinceNow
        if interval <= 0 { return .expired }
        if interval <= 86_400 * 2 { return .expiringSoon }
        return .active
    }
}

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
                let localApp = matchedApp(for: snapshot)
                let history = localApp == nil ? matchedHistory(for: snapshot) : nil
                let iconData = localApp.flatMap { viewModel.appIconData[$0.id] }
                    ?? history.flatMap { viewModel.signingHistoryIconData[$0.id] }
                return AppleAccountAppItem(
                    snapshot: snapshot,
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
            detailRow("Apple 返回的 App ID", appIDQuotaText)
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
        VStack(alignment: .leading, spacing: 8) {
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Apple Development")
                        .font(.caption)
                        .foregroundStyle(Color.sealTextSecondary)
                }
                Spacer(minLength: 8)
                Text(certificate.hasLocalPrivateKey ? "本机可用" : "本机无私钥")
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
                FullIdentifierRow(title: "Machine Identifier", value: machineIdentifier)
            }
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 14) {
                appIcon(item)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.status.color)
                    Text("App ID 到期：\(item.appIDExpirationText)")
                        .font(.caption)
                        .foregroundStyle(Color.sealTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("描述文件过期：\(item.expirationText)")
                        .font(.caption)
                        .foregroundStyle(Color.sealTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }

            FullIdentifierRow(title: "App ID Identifier", value: item.appIDIdentifier)
            FullIdentifierRow(title: "Bundle ID", value: item.bundleIdentifier)
            if let profileName = item.profileName, profileName.isEmpty == false {
                FullIdentifierRow(title: "Provisioning Profile", value: profileName)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(Color.sealTextSecondary)
                Spacer(minLength: 12)
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.sealAccent)
            }
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        return "Apple 当前返回 \(inventory.usedBundleIDCount) 个"
    }

    private func matchedApp(for snapshot: ApplePortalAppIDSnapshot) -> AppRecord? {
        let bundleMatches = relatedApps.filter { app in
            [
                app.mappedBundleIdentifier,
                app.preferredBundleIdentifier,
                app.originalBundleIdentifier
            ]
            .compactMap { $0 }
            .contains {
                $0.caseInsensitiveCompare(snapshot.bundleIdentifier) == .orderedSame
            }
        }
        return bundleMatches.first(where: { $0.accountID == currentAccount.id })
            ?? bundleMatches.first(where: { $0.accountID == nil })
            ?? bundleMatches.first
    }

    private func matchedHistory(
        for snapshot: ApplePortalAppIDSnapshot
    ) -> SigningHistoryRecord? {
        let successfulRecords = viewModel.signingHistory.filter {
            $0.accountID == currentAccount.id && $0.result == .success
        }
        return successfulRecords.filter { record in
            record.displayBundleIdentifier.caseInsensitiveCompare(snapshot.bundleIdentifier) == .orderedSame
        }
        .sorted(by: { $0.signedAt > $1.signedAt })
        .first
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
            case .expiringSoon: return "临期"
            case .expired: return "过期"
            case .unavailable: return "无描述文件"
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
    let appIDIdentifier: String
    let bundleIdentifier: String
    let profileName: String?
    let appIDExpirationDate: Date?
    let expiryDate: Date?
    let iconData: Data?
    let status: Status

    init(
        snapshot: ApplePortalAppIDSnapshot,
        iconData: Data?
    ) {
        id = snapshot.id
        name = snapshot.name
        appIDIdentifier = snapshot.identifier
        bundleIdentifier = snapshot.bundleIdentifier
        profileName = snapshot.provisioningProfileName
        appIDExpirationDate = snapshot.appIDExpirationDate
        expiryDate = snapshot.provisioningProfileExpirationDate
        self.iconData = iconData
        status = Self.status(
            expiryDate: snapshot.provisioningProfileExpirationDate,
            profileState: snapshot.provisioningProfileState
        )
    }

    var appIDExpirationText: String {
        guard let appIDExpirationDate else { return "Apple 未返回" }
        return SigningHistoryDateFormatter.string(from: appIDExpirationDate)
    }

    var expirationText: String {
        guard let expiryDate else { return "Apple 未返回描述文件" }
        return SigningHistoryDateFormatter.string(from: expiryDate)
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

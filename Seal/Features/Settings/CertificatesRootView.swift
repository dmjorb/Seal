import SwiftUI

struct CertificatesRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]

    @State private var isAddingAccount = false
    @State private var detailAccount: AppleAccountRecord?
    @State private var accountPendingDeletion: AppleAccountRecord?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                Text("Apple ID")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                    .padding(.leading, 8)

                if viewModel.accounts.isEmpty {
                    emptyState
                } else {
                    accountsList
                }
            }
            .padding(20)
        }
        .navigationTitle("Apple ID")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isAddingAccount) {
            AddAccountView(viewModel: viewModel)
        }
        .confirmationDialog(
            "删除 Apple ID？",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: accountPendingDeletion
        ) { account in
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteAccount(account) }
                accountPendingDeletion = nil
            }
            Button("取消", role: .cancel) { accountPendingDeletion = nil }
        } message: { account in
            let count = relatedApps.filter { $0.accountID == account.id }.count
            Text(
                count == 0
                    ? "删除后将无法继续使用此账号签名。"
                    : "该账号仍绑定于 \(count) 个应用。删除后，这些应用无法继续续签。"
            )
        }
        .navigationDestination(
            isPresented: Binding(
                get: { detailAccount != nil },
                set: { if !$0 { detailAccount = nil } }
            )
        ) {
            if let account = detailAccount {
                AppleAccountDetailView(
                    account: account,
                    relatedApps: relatedApps,
                    viewModel: viewModel
                )
            }
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
            await viewModel.refreshCertificateInventories()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await viewModel.load(force: true)
                await viewModel.refreshCertificateInventories()
            }
        }
        .onChange(of: viewModel.requestedRoute) { route in
            guard route == .addAccount else { return }
            viewModel.requestedRoute = nil
            isAddingAccount = true
        }
        .sealScreenBackground()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Color.sealAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.accounts.isEmpty ? "添加 Apple ID" : "当前签名账号")
                    .font(.title3.weight(.semibold))
                Text(activeAccountSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { isAddingAccount = true } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.sealAccent.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private var activeAccountSubtitle: String {
        guard let account = viewModel.activeAccount else {
            return "选择一个已验证账号用于新的 IPA 签名"
        }
        return viewModel.fullEmail(for: account)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(Color.sealAccent)
            Text("还没有 Apple ID")
                .font(.headline)
            Text("添加并验证后，可用于签名、续签和查看 Apple 账号状态。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(cornerRadius: 24)
    }

    private var accountsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.accounts.enumerated()), id: \.element.id) { index, account in
                accountRow(account)
                if index < viewModel.accounts.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 24)
    }

    private func accountRow(_ account: AppleAccountRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                guard account.status == .verified else {
                    detailAccount = account
                    return
                }
                Task { await viewModel.selectActiveAccount(account) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isActive(account) ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            isActive(account)
                                ? Color.sealAccent
                                : Color.sealTextSecondary.opacity(0.55)
                        )
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.fullEmail(for: account))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(account.teamName) · \(account.teamID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.sealTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(isActive(account) ? "当前使用" : accountStatusTitle(account))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                isActive(account)
                                    ? Color.sealAccent
                                    : accountStatusColor(account)
                            )
                        Text(appIDCountTitle(account))
                            .font(.caption2)
                            .foregroundStyle(Color.sealTextSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                detailAccount = account
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("删除", role: .destructive) {
                    accountPendingDeletion = account
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func isActive(_ account: AppleAccountRecord) -> Bool {
        viewModel.activeAccountID == account.id
    }

    private func accountStatusTitle(_ account: AppleAccountRecord) -> String {
        account.status == .verified ? "可用" : "需验证"
    }

    private func accountStatusColor(_ account: AppleAccountRecord) -> Color {
        account.status == .verified ? .sealSuccess : .sealWarning
    }

    private func appIDCountTitle(_ account: AppleAccountRecord) -> String {
        if viewModel.isCertificateInventoryLoading(accountID: account.id) {
            return "同步中"
        }
        if let inventory = viewModel.certificateInventory(for: account.id) {
            return "App ID \(inventory.usedBundleIDCount)"
        }
        if viewModel.certificateInventoryFailure(for: account.id) != nil {
            return "同步失败"
        }
        return "未同步"
    }
}

import SwiftUI

struct CertificatesRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let relatedApps: [AppRecord]
    @State private var isAddingAccount = false
    @State private var actionAccount: AppleAccountRecord?
    @State private var detailAccount: AppleAccountRecord?
    @State private var accountPendingDeletion: AppleAccountRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Text("Apple ID 证书")
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
        .navigationTitle("证书")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isAddingAccount) {
            AddAccountView(viewModel: viewModel)
        }
        .confirmationDialog(
            actionAccount?.maskedEmail ?? "Apple ID",
            isPresented: Binding(
                get: { actionAccount != nil },
                set: { if !$0 { actionAccount = nil } }
            ),
            titleVisibility: .visible,
            presenting: actionAccount
        ) { account in
            Button("证书详情") {
                detailAccount = account
                actionAccount = nil
            }
            Button("删除", role: .destructive) {
                accountPendingDeletion = account
                actionAccount = nil
            }
            Button("取消", role: .cancel) {
                actionAccount = nil
            }
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
            Text(count == 0 ? "删除后将无法使用此账号签名。" : "该账号仍用于签名 \(count) 个应用，删除后这些应用无法继续续签。")
        }
        .navigationDestination(item: $detailAccount) { account in
            AppleAccountDetailView(
                account: account,
                relatedApps: relatedApps.filter { $0.accountID == account.id },
                viewModel: viewModel
            )
        }
        .alert(item: $viewModel.alertFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text("\(failure.reason)\n\(failure.code)"),
                dismissButton: .default(Text(failure.recovery))
            )
        }
        .task {
            await viewModel.load(force: true)
            await viewModel.refreshCertificateInventories()
        }
        .onChange(of: viewModel.requestedRoute) { route in
            guard route == .addAccount else { return }
            viewModel.requestedRoute = nil
            isAddingAccount = true
        }
        .sealScreenBackground(.secondary)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.sealAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.accounts.isEmpty ? "添加 Apple ID" : "证书")
                    .font(.title3.weight(.semibold))
                Text(viewModel.accounts.isEmpty ? "添加 Apple ID 后用于签名" : "\(viewModel.accounts.count) 个 Apple ID")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(Color.sealAccent)
            Text("还没有 Apple ID")
                .font(.headline)
            Text("添加后可查看证书详情、已签应用和过期时间。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(cornerRadius: 24)
    }

    private var accountsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.accounts.enumerated()), id: \.element.id) { index, account in
                Button {
                    actionAccount = account
                } label: {
                    accountRow(account)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("证书详情") { detailAccount = account }
                    Button("删除", role: .destructive) { accountPendingDeletion = account }
                }

                if index < viewModel.accounts.count - 1 {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 24)
    }

    private func accountRow(_ account: AppleAccountRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rosette")
                .font(.title2)
                .foregroundStyle(Color.sealAccent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.maskedEmail)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(account.teamName)
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(appleSideCountText(for: account))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appleSideCountColor(for: account))
                Text(account.status == .verified ? "可用" : "需验证")
                    .font(.caption)
                    .foregroundStyle(account.status == .verified ? Color.sealSuccess : Color.sealWarning)
            }
        }
        .padding(.vertical, 14)
    }

    private func appleSideCountText(for account: AppleAccountRecord) -> String {
        if viewModel.isCertificateInventoryLoading(accountID: account.id) {
            return "同步中"
        }
        if let inventory = viewModel.certificateInventory(for: account.id) {
            return "Apple 侧 \(inventory.usedBundleIDCount)"
        }
        if viewModel.certificateInventoryFailure(for: account.id) != nil {
            return "同步失败"
        }
        return "未同步"
    }

    private func appleSideCountColor(for account: AppleAccountRecord) -> Color {
        if viewModel.certificateInventoryFailure(for: account.id) != nil {
            return Color.sealDanger
        }
        if viewModel.certificateInventory(for: account.id) != nil {
            return Color.sealAccent
        }
        return Color.sealTextSecondary
    }
}

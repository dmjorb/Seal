import SwiftUI

struct StorageMaintenanceView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var confirmsTemporaryClear = false
    @State private var confirmsIPACacheClear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryCard
                usageCard
                actionCard
            }
            .padding(20)
        }
        .navigationTitle("存储与维护")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refreshStorageUsage() }
        .confirmationDialog(
            "清理待签名 IPA 与临时缓存？",
            isPresented: $confirmsIPACacheClear,
            titleVisibility: .visible
        ) {
            Button("清理", role: .destructive) {
                Task { await viewModel.clearIPAAndSigningCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除尚未签名的导入 IPA 和临时签名工作区。已签名 IPA 与已安装应用的原始 IPA 都会保留。")
        }
        .confirmationDialog(
            "清理临时文件？",
            isPresented: $confirmsTemporaryClear,
            titleVisibility: .visible
        ) {
            Button("清理临时文件", role: .destructive) {
                Task { await viewModel.clearTemporaryFiles() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除签名工作区和临时导入文件，不会删除正式 Signed.ipa。")
        }
        .sealScreenBackground()
    }

    private var summaryCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.sealAccent)
            Text(viewModel.storageUsage.total.sealFormattedByteCount)
                .font(.title2.weight(.semibold))
            Text("Seal 当前本机存储占用")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var usageCard: some View {
        VStack(spacing: 0) {
            usageRow("原始 IPA", viewModel.storageUsage.originalIPAs)
            Divider()
            usageRow("已签名 IPA", viewModel.storageUsage.signedIPAs)
            Divider()
            usageRow("图标与数据", viewModel.storageUsage.appData)
            Divider()
            usageRow("临时缓存", viewModel.storageUsage.temporary)
        }
        .padding(.horizontal, 16)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button("清理待签名 IPA 与临时缓存") { confirmsIPACacheClear = true }
                .sealPrimaryAction(cornerRadius: 12)
            Button("只清理临时缓存") { confirmsTemporaryClear = true }
                .sealOutlineAction(cornerRadius: 12)
        }
    }

    private func usageRow(_ title: String, _ value: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.sealFormattedByteCount)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(minHeight: 54)
    }
}

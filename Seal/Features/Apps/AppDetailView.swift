import SwiftUI
import UIKit

struct AppDetailView: View {
    let appID: UUID
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false

    var body: some View {
        Group {
            if let app = viewModel.apps.first(where: { $0.id == appID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(app)
                        if app.state == .installed { expiryCard(app) }
                        infoCard(app)
                    }
                    .padding(20)
                    .padding(.bottom, 106)
                }
                .safeAreaInset(edge: .bottom) { actionBar(app) }
                .navigationTitle(app.state == .installed ? "应用详情" : "签名安装")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !app.isSeal { ToolbarItem(placement: .topBarTrailing) { Button(role: .destructive) { confirmsDeletion = true } label: { Image(systemName: "trash") } } }
                }
                .confirmationDialog("从 Seal 中移除 \(app.name)？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                    Button("移除记录", role: .destructive) { Task { if await viewModel.delete(app) { dismiss() } } }
                    Button("取消", role: .cancel) {}
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("应用不存在").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sealScreenBackground(.secondary)
    }

    private func header(_ app: AppRecord) -> some View {
        HStack(spacing: 16) {
            icon(app, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.title2.weight(.semibold)).lineLimit(1)
                Text("v\(app.version) (\(app.buildNumber))").font(.subheadline).foregroundStyle(.secondary)
                Text(displayBundleIdentifier(app)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func expiryCard(_ app: AppRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(expiryColor(app))
            VStack(alignment: .leading, spacing: 2) {
                Text(expiryText(app)).font(.title3.weight(.semibold))
                Text(app.expiryDate.map { "到期：\($0.formatted(date: .abbreviated, time: .omitted))" } ?? "等待签名完成").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18).glassSurface(cornerRadius: 24)
    }

    private func infoCard(_ app: AppRecord) -> some View {
        VStack(spacing: 0) {
            detailRow("签名账号", accountName(app))
            Divider()
            detailRow("签名证书", certificateName(app))
            Divider()
            detailRow("导入时间", app.importedAt.formatted(date: .abbreviated, time: .shortened))
            Divider()
            detailRow("原始 Bundle ID", app.originalBundleIdentifier)
            Divider()
            detailRow(app.state == .installed ? "签名后 Bundle ID" : "推荐 Bundle ID", displayBundleIdentifier(app))
            Divider()
            detailRow("Bundle ID 规则", BundleIDPolicy.displayMode(for: app))
            Divider()
            detailRow("应用大小", app.size.formatted(.byteCount(style: .file)))
            Divider()
            detailRow("扩展", app.extensions.isEmpty ? "无" : "\(app.extensions.count) 个")
        }
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 24)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).lineLimit(2).truncationMode(.middle)
        }.padding(.vertical, 15)
    }

    private func actionBar(_ app: AppRecord) -> some View {
        Button(app.state == .installed ? "续签" : "签名并安装") {
            dismiss()
            viewModel.presentOperation(for: app)
        }
        .sealPrimaryAction()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private func icon(_ app: AppRecord, size: CGFloat) -> some View {
        Group {
            if let data = viewModel.iconData[app.id], let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "app.fill").resizable().scaledToFit().padding(12).foregroundStyle(Color.sealAccent).background(.white.opacity(0.6)) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func accountName(_ app: AppRecord) -> String {
        viewModel.accounts.first { $0.id == app.accountID }?.maskedEmail ?? "签名时选择"
    }

    private func certificateName(_ app: AppRecord) -> String {
        guard let serial = app.certificateSerialNumber else {
            return app.state == .installed ? "未记录" : "签名时确定"
        }
        let value = serial.count > 10
            ? "\(serial.prefix(5))…\(serial.suffix(5))"
            : serial
        return "Seal · \(value)"
    }

    private func displayBundleIdentifier(_ app: AppRecord) -> String {
        if app.isSeal { return Bundle.main.bundleIdentifier ?? app.mappedBundleIdentifier ?? app.originalBundleIdentifier }
        if app.state == .installed { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        return app.preferredBundleIdentifier ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
    }
    private func expiryText(_ app: AppRecord) -> String {
        guard let date = app.expiryDate else { return "尚未签名" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "已过期" }
        if interval < 86_400 { return "剩余 \(max(1, Int(interval / 3_600))) 小时" }
        return "剩余 \(max(1, Int(interval / 86_400))) 天"
    }
    private func expiryColor(_ app: AppRecord) -> Color { guard let date = app.expiryDate else { return .secondary }; return date.timeIntervalSinceNow > 86_400 ? .green : .orange }
}

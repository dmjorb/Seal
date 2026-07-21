import SwiftUI
import UIKit

struct AppDetailView: View {
    let appID: UUID
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

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
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("应用不存在")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sealScreenBackground()
    }

    private func header(_ app: AppRecord) -> some View {
        HStack(spacing: 16) {
            icon(app, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(app.name) \(app.version)")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(displayBundleIdentifier(app))
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func expiryCard(_ app: AppRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: expiryIcon(app))
                .font(.title2)
                .foregroundStyle(expiryColor(app))
            VStack(alignment: .leading, spacing: 4) {
                Text(expiryText(app))
                    .font(.title3.weight(.semibold))
                Text(app.expiryDate.map { "到期：\(SealSettingsDateFormatter.string(from: $0))" } ?? "等待签名完成")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
            }
            Spacer()
        }
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private func infoCard(_ app: AppRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("签名账户", accountName(app))
            Divider()
            detailRow("签名证书", certificateName(app))
            Divider()
            detailRow("原始 Bundle ID", app.originalBundleIdentifier)
            Divider()
            detailRow("扩展", app.extensions.isEmpty ? "无" : "\(app.extensions.count) 个")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

    private func actionBar(_ app: AppRecord) -> some View {
        Button(app.state == .installed ? "续签并安装" : "签名并安装") {
            dismiss()
            viewModel.presentOperation(for: app)
        }
        .sealPrimaryAction()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func icon(_ app: AppRecord, size: CGFloat) -> some View {
        Group {
            if let data = viewModel.iconData[app.id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurfaceElevated)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func accountName(_ app: AppRecord) -> String {
        viewModel.accounts.first { $0.id == app.accountID }?.maskedEmail ?? "签名时选择"
    }

    private func certificateName(_ app: AppRecord) -> String {
        guard let serial = app.certificateSerialNumber, serial.isEmpty == false else {
            return app.state == .installed ? "未记录" : "签名时创建"
        }
        return "Seal-\(serial.suffix(8))"
    }

    private func displayBundleIdentifier(_ app: AppRecord) -> String {
        if app.isSeal { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        if app.state == .installed { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        return app.preferredBundleIdentifier ?? app.originalBundleIdentifier
    }

    private func expiryText(_ app: AppRecord) -> String {
        guard let date = app.expiryDate else { return "尚未签名" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "已过期" }
        if interval < 86_400 { return "剩余 \(max(1, Int(interval / 3_600))) 小时" }
        return "剩余 \(max(1, Int(interval / 86_400))) 天"
    }

    private func expiryIcon(_ app: AppRecord) -> String {
        guard let date = app.expiryDate else { return "clock" }
        return date.timeIntervalSinceNow <= 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    private func expiryColor(_ app: AppRecord) -> Color {
        guard let date = app.expiryDate else { return .sealTextSecondary }
        return date.timeIntervalSinceNow > 86_400 ? .sealSuccess : .sealWarning
    }
}

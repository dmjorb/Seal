import SwiftUI
import UIKit

struct AppDetailView: View {
    let appID: UUID
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let app = viewModel.apps.first(where: { $0.id == appID }) {
                SealDrawer(title: app.state == .installed ? "应用详情" : "应用详情") {
                    VStack(alignment: .leading, spacing: 20) {
                        header(app)
                        if app.state == .installed { expiryCard(app) }
                        infoCard(app)
                    }
                    .padding(.bottom, 8)
                } footer: {
                    detailAction(app)
                }
            } else {
                SealDrawer(title: "应用详情") {
                    VStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("应用不存在")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } footer: {
                    Button("关闭") { dismiss() }
                        .sealOutlineAction(cornerRadius: 14)
                }
            }
        }
        .alert(item: $viewModel.alertFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.userMessage),
                dismissButton: .default(Text(failure.recovery))
            )
        }
    }

    private func header(_ app: AppRecord) -> some View {
        HStack(spacing: 16) {
            icon(app, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(app.name) \(app.version)")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                bundleIdentifierValue(displayBundleIdentifier(app), compactAfterSeal: true)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.sealTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            identifierDetailRow("Bundle ID", signedBundleIdentifier(app), compactAfterSeal: true)
            Divider()
            identifierDetailRow("原始 Bundle ID", app.originalBundleIdentifier, compactAfterSeal: false)
            Divider()
            detailRow("描述文件", profileSummary(app))
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

    private func identifierDetailRow(
        _ title: String,
        _ value: String,
        compactAfterSeal: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            bundleIdentifierValue(value, compactAfterSeal: compactAfterSeal)
                .foregroundStyle(Color.sealTextSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private func bundleIdentifierValue(_ value: String, compactAfterSeal: Bool) -> some View {
        let compactValue = compactAfterSeal ? compactSignedBundleIdentifier(value) : value
        ViewThatFits(in: .horizontal) {
            Text(value)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(compactValue)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .multilineTextAlignment(.trailing)
    }

    @ViewBuilder
    private func detailAction(_ app: AppRecord) -> some View {
        if app.state == .signed || app.hasSignedArtifact && app.state != .installed {
            Button {
                Task {
                    if await viewModel.installSignedArtifact(app) { dismiss() }
                }
            } label: {
                if viewModel.installingSignedAppID == app.id {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("安装")
                }
            }
            .sealPrimaryAction(cornerRadius: 14)
            .disabled(viewModel.installingSignedAppID == app.id)
        } else {
            Button(app.state == .installed ? "立即续签" : "签名并安装") {
                dismiss()
                viewModel.presentOperation(for: app)
            }
            .sealPrimaryAction(cornerRadius: 14)
        }
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
        guard let account = viewModel.accounts.first(where: { $0.id == app.accountID }) else {
            return "签名时选择"
        }
        return viewModel.fullEmail(for: account)
    }

    private func compactSignedBundleIdentifier(_ value: String) -> String {
        guard let markerRange = value.range(of: ".seal.", options: .backwards) else {
            return value
        }
        let prefix = String(value[..<markerRange.upperBound])
        let suffix = String(value[markerRange.upperBound...])
        guard suffix.count > 8 else {
            return value
        }
        return "\(prefix)\(suffix.prefix(4))…\(suffix.suffix(4))"
    }

    private func certificateName(_ app: AppRecord) -> String {
        if let serial = app.certificateSerialNumber, serial.isEmpty == false {
            return "Seal-\(serial.suffix(8))"
        }
        if let serial = app.signingTargets
            .flatMap(\.certificateSerialNumbers)
            .first(where: { $0.isEmpty == false }) {
            return "Seal-\(serial.suffix(8))"
        }
        return app.state == .installed ? "续签时重新确认" : "签名时创建"
    }

    private func signedBundleIdentifier(_ app: AppRecord) -> String {
        app.mappedBundleIdentifier
            ?? app.preferredBundleIdentifier
            ?? (app.state == .installed ? "未记录" : app.originalBundleIdentifier)
    }

    private func profileSummary(_ app: AppRecord) -> String {
        if let uuid = app.provisioningProfileUUID, uuid.isEmpty == false {
            return uuid
        }
        if let date = app.provisioningProfileExpirationDate ?? app.expiryDate {
            return "到期 \(SealSettingsDateFormatter.string(from: date))"
        }
        return app.state == .installed ? "未记录" : "签名后生成"
    }

    private func displayBundleIdentifier(_ app: AppRecord) -> String {
        if app.state == .installed {
            return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier
        }
        return app.preferredBundleIdentifier ?? app.originalBundleIdentifier
    }

    private func expiryText(_ app: AppRecord) -> String {
        guard let date = app.expiryDate else { return "尚未签名" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "已过期" }
        if interval < 86_400 { return "\(max(1, Int(interval / 3_600)))小时" }
        return "\(max(1, Int(interval / 86_400)))天"
    }

    private func expiryIcon(_ app: AppRecord) -> String {
        guard let date = app.expiryDate else { return "clock" }
        return date.timeIntervalSinceNow <= 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    private func expiryColor(_ app: AppRecord) -> Color {
        guard let date = app.expiryDate else { return .sealTextSecondary }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 || interval < 86_400 { return .sealDanger }
        if interval < 4 * 86_400 { return .sealWarning }
        return .sealTextSecondary
    }
}

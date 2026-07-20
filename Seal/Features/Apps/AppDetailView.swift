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
                Text(displayBundleIdentifier(app))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: 0) {
            detailRow("签名账号", accountName(app))
            Divider()
            if let teamID = app.signingTeamID ?? viewModel.accounts.first(where: { $0.id == app.accountID })?.teamID {
                FullIdentifierRow(title: "Team ID", value: teamID)
                Divider()
            }
            if let serial = app.certificateSerialNumber {
                FullIdentifierRow(title: "证书 Serial", value: serial)
                Divider()
            } else {
                detailRow("签名证书", app.state == .installed ? "未记录" : "签名时创建或选择")
                Divider()
            }
            if let udid = app.signedDeviceIdentifier {
                FullIdentifierRow(title: "设备 UDID", value: udid)
                Divider()
            }
            FullIdentifierRow(title: "原始 Bundle ID", value: app.originalBundleIdentifier)
            Divider()
            FullIdentifierRow(
                title: app.state == .installed ? "签名后 Bundle ID" : "目标 Bundle ID",
                value: displayBundleIdentifier(app)
            )
            if let profileUUID = app.provisioningProfileUUID {
                Divider()
                FullIdentifierRow(title: "Profile UUID", value: profileUUID)
            }
            if let profileName = app.provisioningProfileName {
                Divider()
                FullIdentifierRow(title: "Profile 名称", value: profileName)
            }
            Divider()
            detailRow("导入时间", app.importedAt.formatted(date: .abbreviated, time: .shortened))
            Divider()
            detailRow("应用大小", app.size.formatted(.byteCount(style: .file)))
            Divider()
            detailRow("扩展", app.extensions.isEmpty ? "无" : "\(app.extensions.count) 个")

            ForEach(Array(app.extensions.enumerated()), id: \.offset) { index, appExtension in
                Divider()
                FullIdentifierRow(
                    title: "扩展 \(index + 1) Bundle ID",
                    value: appExtension.mappedBundleIdentifier ?? appExtension.originalBundleIdentifier
                )
                if let profileUUID = appExtension.provisioningProfileUUID {
                    FullIdentifierRow(
                        title: "扩展 \(index + 1) Profile UUID",
                        value: profileUUID
                    )
                }
            }

            ForEach(Array(app.signingTargets.enumerated()), id: \.element.id) { index, target in
                Divider()
                Text("签名目标 \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 12)
                FullIdentifierRow(title: "Bundle ID", value: target.bundleIdentifier)
                if let profileUUID = target.profileUUID, profileUUID.isEmpty == false {
                    FullIdentifierRow(title: "Profile UUID", value: profileUUID)
                }
                if let profileName = target.profileName, profileName.isEmpty == false {
                    FullIdentifierRow(title: "Profile 名称", value: profileName)
                }
                FullIdentifierRow(title: "Profile Team ID", value: target.teamIdentifier)
                if target.certificateSerialNumbers.isEmpty == false {
                    FullIdentifierRow(
                        title: "Profile 证书 Serial",
                        value: target.certificateSerialNumbers.joined(separator: "\n")
                    )
                }
                if target.deviceIdentifiers.isEmpty == false {
                    FullIdentifierRow(
                        title: "Profile 设备 UDID",
                        value: target.deviceIdentifiers.joined(separator: "\n")
                    )
                }
                if target.entitlementKeys.isEmpty == false {
                    FullIdentifierRow(
                        title: "Profile Entitlements",
                        value: target.entitlementKeys.joined(separator: "\n")
                    )
                }
                detailRow(
                    "Profile 到期",
                    target.profileExpirationDate.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 24)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 15)
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

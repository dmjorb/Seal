import SwiftUI
import UIKit

enum AppListPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case unsigned = "待签名"
    case signed = "已签名"
    case installed = "已安装"

    var id: Self { self }

    var sectionTitle: String {
        switch self {
        case .unsigned: "待签名应用"
        case .signed: "已签名 IPA"
        case .installed: "已安装应用"
        }
    }
}

struct ImportedAppRow: View {
    let app: AppRecord
    let mode: AppListPresentationMode
    let displayName: String
    let iconData: Data?
    let signedIPAFileStatus: SignedIPAFileStatus?

    var body: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("v\(app.version)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                BundleIdentifierText(displayBundleIdentifier)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("imported-app-row")
    }

    private var displayBundleIdentifier: String {
        switch mode {
        case .unsigned:
            return app.preferredBundleIdentifier
                ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
        case .signed, .installed:
            return app.mappedBundleIdentifier
                ?? app.preferredBundleIdentifier
                ?? app.originalBundleIdentifier
        }
    }

    @ViewBuilder private var icon: some View {
        Group {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(11)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurface)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(trailingTop)
                .font(.subheadline.weight(mode == .unsigned ? .regular : .semibold))
                .foregroundStyle(trailingColor)
                .lineLimit(1)

            Text(trailingBottom ?? " ")
                .font(.caption)
                .foregroundStyle(Color.sealTextSecondary)
                .lineLimit(1)
                .accessibilityHidden(trailingBottom == nil)
        }
        .frame(minWidth: 82, alignment: .trailing)
    }

    private var trailingTop: String {
        switch mode {
        case .unsigned:
            return app.size.formatted(.byteCount(style: .file))
        case .signed:
            switch signedIPAFileStatus {
            case .missing: return "文件缺失"
            case .invalid: return "文件损坏"
            case .available, .none:
                return AppValidityFormatter.text(
                    expiryDate: app.provisioningProfileExpirationDate ?? app.expiryDate,
                    fallback: "已签名"
                )
            }
        case .installed:
            return AppValidityFormatter.text(expiryDate: app.expiryDate, fallback: "已安装")
        }
    }

    private var trailingBottom: String? {
        switch mode {
        case .unsigned:
            return AppImportTimeFormatter.string(from: app.importedAt)
        case .signed:
            return AppImportTimeFormatter.string(from: app.lastSignedAt ?? app.importedAt)
        case .installed:
            return nil
        }
    }

    private var trailingColor: Color {
        guard mode != .unsigned else { return .sealTextSecondary }
        if mode == .signed {
            switch signedIPAFileStatus {
            case .missing, .invalid: return .sealDanger
            case .available, .none: break
            }
        }
        let expiry = mode == .signed
            ? (app.provisioningProfileExpirationDate ?? app.expiryDate)
            : app.expiryDate
        switch AppValidityFormatter.presentation(expiryDate: expiry)?.tone {
        case .danger: return .sealDanger
        case .warning: return .sealWarning
        case .success, .neutral, nil: return .sealTextSecondary
        }
    }

    private var accessibilityLabel: String {
        let parts: [String?] = [
            displayName,
            "版本 \(app.version)",
            displayBundleIdentifier,
            trailingTop,
            trailingBottom
        ]
        return parts.compactMap { $0 }.joined(separator: "，")
    }

    private var accessibilityHint: String {
        switch mode {
        case .unsigned: "双击打开签名、仅签名或删除操作"
        case .signed: "双击打开安装、导出或删除操作"
        case .installed: "双击打开续签操作"
        }
    }
}

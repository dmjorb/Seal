import SwiftUI
import UIKit

struct ImportedAppRow: View {
    let app: AppRecord
    let iconData: Data?

    var body: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(app.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("v\(app.version)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }

                bundleIdentifierText
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [app.displayName, "版本 \(app.version)", displayBundleIdentifier, trailingLabel]
                .joined(separator: "，")
        )
        .accessibilityIdentifier("imported-app-row")
    }

    private var displayBundleIdentifier: String {
        if app.state == .installed || app.state == .signed || app.hasSignedArtifact || app.isSeal {
            return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier
        }
        return app.preferredBundleIdentifier ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
    }

    @ViewBuilder
    private var bundleIdentifierText: some View {
        let identifier = displayBundleIdentifier
        if identifier.lowercased().hasSuffix(".seal"), identifier.count > 5 {
            let prefix = String(identifier.dropLast(5))
            Text(prefix).foregroundColor(Color.sealTextSecondary)
                + Text(".seal").foregroundColor(Color.sealAccent)
        } else {
            Text(identifier).foregroundStyle(Color.sealTextSecondary)
        }
    }

    @ViewBuilder private var icon: some View {
        Group {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(11)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurface)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        if app.state == .installed || app.isSeal {
            let validity = AppOperationPresentation(app: app).validity
            Text(validity?.text ?? "已安装")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: validity?.tone))
                .frame(minWidth: 70, alignment: .trailing)
        } else if app.state == .signed || app.hasSignedArtifact {
            VStack(alignment: .trailing, spacing: 5) {
                Text(signedValidityText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(signedValidityColor)
                Text(AppImportTimeFormatter.string(from: app.lastSignedAt ?? app.importedAt))
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary)
            }
            .frame(minWidth: 82, alignment: .trailing)
        } else {
            VStack(alignment: .trailing, spacing: 5) {
                Text(app.size.formatted(.byteCount(style: .file)))
                    .font(.subheadline)
                Text(AppImportTimeFormatter.string(from: app.importedAt))
                    .font(.caption)
            }
            .foregroundStyle(Color.sealTextSecondary)
            .frame(minWidth: 82, alignment: .trailing)
        }
    }

    private var signedValidity: AppValidityPresentation? {
        guard let expiry = app.provisioningProfileExpirationDate ?? app.expiryDate else { return nil }
        var copy = app
        copy.state = .installed
        copy.expiryDate = expiry
        return AppOperationPresentation(app: copy).validity
    }

    private var signedValidityText: String {
        if app.signedArtifactStatus == .missing { return "文件缺失" }
        if app.signedArtifactStatus == .damaged { return "文件损坏" }
        if app.signedArtifactStatus == .deviceUnavailable { return "设备不可用" }
        return signedValidity?.text ?? app.signedArtifactStatus?.title ?? "已签名"
    }

    private var signedValidityColor: Color {
        if let status = app.signedArtifactStatus,
           [SignedArtifactStatus.missing, .damaged, .deviceUnavailable, .expired].contains(status) {
            return .sealDanger
        }
        return color(for: signedValidity?.tone)
    }

    private var trailingLabel: String {
        if app.state == .installed || app.isSeal {
            return AppOperationPresentation(app: app).validity?.text ?? "已安装"
        }
        if app.state == .signed || app.hasSignedArtifact {
            return "\(signedValidityText)，\(AppImportTimeFormatter.string(from: app.lastSignedAt ?? app.importedAt))"
        }
        return "\(app.size.formatted(.byteCount(style: .file)))，\(AppImportTimeFormatter.string(from: app.importedAt))"
    }

    private func color(for tone: AppValidityTone?) -> Color {
        switch tone {
        case .success: .sealSuccess
        case .warning: .sealWarning
        case .danger: .sealDanger
        case .neutral, nil: .sealTextSecondary
        }
    }
}

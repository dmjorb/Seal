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
                    Text(app.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("v\(app.version)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }

                Text(displayBundleIdentifier)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [app.name, "版本 \(app.version)", app.originalBundleIdentifier, trailingLabel]
                .joined(separator: "，")
        )
        .accessibilityIdentifier("imported-app-row")
    }

    private var displayBundleIdentifier: String {
        if app.isSeal { return Bundle.main.bundleIdentifier ?? app.mappedBundleIdentifier ?? app.originalBundleIdentifier }
        if app.state == .installed { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        return app.preferredBundleIdentifier ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(for: validity?.tone))
                .frame(minWidth: 58, alignment: .trailing)
        } else {
            VStack(alignment: .trailing, spacing: 5) {
                Text(app.size.formatted(.byteCount(style: .file)))
                    .font(.system(size: 14, weight: .regular))
                Text(AppImportTimeFormatter.string(from: app.importedAt))
                    .font(.system(size: 13, weight: .regular))
            }
            .foregroundStyle(Color.sealTextSecondary)
            .frame(minWidth: 82, alignment: .trailing)
        }
    }

    private var trailingLabel: String {
        if app.state == .installed || app.isSeal {
            return AppOperationPresentation(app: app).validity?.text ?? "已安装"
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

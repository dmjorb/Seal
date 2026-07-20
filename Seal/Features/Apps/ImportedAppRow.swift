import SwiftUI
import UIKit

struct ImportedAppRow: View {
    let app: AppRecord
    let iconData: Data?

    var body: some View {
        HStack(spacing: 18) {
            icon

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("–v\(app.version)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }

                Text(displayBundleIdentifier)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)
            trailing
        }
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
        if SelfManagedSealMigrationPolicy.isMigrationPackage(app) { return "Seal 自续签版" }
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
                    .padding(12)
                    .foregroundStyle(Color.sealAccent)
                    .background(.white.opacity(0.72))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        if app.state == .installed {
            let validity = AppOperationPresentation(app: app).validity
            Text(validity?.text ?? "已安装")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color(for: validity?.tone))
                .frame(minWidth: 92, alignment: .trailing)
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                Text(app.size.formatted(.byteCount(style: .file)))
                    .font(.system(size: 16, weight: .regular))
                Text(AppImportTimeFormatter.string(from: app.importedAt))
                    .font(.system(size: 16, weight: .regular))
            }
            .foregroundStyle(Color.sealTextSecondary)
            .frame(minWidth: 100, alignment: .trailing)
        }
    }

    private var trailingLabel: String {
        if app.state == .installed {
            return AppOperationPresentation(app: app).validity?.text ?? "已安装"
        }
        return "\(app.size.formatted(.byteCount(style: .file)))，\(AppImportTimeFormatter.string(from: app.importedAt))"
    }

    private func color(for tone: AppValidityTone?) -> Color {
        switch tone {
        case .warning: .sealWarning
        case .danger: .sealDanger
        case .neutral, nil: .sealTextSecondary
        }
    }
}

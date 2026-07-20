import SwiftUI

struct EnvironmentStatusGlass: View {
    let snapshot: EnvironmentSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.isConfigured
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(snapshot.isConfigured ? Color.green : Color.orange)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.isConfigured ? "签名环境已配置" : "签名环境未配置")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(actionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sealAccent)
        }
        .padding()
        .glassSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("environment-status-glass")
    }

    private var detail: String {
        switch snapshot.nextSetupStep {
        case .account:
            return snapshot.accountCount == 0 ? "添加 Apple ID" : "重新验证 Apple ID"
        case .pairing:
            return "导入配对文件"
        case nil:
            return "签名准备已完成"
        }
    }

    private var actionTitle: String {
        switch snapshot.nextSetupStep {
        case .account: return "添加"
        case .pairing: return "导入"
        case nil: return ""
        }
    }
}

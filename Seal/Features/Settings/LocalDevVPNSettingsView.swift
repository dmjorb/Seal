import SwiftUI

struct LocalDevVPNSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                hero
                detailsCard
                actions
                helperCard
            }
            .padding(20)
        }
        .navigationTitle("LocalDevVPN")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground(.secondary)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: heroIcon)
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(statusTitle)
                .font(.title2.weight(.semibold))
            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.installDiagnostics.steps.enumerated()), id: \.offset) { index, step in
                diagnosticRow(step)
                if index < viewModel.installDiagnostics.steps.count - 1 {
                    Divider()
                }
            }
            Divider()
            FullIdentifierRow(title: "设备 UDID", value: deviceIdentifier)
            if let failureCode {
                Divider()
                detailRow("错误代码", failureCode, Color.sealDanger)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var actions: some View {
        Button("打开 LocalDevVPN") {
            openURL(LocalDevVPNLink.enableAndReturn) { accepted in
                guard accepted == false else { return }
                openURL(LocalDevVPNLink.appStore)
            }
        }
        .sealPrimaryAction(cornerRadius: 12)
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.headline)
            Text("Seal 通过 LocalDevVPN 建立本机安装通道。打开或恢复 VPN 后，请返回设置页，在 LocalDevVPN 下方点击“一键检测”，统一检查 Apple ID、证书、配对文件和安装通道。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }


    private func diagnosticRow(_ step: InstallDiagnosticStep) -> some View {
        let color: Color = {
            switch step.status {
            case .passed: return .sealSuccess
            case .running: return .sealAccent
            case .failed: return .sealDanger
            case .pending: return Color.sealTextSecondary
            }
        }()
        return HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: iconName(for: step.status))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
            Text(step.title)
            Spacer(minLength: 12)
            Text(step.valueText)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(minHeight: 54)
    }

    private func iconName(for status: InstallDiagnosticStep.Status) -> String {
        switch status {
        case .passed: "checkmark"
        case .running: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark"
        case .pending: "minus"
        }
    }

    private func detailRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(minHeight: 54)
    }

    private var heroIcon: String {
        if case .ready = viewModel.diagnosticState {
            return "checkmark.circle.fill"
        }
        if case .running = viewModel.diagnosticState {
            return "arrow.triangle.2.circlepath"
        }
        if installFailure != nil {
            return "exclamationmark.triangle.fill"
        }
        return "network"
    }

    private var statusTitle: String {
        if case .ready = viewModel.diagnosticState {
            return "LocalDevVPN 已连接"
        }
        if case .running = viewModel.diagnosticState {
            return "正在检测连接"
        }
        if let installFailure {
            return installFailure.title
        }
        return "尚未检测"
    }

    private var statusSubtitle: String {
        if case .ready = viewModel.diagnosticState {
            return "安装通道可用，可以签名和续签应用"
        }
        if case .running = viewModel.diagnosticState {
            return "正在分层检测 VPN 通道、配对文件、设备响应和安装服务"
        }
        if let installFailure {
            return installFailure.reason
        }
        return "返回设置页点击“一键检测”确认当前连接状态"
    }

    private var statusColor: Color {
        if case .ready = viewModel.diagnosticState {
            return .sealSuccess
        }
        if case .running = viewModel.diagnosticState {
            return .sealAccent
        }
        return installFailure == nil ? Color.sealTextSecondary : .sealDanger
    }

    private var installFailure: ImportFailure? {
        guard case .failed(let failure) = viewModel.diagnosticState else {
            return nil
        }
        return failure.code.hasPrefix("SEAL-INSTALL-")
            || failure.code.hasPrefix("SEAL-PAIR-")
            ? failure
            : nil
    }

    private var deviceIdentifier: String {
        if let id = viewModel.installDiagnostics.deviceIdentifier { return id }
        if case .ready(let id) = viewModel.diagnosticState { return id }
        return "—"
    }

    private var failureCode: String? {
        installFailure?.code
    }
}

import SwiftUI

struct LocalDevVPNSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    @State private var isChecking = false

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
            detailRow("设备标识", deviceIdentifier, Color.sealTextSecondary)
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
        VStack(spacing: 12) {
            Button("打开 LocalDevVPN") {
                openURL(LocalDevVPNLink.enableAndReturn) { accepted in
                    guard accepted == false else { return }
                    openURL(LocalDevVPNLink.appStore)
                }
            }
            .sealPrimaryAction(cornerRadius: 12)

            Button(isChecking ? "检测中…" : "重新检测") {
                guard isChecking == false else { return }
                isChecking = true
                Task {
                    await viewModel.testLocalDevVPN()
                    isChecking = false
                }
            }
            .sealOutlineAction(cornerRadius: 12)
            .disabled(isChecking)
        }
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.headline)
            Text("Seal 通过 LocalDevVPN 建立本机安装通道。未连接时，签名、安装和续签都会被暂停，避免生成不可安装的结果。打开 LocalDevVPN 后回到 Seal，重新检测即可继续。")
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
                .lineLimit(1)
                .truncationMode(.middle)
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
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minHeight: 54)
    }

    private var heroIcon: String {
        switch viewModel.diagnosticState {
        case .ready: return "checkmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "network"
        }
    }

    private var statusTitle: String {
        switch viewModel.diagnosticState {
        case .ready: return "LocalDevVPN 已连接"
        case .running: return "正在检测连接"
        case .failed(let failure): return failure.title
        case .idle: return "尚未检测"
        }
    }

    private var statusSubtitle: String {
        switch viewModel.diagnosticState {
        case .ready: return "安装通道可用，可以签名和续签应用"
        case .running: return "正在分层检测 VPN 通道、配对文件、设备响应和安装服务"
        case .failed(let failure): return failure.reason
        case .idle: return "点击重新检测确认当前设备连接状态"
        }
    }

    private var statusColor: Color {
        switch viewModel.diagnosticState {
        case .ready: return .sealSuccess
        case .running: return .sealAccent
        case .failed: return .sealDanger
        case .idle: return Color.sealTextSecondary
        }
    }

    private var deviceIdentifier: String {
        if let id = viewModel.installDiagnostics.deviceIdentifier { return id }
        if case .ready(let id) = viewModel.diagnosticState { return id }
        return "—"
    }

    private var failureCode: String? {
        if case .failed(let failure) = viewModel.diagnosticState { return failure.code }
        return nil
    }
}

import SwiftUI
import UIKit

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
            }
            .padding(20)
        }
        .navigationTitle("LocalDevVPN")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground()
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
        .glassSurface(cornerRadius: 24)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("设备响应", deviceResponseText, deviceResponseColor)
            Divider()
            detailRow("安装服务", installServiceText, installServiceColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 18)
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

            Button(isChecking ? "正在检测…" : "重新检测") {
                guard isChecking == false else { return }
                isChecking = true
                Task {
                    await viewModel.testConnection()
                    isChecking = false
                }
            }
            .sealOutlineAction(cornerRadius: 12)
            .disabled(isChecking)
        }
    }

    private func detailRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 54)
    }

    private var heroIcon: String {
        if case .ready = viewModel.diagnosticState { return "checkmark.circle.fill" }
        if case .running = viewModel.diagnosticState { return "arrow.triangle.2.circlepath" }
        if installFailure != nil { return "exclamationmark.triangle.fill" }
        return "network"
    }

    private var statusTitle: String {
        if case .ready = viewModel.diagnosticState { return "LocalDevVPN 已连接" }
        if case .running = viewModel.diagnosticState { return "正在检测连接" }
        if installFailure != nil { return "LocalDevVPN 未连接" }
        return "尚未检测"
    }

    private var statusSubtitle: String {
        if case .ready = viewModel.diagnosticState { return "安装通道可用，可以签名和续签应用" }
        if case .running = viewModel.diagnosticState { return "正在检测设备响应和安装服务" }
        if let installFailure { return installFailure.userReason }
        return "打开 LocalDevVPN 后，点击重新检测确认安装通道。"
    }

    private var statusColor: Color {
        if case .ready = viewModel.diagnosticState { return .sealSuccess }
        if case .running = viewModel.diagnosticState { return .sealAccent }
        return installFailure == nil ? Color.sealTextSecondary : .sealDanger
    }

    private var installFailure: ImportFailure? {
        guard case .failed(let failure) = viewModel.diagnosticState else { return nil }
        return failure.code.hasPrefix("SEAL-INSTALL-") || failure.code.hasPrefix("SEAL-PAIR-") ? failure : nil
    }

    private var deviceResponseText: String {
        switch viewModel.diagnosticState {
        case .ready: return "正常"
        case .running: return "检测中"
        case .failed: return "不可用"
        case .idle: return "未检测"
        }
    }

    private var installServiceText: String {
        switch viewModel.diagnosticState {
        case .ready: return "可用"
        case .running: return "检测中"
        case .failed: return "不可用"
        case .idle: return "未检测"
        }
    }

    private var deviceResponseColor: Color {
        if case .ready = viewModel.diagnosticState { return .sealSuccess }
        if case .failed = viewModel.diagnosticState { return .sealDanger }
        return .sealTextSecondary
    }

    private var installServiceColor: Color { deviceResponseColor }
}

import SwiftUI
import UIKit

struct SigningProgressView: View {
    @ObservedObject var viewModel: AppsViewModel
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                SealSheetGrabber()

                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.primary)

                if let app = session?.app {
                    appIdentity(app)
                }

                if let session {
                    signingRuntimeCard(session)
                }

                statusContent
                actions
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .sealSheetBackground()
        .interactiveDismissDisabled(isRunning)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch session?.status {
        case .running(let stage):
            runningContent(stage)
        case .succeeded(let installed):
            successContent(installed)
        case .failed(let failure):
            failureContent(failure)
        case nil:
            EmptyView()
        }
    }

    private func runningContent(_ stage: SigningStage) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress(for: stage))
                    .stroke(
                        Color.sealAccent,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress(for: stage) * 100))%")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 112, height: 112)
            .padding(.top, 2)

            VStack(spacing: 7) {
                Text(runningStatusTitle(for: stage))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("请保持 Seal 在前台运行")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
            }

            stageTimeline(activeStage: stage)
        }
    }

    private func successContent(_ installed: AppRecord) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.sealSuccess)
                .frame(width: 112, height: 112)
                .background(Color.sealSuccess.opacity(0.12), in: Circle())

            VStack(spacing: 7) {
                Text(isRenewal ? "续签并安装成功" : "签名并安装成功")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(expiryText(for: installed))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sealTextSecondary)
            }

            completedTimeline
        }
    }

    private func failureContent(_ failure: ImportFailure) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color.sealDanger)
                .frame(width: 104, height: 104)
                .overlay {
                    Circle().stroke(Color.sealDanger.opacity(0.22), lineWidth: 3)
                }

            VStack(spacing: 9) {
                Text(isRenewal ? "无法完成续签" : "无法完成签名")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(userFacingReason(failure))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recoveryText(failure))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch session?.status {
        case .running:
            Button(isRenewal ? "续签中…" : "签名中…") {}
                .sealSecondaryDisabledAction(cornerRadius: 14)
                .disabled(true)

        case .succeeded:
            Button("回到列表") { finish() }
                .sealPrimaryAction(cornerRadius: 14)
            Button("完成") { finish() }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .buttonStyle(.plain)
                .foregroundStyle(Color.sealAccent)

        case .failed(let failure):
            Button(primaryRecoveryTitle(failure)) {
                performPrimaryRecovery(failure)
            }
            .sealPrimaryAction(cornerRadius: 14)

            if shouldOfferRetry(failure) {
                Button("重新尝试") { viewModel.retrySigning() }
                    .sealOutlineAction(cornerRadius: 14)
            }
            Button("取消") {
                viewModel.dismissSigningResult()
                dismiss()
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 38)
            .buttonStyle(.plain)
            .foregroundStyle(Color.sealAccent)

        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            switch session?.status {
            case .running:
                Text("完成前请勿关闭应用")
            case .succeeded:
                Text("到期前将自动提醒")
            case .failed:
                Text(isRenewal ? "应用和现有安装不会被删除" : "IPA 文件已保留，不需要重新导入")
            case nil:
                EmptyView()
            }
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(Color.sealTextSecondary)
        .multilineTextAlignment(.center)
    }

    private func signingRuntimeCard(_ session: SigningSession) -> some View {
        VStack(spacing: 0) {
            runtimeRow("Apple ID", session.account.maskedEmail)
            Divider().padding(.leading, 14)
            runtimeRow("签名证书", certificateDisplayName(session))
            Divider().padding(.leading, 14)
            runtimeRow("Bundle ID", runtimeBundleIdentifier(session))
        }
        .padding(.horizontal, 14)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func runtimeRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: title.contains("Bundle") || title.contains("证书") ? .monospaced : .default))
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 48)
    }

    private func certificateDisplayName(_ session: SigningSession) -> String {
        guard let serial = session.selectedCertificateSerialNumber ?? session.account.certificateSerialNumber,
              serial.isEmpty == false else {
            return "签名时创建"
        }
        return "Seal-\(serial.suffix(8))"
    }

    private func runtimeBundleIdentifier(_ session: SigningSession) -> String {
        if let requested = session.requestedBundleIdentifier, requested.isEmpty == false {
            return requested
        }
        return displayBundleIdentifier(session.app)
    }

    private func appIdentity(_ app: AppRecord) -> some View {
        HStack(spacing: 18) {
            appIcon(app, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(app.name)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("–v\(app.version)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
                Text(displayBundleIdentifier(app))
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayBundleIdentifier(_ app: AppRecord) -> String {
        if app.isSeal { return Bundle.main.bundleIdentifier ?? app.mappedBundleIdentifier ?? app.originalBundleIdentifier }
        if app.state == .installed { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        return app.preferredBundleIdentifier ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
    }

    private func stageTimeline(activeStage: SigningStage) -> some View {
        let activeIndex = SigningStage.allCases.firstIndex(of: activeStage) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(SigningStage.allCases.enumerated()), id: \.offset) { index, stage in
                HStack(alignment: .top, spacing: 13) {
                    VStack(spacing: 0) {
                        timelineMarker(for: index, activePosition: activeIndex)
                        if index < SigningStage.allCases.count - 1 {
                            Rectangle()
                                .fill(timelineLineColor(for: index, activePosition: activeIndex))
                                .frame(width: 2, height: 18)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.userVisibleTitle(isRenewal: isRenewal))
                            .font(.system(size: 16, weight: index == activeIndex ? .semibold : .regular))
                            .foregroundStyle(index == activeIndex ? .primary : Color.sealTextSecondary)
                        if index == activeIndex {
                            Text("正在执行")
                                .font(.caption)
                                .foregroundStyle(Color.sealAccent)
                        }
                    }
                    .padding(.top, -1)
                }
            }
        }
        .padding(.top, 2)
    }

    private var completedTimeline: some View {
        let steps = SigningStage.allCases.map { $0.userVisibleTitle(isRenewal: isRenewal) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                HStack(alignment: .top, spacing: 13) {
                    VStack(spacing: 0) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.sealSuccess)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(Color.sealSuccess)
                                .frame(width: 2, height: 22)
                        }
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.sealTextSecondary)
                        .padding(.top, -1)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func timelineMarker(for position: Int, activePosition: Int) -> some View {
        if position < activePosition {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.sealSuccess)
        } else if position == activePosition {
            ZStack {
                Circle()
                    .fill(Color.sealAccent.opacity(0.16))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.sealAccent)
                    .frame(width: 11, height: 11)
            }
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 10, height: 10)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func appIcon(_ app: AppRecord, size: CGFloat) -> some View {
        Group {
            if let data = viewModel.iconData[app.id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var session: SigningSession? { viewModel.signingSession }

    private var isRenewal: Bool { session?.app.state == .installed }

    private var title: String {
        switch session?.status {
        case .running: isRenewal ? "正在续签" : "正在签名"
        case .succeeded: isRenewal ? "续签完成" : "签名完成"
        case .failed: isRenewal ? "续签失败" : "签名失败"
        case nil: "签名"
        }
    }

    private var isRunning: Bool {
        if case .running = session?.status { return true }
        return false
    }

    private func progress(for stage: SigningStage) -> Double {
        switch stage {
        case .waitingForChannel: 0.10
        case .preparingAccount: 0.20
        case .preparingCertificate: 0.33
        case .preparingProfiles: 0.48
        case .signing: 0.62
        case .installing: 0.82
        case .verifying: 0.94
        }
    }

    private func timelinePosition(for stage: SigningStage) -> Int {
        switch stage {
        case .waitingForChannel, .preparingAccount, .preparingCertificate, .preparingProfiles:
            0
        case .signing:
            1
        case .installing, .verifying:
            2
        }
    }

    private func timelineLineColor(for position: Int, activePosition: Int) -> Color {
        position < activePosition ? Color.sealSuccess : Color.secondary.opacity(0.25)
    }

    private func runningStatusTitle(for stage: SigningStage) -> String {
        if timelinePosition(for: stage) == 2 { return "等待安装" }
        if timelinePosition(for: stage) == 1 { return isRenewal ? "正在续签" : "正在签名" }
        return stage.title
    }

    private func expiryText(for installed: AppRecord) -> String {
        guard let expiryDate = installed.expiryDate else { return "应用已安装" }
        return "到期：\(SealSettingsDateFormatter.string(from: expiryDate))"
    }

    private func primaryRecoveryTitle(_ failure: ImportFailure) -> String {
        if isAuthFailure(failure) { return "重新验证 Apple ID" }
        if isCertificateFailure(failure) { return "前往签名证书" }
        if isAppIDFailure(failure) { return "更换 Apple ID 或 Bundle ID" }
        if isPairingFailure(failure) { return "重新导入配对文件" }
        if isInstallChannelFailure(failure) { return "打开 LocalDevVPN" }
        if failure.code == "SEAL-EXT-401" { return "移除扩展并重试" }
        return "查看设置"
    }

    private func performPrimaryRecovery(_ failure: ImportFailure) {
        if isAuthFailure(failure) {
            openSettings(.account)
        } else if isCertificateFailure(failure) {
            openSettings(.certificates)
        } else if isAppIDFailure(failure) {
            if session?.app.isSeal == true || session?.app.state == .installed {
                openSettings(.account)
            } else {
                viewModel.dismissSigningResult()
                dismiss()
            }
        } else if isPairingFailure(failure) {
            openSettings(.pairing)
        } else if isInstallChannelFailure(failure) {
            openSettings(.localDevVPN)
        } else if failure.code == "SEAL-EXT-401" {
            viewModel.retryWithoutExtensions()
        } else {
            viewModel.retrySigning()
        }
    }

    private func shouldOfferRetry(_ failure: ImportFailure) -> Bool {
        if isCertificateFailure(failure) { return false }
        if isAuthFailure(failure) || isAppIDFailure(failure) || isPairingFailure(failure) {
            return false
        }
        return true
    }

    private func userFacingReason(_ failure: ImportFailure) -> String {
        if isAuthFailure(failure) {
            return "Apple ID 登录状态已失效，请重新验证后重试"
        }
        return failure.userReason
    }

    private func recoveryText(_ failure: ImportFailure) -> String {
        let recovery = failure.recovery.trimmingCharacters(in: .whitespacesAndNewlines)
        if recovery.isEmpty || recovery == "知道了" { return "请根据上方原因处理后再试。" }
        return recovery
    }

    private func isAuthFailure(_ failure: ImportFailure) -> Bool {
        failure.code.hasPrefix("SEAL-AUTH-") || failure.code.contains("APPLE_ID")
    }

    private func isCertificateFailure(_ failure: ImportFailure) -> Bool {
        failure.code.hasPrefix("SEAL-CERT-") || failure.code.contains("CERT")
    }

    private func isAppIDFailure(_ failure: ImportFailure) -> Bool {
        failure.code.hasPrefix("SEAL-APPID-")
    }

    private func isPairingFailure(_ failure: ImportFailure) -> Bool {
        failure.code.hasPrefix("SEAL-PAIR-")
    }

    private func isInstallChannelFailure(_ failure: ImportFailure) -> Bool {
        failure.code.hasPrefix("SEAL-INSTALL-")
    }

    private func openSettings(_ route: SettingsRoute) {
        viewModel.dismissSigningResult()
        viewModel.openSettings(route: route)
        dismiss()
    }

    private func finish() {
        viewModel.dismissSigningResult()
        onFinish()
        dismiss()
    }
}

private extension SigningStage {
    func userVisibleTitle(isRenewal: Bool) -> String {
        switch self {
        case .waitingForChannel: return "检查安装通道"
        case .preparingAccount: return "检查 Apple ID"
        case .preparingCertificate: return "检查本机证书"
        case .preparingProfiles: return "生成描述文件"
        case .signing: return isRenewal ? "重新签名应用" : "签名应用"
        case .installing: return "安装到设备"
        case .verifying: return "保存续签记录"
        }
    }
}

private struct TimelineStep: Equatable {
    let title: String
    let position: Int
}

import SwiftUI
import UIKit

struct SigningProgressView: View {
    @ObservedObject var viewModel: AppsViewModel
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            SealSheetGrabber()

            Text(title)
                .font(.system(size: 20, weight: .bold))
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
        .padding(.bottom, 22)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(runningStatusTitle(for: stage))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(progress(for: stage) * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
            }
            ProgressView(value: progress(for: stage))
                .tint(Color.sealAccent)
            Text(stage.userVisibleTitle(isRenewal: isRenewal))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.sealTextSecondary)
        }
        .padding(14)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func successContent(_ installed: AppRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.sealSuccess)
            VStack(alignment: .leading, spacing: 3) {
                Text(isRenewal ? "续签并安装成功" : "签名并安装成功")
                    .font(.system(size: 16, weight: .semibold))
                Text(expiryText(for: installed))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func failureContent(_ failure: ImportFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sealDanger)
                Text(failure.title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            Text(userFacingReason(failure))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.sealTextSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if recoveryText(failure).isEmpty == false {
                Text(recoveryText(failure))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sealAccent)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.sealDanger.opacity(0.18), lineWidth: 0.8)
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
            Button("完成") { finish() }
                .sealPrimaryAction(cornerRadius: 14)

        case .failed(let failure):
            Button(primaryRecoveryTitle(failure)) {
                performPrimaryRecovery(failure)
            }
            .sealPrimaryAction(cornerRadius: 14)

            if shouldOfferRetry(failure) {
                Button("重试") { viewModel.retrySigning() }
                    .sealOutlineAction(cornerRadius: 14)
            }
        case nil:
            EmptyView()
        }
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
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: title.contains("Bundle") || title.contains("证书") ? .monospaced : .default))
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 42)
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
        HStack(spacing: 14) {
            appIcon(app, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("v\(app.version)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                        .lineLimit(1)
                }
                Text(displayBundleIdentifier(app))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayBundleIdentifier(_ app: AppRecord) -> String {
        if app.isSeal { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        if app.state == .installed { return app.mappedBundleIdentifier ?? app.preferredBundleIdentifier ?? app.originalBundleIdentifier }
        return app.preferredBundleIdentifier ?? app.originalBundleIdentifier
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
                    .padding(11)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var session: SigningSession? { viewModel.signingSession }
    private var isRenewal: Bool { session?.app.state == .installed || session?.app.isSeal == true }

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
        case .waitingForChannel, .preparingAccount, .preparingCertificate, .preparingProfiles: 0
        case .signing: 1
        case .installing, .verifying: 2
        }
    }

    private func runningStatusTitle(for stage: SigningStage) -> String {
        if timelinePosition(for: stage) == 2 { return "正在安装" }
        if timelinePosition(for: stage) == 1 { return isRenewal ? "正在续签" : "正在签名" }
        return stage.title
    }

    private func expiryText(for installed: AppRecord) -> String {
        guard let expiryDate = installed.expiryDate else { return "应用已安装" }
        return "到期：\(SealSettingsDateFormatter.string(from: expiryDate))"
    }

    private func primaryRecoveryTitle(_ failure: ImportFailure) -> String {
        if isAuthFailure(failure) { return "重新验证 Apple ID" }
        if isCertificateFailure(failure) { return "重试" }
        if isAppIDFailure(failure) { return "更换 Bundle ID" }
        if isPairingFailure(failure) { return "配对文件" }
        if isInstallChannelFailure(failure) { return "知道了" }
        if failure.code == "SEAL-EXT-401" { return "移除扩展并重试" }
        return "重试"
    }

    private func performPrimaryRecovery(_ failure: ImportFailure) {
        if isAuthFailure(failure) {
            openSettings(.account)
        } else if isCertificateFailure(failure) {
            viewModel.retrySigning()
        } else if isAppIDFailure(failure) {
            viewModel.dismissSigningResult()
            dismiss()
        } else if isPairingFailure(failure) {
            openSettings(.pairing)
        } else if isInstallChannelFailure(failure) {
            viewModel.dismissSigningResult()
            dismiss()
        } else if failure.code == "SEAL-EXT-401" {
            viewModel.retryWithoutExtensions()
        } else {
            viewModel.retrySigning()
        }
    }

    private func shouldOfferRetry(_ failure: ImportFailure) -> Bool {
        if isAuthFailure(failure) || isAppIDFailure(failure) || isPairingFailure(failure) { return false }
        return true
    }

    private func userFacingReason(_ failure: ImportFailure) -> String {
        failure.userReason
    }

    private func recoveryText(_ failure: ImportFailure) -> String {
        let recovery = failure.recovery.trimmingCharacters(in: .whitespacesAndNewlines)
        if recovery.isEmpty || recovery == "知道了" { return "" }
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
        case .waitingForChannel: return isRenewal ? "正在准备续签" : "正在准备签名"
        case .preparingAccount: return isRenewal ? "正在准备续签" : "正在准备签名"
        case .preparingCertificate: return "正在处理 Bundle ID"
        case .preparingProfiles: return "正在生成描述文件"
        case .signing: return "正在写入签名"
        case .installing: return "正在安装到设备"
        case .verifying: return "正在确认安装"
        }
    }
}

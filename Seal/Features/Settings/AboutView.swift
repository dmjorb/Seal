import SwiftUI
import UIKit

struct AboutView: View {
    private let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    private let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.mjorb.seal"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                headerCard
                versionCard
                noteCard
            }
            .padding(20)
        }
        .navigationTitle("当前版本")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground(.secondary)
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "signature")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.sealAccent)
            Text("Seal")
                .font(.title.weight(.semibold))
            Text("个人 IPA 签名与续签工具")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var versionCard: some View {
        VStack(spacing: 0) {
            infoRow("版本", version)
            Divider()
            infoRow("构建号", build)
            Divider()
            infoRow("Bundle ID", bundleID)
            Divider()
            infoRow("系统", "iOS \(UIDevice.current.systemVersion)")
        }
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var noteCard: some View {
        Text("这里仅显示当前安装的 Seal 版本信息。开源组件、协议与上游仓库请在“开源许可”页面查看。")
            .font(.footnote)
            .foregroundStyle(Color.sealTextSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(Color.sealTextSecondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 16, weight: .regular))
        .frame(minHeight: 54)
    }
}

import SwiftUI

struct PrivacyNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                privacyRow("Apple ID 凭据", "仅保存在本机钥匙串")
                privacyRow("IPA 文件", "仅在本机导入、签名和安装")
                privacyRow("配对文件", "仅用于连接当前设备")
                privacyRow("日志", "仅保存在本机，可随时清空")
            }
            .padding(20)
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground()
    }

    private func privacyRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.sealSuccess)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
            }
            Spacer()
        }
        .padding(16)
        .glassSurface(cornerRadius: 14)
    }
}

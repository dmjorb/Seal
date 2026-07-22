import SwiftUI

struct SigningAndRenewalGuideView: View {
    private let signingSteps = [
        "打开 LocalDevVPN，并开启 VPN。",
        "打开 Seal。",
        "添加 Apple ID。",
        "导入配对文件。\n如果显示“待验证”，这是正常状态。",
        "在「我的」页确认签名环境。\n显示“可直接签名”后，就可以继续。",
        "回到「应用」页，点击 + 导入 IPA。",
        "点开 IPA，确认 Apple ID 和 Bundle ID。",
        "点击签名并安装。"
    ]

    private let renewalSteps = [
        "打开 LocalDevVPN，并开启 VPN。",
        "打开 Seal。",
        "点开快到期的 App。",
        "点击续签。"
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                guideSection(title: "签名", steps: signingSteps)
                guideSection(title: "续签", steps: renewalSteps)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .navigationTitle("签名和续签")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground(.secondary)
    }

    private func guideSection(title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.sealAccent)
                            .frame(width: 26, height: 26)
                            .background(Color.sealAccent.opacity(0.14), in: Circle())
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 14)
                    if index < steps.count - 1 {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

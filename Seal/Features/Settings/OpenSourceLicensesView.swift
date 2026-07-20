import SwiftUI

struct OpenSourceLicensesView: View {
    private let dependencies: [OpenSourceDependency] = [
        OpenSourceDependency(
            name: "AltSign",
            purpose: "IPA 签名、证书与描述文件处理",
            license: "AGPL-3.0",
            url: URL(string: "https://github.com/SideStore/AltSign")!
        ),
        OpenSourceDependency(
            name: "Minimuxer",
            purpose: "LocalDevVPN / SideStore 安装通道",
            license: "AGPL-3.0",
            url: URL(string: "https://github.com/SideStore/minimuxer")!
        ),
        OpenSourceDependency(
            name: "ZIPFoundation",
            purpose: "IPA 解包、读取和重新打包",
            license: "MIT",
            url: URL(string: "https://github.com/weichsel/ZIPFoundation")!
        ),
        OpenSourceDependency(
            name: "DeviceSupport",
            purpose: "设备支持文件与连接能力",
            license: "开源许可见上游仓库",
            url: URL(string: "https://github.com/SideStore/DeviceSupport")!
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Seal 使用的开源组件仅用于本机 IPA 解析、签名、安装与设备连接。请以各上游仓库中的 LICENSE 文件为准。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(dependencies.enumerated()), id: \.element.id) { index, dependency in
                        Link(destination: dependency.url) {
                            HStack(alignment: .center, spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(dependency.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(dependency.purpose)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(Color.sealTextSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(dependency.license)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sealAccent)
                                }
                                Spacer(minLength: 12)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.sealTextSecondary)
                            }
                            .padding(.vertical, 15)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < dependencies.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.sealHairline.opacity(0.58), lineWidth: 0.8)
                }
            }
            .padding(20)
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground()
    }
}

private struct OpenSourceDependency: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let purpose: String
    let license: String
    let url: URL
}

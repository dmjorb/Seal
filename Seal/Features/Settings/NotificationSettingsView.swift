import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("到期前 24 小时提醒")
                            .font(.headline)
                        Text("作为自动续签失败或未运行时的兜底提醒")
                            .font(.caption)
                            .foregroundStyle(Color.sealTextSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.notificationsEnabled },
                        set: { viewModel.submitNotificationsEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(.sealAccent)
                    .disabled(viewModel.isNotificationOperationRunning)
                }
                .padding(18)
                .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(20)
        }
        .navigationTitle("提醒设置")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground()
    }
}

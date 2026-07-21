import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL

    private let leadOptions: [Int] = [144, 120, 96, 72, 48, 24]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack {
                    Text("到期提醒")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.notificationsEnabled },
                        set: { enabled in Task { await viewModel.setNotificationsEnabled(enabled) } }
                    ))
                    .labelsHidden()
                    .tint(.sealAccent)
                }
                .padding(18)
                .glassSurface(cornerRadius: 22)

                VStack(alignment: .leading, spacing: 12) {
                    Text("提醒时间")
                        .font(.headline)
                    Picker("提醒时间", selection: Binding(
                        get: { normalizedLeadHours },
                        set: { hours in Task { await viewModel.setReminderHours(hours) } }
                    )) {
                        ForEach(leadOptions, id: \.self) { hours in
                            Text(Self.displayLeadTime(hours)).tag(hours)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 172)
                    .disabled(!viewModel.notificationsEnabled)
                    .opacity(viewModel.notificationsEnabled ? 1 : 0.42)
                }
                .padding(18)
                .glassSurface(cornerRadius: 22)

                if !viewModel.notificationsEnabled,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("打开系统通知设置") { openURL(url) }
                        .sealOutlineAction(cornerRadius: 14)
                }
            }
            .padding(20)
        }
        .navigationTitle("提醒设置")
        .navigationBarTitleDisplayMode(.inline)
        .sealScreenBackground()
    }

    private var normalizedLeadHours: Int {
        if leadOptions.contains(viewModel.reminderHours) { return viewModel.reminderHours }
        return min(144, max(1, viewModel.reminderHours))
    }

    private static func displayLeadTime(_ hours: Int) -> String {
        return "到期 \(hours / 24) 天"
    }
}

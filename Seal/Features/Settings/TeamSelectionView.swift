import SwiftUI

struct TeamSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamID: String?
    @State private var isSaving = false

    var body: some View {
        SealDrawer(title: "选择 Team") {
            VStack(alignment: .leading, spacing: 14) {
                Text("此 Apple ID 有多个 Team。后续 Serial、App ID 和描述文件都会固定使用你选择的同一个 Team。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let pending = viewModel.pendingTeamSelection {
                    ForEach(pending.teams) { team in
                        Button {
                            selectedTeamID = team.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(team.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(team.id)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Text(team.isFreeTeam ? "免费 Team" : "付费 Team")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: selectedTeamID == team.id ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedTeamID == team.id ? Color.sealAccent : .secondary)
                            }
                            .padding(14)
                            .background(Color.sealSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(team.name)，\(team.id)，\(team.isFreeTeam ? "免费 Team" : "付费 Team")")
                        .accessibilityValue(selectedTeamID == team.id ? "已选择" : "未选择")
                    }
                }
            }
            .padding(.bottom, 12)
        } footer: {
            HStack(spacing: 12) {
                Button("取消") {
                    viewModel.cancelTeamSelection()
                    dismiss()
                }
                .sealOutlineAction(cornerRadius: 12)

                Button {
                    guard let selectedTeamID,
                          let team = viewModel.pendingTeamSelection?.teams.first(where: { $0.id == selectedTeamID }) else { return }
                    isSaving = true
                    Task { @MainActor in
                        let saved = await viewModel.completeTeamSelection(team)
                        isSaving = false
                        if saved { dismiss() }
                    }
                } label: {
                    if isSaving { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("保存") }
                }
                .sealPrimaryAction(cornerRadius: 12)
                .disabled(selectedTeamID == nil || isSaving)
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            if selectedTeamID == nil {
                selectedTeamID = viewModel.pendingTeamSelection?.teams.first?.id
            }
        }
        .onDisappear {
            if isSaving == false && viewModel.pendingTeamSelection != nil {
                viewModel.cancelTeamSelection()
            }
        }
    }
}

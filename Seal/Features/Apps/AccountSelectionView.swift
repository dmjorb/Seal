import SwiftUI

struct AccountSelectionView: View {
    let app: AppRecord
    let accounts: [AppleAccountRecord]
    let onSelect: (AppleAccountRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        SealDrawer(title: "选择签名账号", subtitle: app.name) {
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    Button { selection = account.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(account.status == .verified ? Color.sealSuccess : Color.sealWarning)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.maskedEmail)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(accountSubtitle(account))
                                    .font(.caption)
                                    .foregroundStyle(Color.sealTextSecondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: selection == account.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection == account.id ? Color.sealAccent : Color.sealTextSecondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(account.maskedEmail)，\(accountSubtitle(account))")
                    .accessibilityAddTraits(selection == account.id ? .isSelected : [])

                    if index < accounts.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassSurface(cornerRadius: 16)
        } footer: {
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .sealOutlineAction(cornerRadius: 14)

                Button("使用此账号") {
                    guard let account = accounts.first(where: { $0.id == selection }) else { return }
                    onSelect(account)
                    dismiss()
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(selection == nil)
            }
        }
        .onAppear { selection = accounts.first?.id }
    }

    private func accountSubtitle(_ account: AppleAccountRecord) -> String {
        let team = account.teamName.isEmpty ? account.teamID : account.teamName
        let status = account.status == .verified ? "已验证" : "需验证"
        return "\(team) · \(status)"
    }
}

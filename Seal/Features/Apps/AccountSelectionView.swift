import SwiftUI

struct AccountSelectionView: View {
    let app: AppRecord
    let accounts: [AppleAccountRecord]
    let onSelect: (AppleAccountRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        SealDrawer(title: "选择 Apple ID") {
            VStack(alignment: .leading, spacing: 14) {
                Text(app.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        Button { selection = account.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.sealAccent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.maskedEmail).foregroundStyle(.primary)
                                    Text("\(account.teamName) · \(account.teamID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: selection == account.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection == account.id ? Color.sealAccent : .secondary)
                            }
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        if index < accounts.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
                .padding(.horizontal, 16)
                .glassSurface(cornerRadius: 16)
            }
            .padding(.bottom, 12)
        } footer: {
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .sealOutlineAction(cornerRadius: 14)
                Button("使用此账号") {
                    if let account = accounts.first(where: { $0.id == selection }) {
                        onSelect(account)
                        dismiss()
                    }
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(selection == nil)
            }
        }
        .onAppear { selection = accounts.first?.id }
    }
}

import SwiftUI

struct AccountSelectionView: View {
    let app: AppRecord
    let accounts: [AppleAccountRecord]
    let onSelect: (AppleAccountRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.secondary.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 10)
            Text("选择签名账号").font(.title3.weight(.semibold))
            Text(app.name).font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    Button { selection = account.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.maskedEmail).foregroundStyle(.primary)
                                Text(account.teamName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selection == account.id ? "checkmark.circle.fill" : "circle").foregroundStyle(selection == account.id ? Color.sealAccent : .secondary)
                        }.padding(.vertical, 14)
                    }.buttonStyle(.plain)
                    if index < accounts.count - 1 { Divider().padding(.leading, 44) }
                }
            }
            .padding(.horizontal, 16)
            .glassSurface(cornerRadius: 16)
            Button("使用此账号") {
                if let account = accounts.first(where: { $0.id == selection }) { onSelect(account); dismiss() }
            }
            .sealPrimaryAction(cornerRadius: 14)
            .disabled(selection == nil)
            Button("取消") { dismiss() }.sealOutlineAction(cornerRadius: 14)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(520), .large])
        .sealSheetBackground(.tertiary)
        .onAppear { selection = accounts.first?.id }
    }
}

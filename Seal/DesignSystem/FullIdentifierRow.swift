import SwiftUI

struct FullIdentifierRow: View {
    let title: String
    let value: String
    var valueColor: Color = .sealTextSecondary
    var showsCopyButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                Spacer(minLength: 8)
                if showsCopyButton {
                    Button("复制") {
                        SealPasteboard.copy(value, announcement: "\(title)已复制")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.sealAccent)
                }
            }
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .contextMenu {
                    Button("复制") {
                        SealPasteboard.copy(value, announcement: "\(title)已复制")
                    }
                }
        }
        .padding(.vertical, 8)
    }
}

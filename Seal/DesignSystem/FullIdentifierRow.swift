import SwiftUI
import UIKit

struct FullIdentifierRow: View {
    let title: String
    let value: String
    var valueColor: Color = .sealTextSecondary
    var showsCopyButton = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                Spacer(minLength: 8)
                if showsCopyButton {
                    Button {
                        UIPasteboard.general.string = value
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.sealAccent)
                    .accessibilityLabel("复制\(title)")
                }
            }
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

import SwiftUI
import UIKit

struct FullIdentifierRow: View {
    let title: String
    let value: String
    var valueColor: Color = .sealTextSecondary
    var showsCopyButton = false

    @State private var showsCopiedConfirmation = false
    @State private var showsFullValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
                Spacer(minLength: 8)
                if showsCopyButton {
                    Button {
                        copyValue()
                    } label: {
                        Image(systemName: showsCopiedConfirmation ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制\(title)")
                }
            }

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(showsFullValue ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: showsFullValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsFullValue.toggle()
                    }
                }
                .textSelection(.enabled)
                .contextMenu {
                    Button("复制") { copyValue() }
                    Button(showsFullValue ? "收起" : "查看完整") {
                        showsFullValue.toggle()
                    }
                }
                .accessibilityLabel("\(title)，\(value)")
                .accessibilityHint(showsFullValue ? "轻点收起" : "轻点查看完整内容，长按可复制")

            if showsCopiedConfirmation {
                Text("已复制")
                    .font(.caption2)
                    .foregroundStyle(Color.sealSuccess)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
    }

    private func copyValue() {
        UIPasteboard.general.string = value
        withAnimation(.easeOut(duration: 0.16)) {
            showsCopiedConfirmation = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.16)) {
                showsCopiedConfirmation = false
            }
        }
    }
}

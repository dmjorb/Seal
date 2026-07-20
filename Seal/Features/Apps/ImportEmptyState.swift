import SwiftUI

struct ImportEmptyState: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("暂无待签名应用")
                .font(.headline)

            Button(action: onImport) {
                Label("导入 IPA", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("import-empty-button")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

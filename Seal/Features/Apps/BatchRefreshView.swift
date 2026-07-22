import SwiftUI

struct BatchRefreshView: View {
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SealDrawer(title: isRunning ? "批量续签" : "续签结果") {
            statusCard
        } footer: {
            if isRunning {
                Button("续签中…") {}
                    .sealSecondaryDisabledAction(cornerRadius: 14)
                    .disabled(true)
            } else {
                Button("完成") {
                    viewModel.dismissBatchRefresh()
                    dismiss()
                }
                .sealPrimaryAction(cornerRadius: 14)
            }
        }
        .interactiveDismissDisabled(isRunning)
    }

    @ViewBuilder private var statusCard: some View {
        switch viewModel.batchRefreshSession?.status {
        case .running:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在续签")
                    .font(.headline)
                Spacer()
                Text(progressText)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(Color.sealTextSecondary)
            }
            .padding(16)
            .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .completed(let result):
            VStack(spacing: 0) {
                resultRow("checkmark.circle.fill", "成功", "\(result.succeeded)", .sealSuccess)
                Divider().padding(.leading, 14)
                resultRow("xmark.circle.fill", "失败", "\(result.failed)", .sealDanger)
            }
            .padding(.horizontal, 14)
            .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.sealDanger)
                    Text(failure.title)
                        .font(.headline)
                }
                Text(failure.userReason)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case nil:
            EmptyView()
        }
    }

    private func resultRow(_ symbol: String, _ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            Text(label)
            Spacer()
            Text(value).foregroundStyle(color)
        }
        .font(.body.weight(.semibold))
        .frame(minHeight: 46)
    }

    private var progressText: String {
        "\(viewModel.batchRefreshSession?.currentIndex ?? 0) / \(viewModel.batchRefreshSession?.total ?? 0)"
    }

    private var isRunning: Bool {
        if case .running = viewModel.batchRefreshSession?.status { return true }
        return false
    }
}

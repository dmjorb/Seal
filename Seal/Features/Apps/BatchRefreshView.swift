import SwiftUI

struct BatchRefreshView: View {
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SealDrawer(title: isRunning ? "批量续签" : "续签结果") {
            statusCard
                .padding(.bottom, 12)
        } footer: {
            action
        }
        .interactiveDismissDisabled(isRunning)
    }

    @ViewBuilder private var statusCard: some View {
        switch viewModel.batchRefreshSession?.status {
        case .running:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在续签").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(progressText)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.sealDanger)
                    Text(failure.title).font(.system(size: 16, weight: .semibold))
                }
                Text(failure.userReason)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .font(.system(size: 15, weight: .semibold))
        .frame(minHeight: 46)
    }

    @ViewBuilder private var action: some View {
        switch viewModel.batchRefreshSession?.status {
        case .completed, .failed:
            Button("完成") { viewModel.dismissBatchRefresh(); dismiss() }
                .sealPrimaryAction(cornerRadius: 14)
        case .running:
            Button("续签中…") {}
                .sealSecondaryDisabledAction(cornerRadius: 14)
                .disabled(true)
        case nil:
            EmptyView()
        }
    }

    private var progressText: String {
        "\(viewModel.batchRefreshSession?.currentIndex ?? 0) / \(viewModel.batchRefreshSession?.total ?? 0)"
    }

    private var isRunning: Bool {
        if case .running = viewModel.batchRefreshSession?.status { return true }
        return false
    }
}

import SwiftUI

struct BatchRefreshView: View {
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            SealSheetGrabber()
            Text(isRunning ? "批量续签" : "续签结果")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            statusCard
            action
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .interactiveDismissDisabled(isRunning)
        .sealSheetBackground()
    }

    @ViewBuilder private var statusCard: some View {
        switch viewModel.batchRefreshSession?.status {
        case .running:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.batchRefreshSession?.currentAppName ?? "准备续签")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(progressText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sealTextSecondary)
                }
                ProgressView(value: progress)
                    .tint(Color.sealAccent)
                Text(viewModel.batchRefreshSession?.currentStage?.title ?? "读取队列")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
            }
            .padding(14)
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
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(failure.userReason)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(3)
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
        case .running:
            Button("取消") { viewModel.cancelBatchRefresh(); dismiss() }
                .sealOutlineAction(cornerRadius: 14)
        case .completed, .failed:
            Button("完成") { viewModel.dismissBatchRefresh(); dismiss() }
                .sealPrimaryAction(cornerRadius: 14)
        default:
            EmptyView()
        }
    }

    private var progressText: String { "\(viewModel.batchRefreshSession?.currentIndex ?? 0) / \(viewModel.batchRefreshSession?.total ?? 0)" }
    private var progress: Double { Double(viewModel.batchRefreshSession?.currentIndex ?? 0) / Double(max(1, viewModel.batchRefreshSession?.total ?? 1)) }
    private var isRunning: Bool { if case .running = viewModel.batchRefreshSession?.status { return true }; return false }
}

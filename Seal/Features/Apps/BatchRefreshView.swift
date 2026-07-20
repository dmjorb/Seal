import SwiftUI

struct BatchRefreshView: View {
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                graphic
                details
                Spacer()
                action
            }
            .padding(24)
            .navigationTitle(isRunning ? "批量续签中" : "续签结果")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isRunning)
            .toolbar {
                if isRunning { ToolbarItem(placement: .cancellationAction) { Button("取消") { viewModel.cancelBatchRefresh(); dismiss() } } }
            }
        }
        .sealSheetBackground(.tertiary)
    }

    @ViewBuilder private var graphic: some View {
        switch viewModel.batchRefreshSession?.status {
        case .running:
            ZStack {
                Circle().stroke(Color.sealAccent.opacity(0.16), lineWidth: 9)
                Circle().trim(from: 0, to: progress).stroke(Color.sealAccent, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(progressText).font(.title3.monospacedDigit().weight(.semibold))
            }.frame(width: 112, height: 112)
        case .completed(let result): Image(systemName: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.system(size: 68)).foregroundStyle(result.failed == 0 ? .green : .orange)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 60)).foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }

    @ViewBuilder private var details: some View {
        switch viewModel.batchRefreshSession?.status {
        case .running:
            VStack(spacing: 12) {
                Text(viewModel.batchRefreshSession?.currentAppName ?? "准备续签").font(.title3.weight(.semibold))
                Text(viewModel.batchRefreshSession?.currentStage?.title ?? "读取队列").font(.subheadline).foregroundStyle(.secondary)
            }
        case .completed(let result):
            VStack(spacing: 0) {
                resultRow("checkmark.circle.fill", "成功", "\(result.succeeded)", .green)
                Divider()
                resultRow("xmark.circle.fill", "失败", "\(result.failed)", .red)
            }.padding(.horizontal, 16).glassSurface(cornerRadius: 16)
        case .failed(let failure):
            VStack(spacing: 6) { Text(failure.reason).font(.title3.weight(.semibold)); Text(failure.code).font(.caption.monospaced()).foregroundStyle(.secondary) }
        case nil: EmptyView()
        }
    }

    private func resultRow(_ symbol: String, _ label: String, _ value: String, _ color: Color) -> some View {
        HStack { Image(systemName: symbol).foregroundStyle(color); Text(label); Spacer(); Text(value).foregroundStyle(color) }.padding(.vertical, 14)
    }

    @ViewBuilder private var action: some View {
        switch viewModel.batchRefreshSession?.status {
        case .completed, .failed:
            Button("完成") { viewModel.dismissBatchRefresh(); dismiss() }.sealPrimaryAction(cornerRadius: 14)
        default:
            EmptyView()
        }
    }

    private var progressText: String { "\(viewModel.batchRefreshSession?.currentIndex ?? 0) / \(viewModel.batchRefreshSession?.total ?? 0)" }
    private var progress: Double { Double(viewModel.batchRefreshSession?.currentIndex ?? 0) / Double(max(1, viewModel.batchRefreshSession?.total ?? 1)) }
    private var isRunning: Bool { if case .running = viewModel.batchRefreshSession?.status { return true }; return false }
}

import SwiftUI

struct LogsCenterView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var confirmsClear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                if viewModel.logs.isEmpty {
                    emptyCard
                } else {
                    logsCard
                }
                actionCard
            }
            .padding(20)
        }
        .navigationTitle("日志中心")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "清理全部日志？",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("清理日志", role: .destructive) {
                Task { await viewModel.clearLogs() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清理后无法从 Seal 内恢复。")
        }
        .task { await viewModel.load(force: true) }
        .sealScreenBackground()
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.sealAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text("运行日志")
                    .font(.title3.weight(.semibold))
                Text("共 \(viewModel.logs.count) 条记录")
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
            }
            Spacer()
        }
        .padding(18)
        .glassSurface(cornerRadius: 22)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Color.sealSuccess)
            Text("暂无日志")
                .font(.headline)
            Text("签名、续签、账号和设备连接记录会显示在这里。")
                .font(.subheadline)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassSurface(cornerRadius: 22)
    }

    private var logsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.logs.enumerated()), id: \.element.id) { index, log in
                logRow(log)
                if index < viewModel.logs.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 18)
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            if viewModel.logExportText.isEmpty == false {
                ShareLink(item: viewModel.logExportText) {
                    Text("导出日志")
                        .frame(maxWidth: .infinity)
                }
                .sealPrimaryAction(cornerRadius: 12)
            }
            Button("清理日志") { confirmsClear = true }
                .sealOutlineAction(cornerRadius: 12)
                .disabled(viewModel.logs.isEmpty)
        }
    }

    private func logRow(_ log: SealLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color(for: log.level))
                .frame(width: 10, height: 10)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(log.category.displayTitle)
                        .font(.body.weight(.semibold))
                    Text(log.level.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: log.level))
                }
                Text(log.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.sealTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SealSettingsDateFormatter.string(from: log.timestamp))
                    .font(.caption)
                    .foregroundStyle(Color.sealTextSecondary.opacity(0.78))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    private func color(for level: SealLogEntry.Level) -> Color {
        switch level {
        case .info: return .sealSuccess
        case .warning: return .sealWarning
        case .error: return .sealDanger
        }
    }
}

private extension SealLogEntry.Category {
    var displayTitle: String {
        switch self {
        case .account: return "账号"
        case .pairing: return "配对"
        case .signing: return "签名"
        case .installation: return "安装"
        case .renewal: return "续签"
        case .system: return "系统"
        }
    }
}

private extension SealLogEntry.Level {
    var displayTitle: String {
        switch self {
        case .info: return "正常"
        case .warning: return "警告"
        case .error: return "失败"
        }
    }
}

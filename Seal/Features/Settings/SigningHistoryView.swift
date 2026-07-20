import SwiftUI
import UIKit

struct SigningHistoryView: View {
    let account: AppleAccountRecord
    @ObservedObject var viewModel: SettingsViewModel
    @State private var filter: SigningHistoryFilter = .all
    @State private var confirmsClear = false

    private var records: [SigningHistoryRecord] {
        viewModel.signingHistory(for: account.id)
    }

    private var filteredRecords: [SigningHistoryRecord] {
        switch filter {
        case .all:
            records
        case .success:
            records.filter { $0.result == .success }
        case .failed:
            records.filter { $0.result == .failed }
        }
    }

    private var summary: SigningHistorySummary {
        SigningHistorySummary(records: records)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                filterPicker

                if filteredRecords.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredRecords) { record in
                            SigningHistoryRow(
                                record: record,
                                iconData: viewModel.signingHistoryIconData[record.id]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .navigationTitle("签名历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if records.isEmpty == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清除") { confirmsClear = true }
                }
            }
        }
        .task { await viewModel.load(force: true) }
        .confirmationDialog(
            "清除这个 Apple ID 的签名历史？",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("清除历史", role: .destructive) {
                Task { await viewModel.clearSigningHistory(for: account.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除 Seal 本地历史记录，不会删除已安装应用或 Apple ID。")
        }
        .sealScreenBackground(.tertiary)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.sealAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.sealAccent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.maskedEmail)
                        .font(.headline)
                    Text(account.teamName)
                        .font(.subheadline)
                        .foregroundStyle(Color.sealTextSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                metric("总记录", "\(summary.total)")
                metric("有效", "\(summary.valid)")
                metric("失败", "\(summary.failed)")
                metric("已删除", "\(summary.deleted)")
            }

            if let latestSignedAt = summary.latestSignedAt {
                Text("最近一次：\(SigningHistoryDateFormatter.string(from: latestSignedAt))")
                    .font(.footnote)
                    .foregroundStyle(Color.sealTextSecondary)
            }
        }
        .padding(18)
        .glassSurface(cornerRadius: 26)
    }

    private var filterPicker: some View {
        Picker("筛选", selection: $filter) {
            ForEach(SigningHistoryFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.sealTextSecondary)
            Text("暂无签名历史")
                .font(.headline)
            Text("这个 Apple ID 完成签名、续签或失败后，记录会自动出现在这里。")
                .font(.footnote)
                .foregroundStyle(Color.sealTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
        .glassSurface(cornerRadius: 26)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.sealTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SigningHistoryRow: View {
    let record: SigningHistoryRecord
    let iconData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(record.appName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(record.result.displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(resultColor)
                    }

                    Text(record.versionDisplay)
                        .font(.subheadline)
                        .foregroundStyle(Color.sealTextSecondary)

                    Text(record.displayBundleIdentifier)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.sealTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Divider()

            VStack(spacing: 8) {
                row("操作", record.action.displayTitle, Color.primary)
                row("时间", SigningHistoryDateFormatter.string(from: record.signedAt), Color.primary)
                row("状态", record.statusText(), statusColor)
                FullIdentifierRow(title: "尝试 Bundle ID", value: record.attemptedDisplayBundleIdentifier)
                if let final = record.finalSignedBundleIdentifier, final.isEmpty == false {
                    FullIdentifierRow(title: "最终 Bundle ID", value: final)
                }
                FullIdentifierRow(title: "Team ID", value: record.teamID)
                if let serial = record.certificateSerialNumber, serial.isEmpty == false {
                    FullIdentifierRow(title: "证书 Serial", value: serial)
                }
                if let udid = record.signedDeviceIdentifier, udid.isEmpty == false {
                    FullIdentifierRow(title: "设备 UDID", value: udid)
                }
                if let profileUUID = record.provisioningProfileUUID, profileUUID.isEmpty == false {
                    FullIdentifierRow(title: "Profile UUID", value: profileUUID)
                }
                if let profileName = record.provisioningProfileName, profileName.isEmpty == false {
                    FullIdentifierRow(title: "Profile 名称", value: profileName)
                }
                if let targets = record.signingTargets, targets.isEmpty == false {
                    ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                        FullIdentifierRow(
                            title: "目标 \(index + 1) Bundle ID",
                            value: target.bundleIdentifier
                        )
                        if let profileUUID = target.profileUUID, profileUUID.isEmpty == false {
                            FullIdentifierRow(
                                title: "目标 \(index + 1) Profile UUID",
                                value: profileUUID
                            )
                        }
                        if target.certificateSerialNumbers.isEmpty == false {
                            FullIdentifierRow(
                                title: "目标 \(index + 1) 证书 Serial",
                                value: target.certificateSerialNumbers.joined(separator: "\n")
                            )
                        }
                        if target.deviceIdentifiers.isEmpty == false {
                            FullIdentifierRow(
                                title: "目标 \(index + 1) 设备 UDID",
                                value: target.deviceIdentifiers.joined(separator: "\n")
                            )
                        }
                    }
                }
                if let errorReason = record.errorReason, record.result == .failed {
                    row("原因", errorReason, Color.sealDanger)
                }
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 24)
    }

    private var icon: some View {
        Group {
            if let iconData, let uiImage = UIImage(data: iconData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealAccent.opacity(0.10))
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.8), lineWidth: 1)
        }
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.sealTextSecondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
    }

    private var resultColor: Color {
        record.result == .success ? .sealSuccess : .sealDanger
    }

    private var statusColor: Color {
        if record.result == .failed { return .sealDanger }
        if record.lifecycleStatus == .deleted { return .sealTextSecondary }
        if let expiryDate = record.expiryDate, expiryDate <= Date() { return .sealWarning }
        return .sealSuccess
    }
}

private enum SigningHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .success: "成功"
        case .failed: "失败"
        }
    }
}

enum SigningHistoryDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

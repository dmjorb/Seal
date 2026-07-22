import SwiftUI
import UIKit

struct ImportConfirmationView: View {
    let draft: ImportDraft
    let isCommitting: Bool
    let failure: ImportFailure?
    let onCancel: () -> Void
    let onPrimaryAction: () -> Void

    @State private var didTapPrimaryAction = false

    private var showsProgress: Bool {
        isCommitting || didTapPrimaryAction
    }

    var body: some View {
        SealDrawer(title: failure == nil ? "导入 IPA" : "导入失败") {
            VStack(spacing: 16) {
                header
                if let failure {
                    failureCard(failure)
                } else {
                    summaryCard
                }
            }
        } footer: {
            VStack(spacing: 12) {
                Button {
                    guard showsProgress == false else { return }
                    didTapPrimaryAction = true
                    onPrimaryAction()
                } label: {
                    if showsProgress {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在导入")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(failure?.recovery ?? "导入")
                    }
                }
                .sealPrimaryAction(cornerRadius: 14)
                .disabled(showsProgress)

                Button("取消", action: onCancel)
                    .sealOutlineAction(cornerRadius: 14)
                    .disabled(isCommitting)
            }
        }
        .interactiveDismissDisabled(showsProgress)
        .accessibilityIdentifier("import-confirmation")
        .onChange(of: isCommitting) { newValue in
            if newValue == false { didTapPrimaryAction = false }
        }
        .onChange(of: failure?.code) { _ in
            didTapPrimaryAction = false
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            appIcon
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.parsedIPA.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("v\(draft.parsedIPA.version) · \(formattedSize)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.sealTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow("Bundle ID", draft.parsedIPA.bundleIdentifier, monospaced: true)
            Divider().padding(.leading, 16)
            summaryRow("扩展", extensionSummary)
            Divider().padding(.leading, 16)
            summaryRow("状态", migrationSummary)
        }
        .padding(.horizontal, 16)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func summaryRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(Color.sealTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 54)
    }

    private func failureCard(_ failure: ImportFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(failure.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.sealWarning)
            Text(failure.userMessage)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.8)
        }
    }

    @ViewBuilder private var appIcon: some View {
        Group {
            if let data = draft.parsedIPA.iconData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(Color.sealAccent)
                    .background(Color.sealSurface)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: draft.parsedIPA.fileSize, countStyle: .file)
    }

    private var extensionSummary: String {
        draft.parsedIPA.extensions.isEmpty ? "无" : "\(draft.parsedIPA.extensions.count) 个"
    }

    private var migrationSummary: String {
        "可导入"
    }
}

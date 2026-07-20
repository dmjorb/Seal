import SwiftUI
import UniformTypeIdentifiers

struct AppsRootView: View {
    private enum ListMode: String, Identifiable {
        case unsigned = "待签名"
        case installed = "已安装"

        var id: Self { self }
    }

    @ObservedObject var viewModel: AppsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var sealTitleSize = 38
    @State private var mode: ListMode = .unsigned
    @State private var detailApp: AppRecord?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    modeTabs
                    appSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $viewModel.isImporterPresented,
                allowedContentTypes: [.item, .data, .archive, .ipaArchive, .zipArchive]
            ) { result in
                switch result {
                case .success(let url): Task { await viewModel.importSelectedFile(url) }
                case .failure(let error): viewModel.handleImporterFailure(error)
                }
            }
            .sheet(isPresented: $viewModel.isImportSheetPresented, onDismiss: cancelDraftIfNeeded) {
                if let draft = viewModel.sheetDraft {
                    ImportConfirmationView(
                        draft: draft,
                        isCommitting: viewModel.phase == .committing,
                        failure: viewModel.sheetFailure,
                        onCancel: { Task { await viewModel.cancelImport() } },
                        onPrimaryAction: {
                            Task {
                                if viewModel.sheetFailure == nil { await viewModel.confirmImport() }
                                else { await viewModel.retryImport() }
                            }
                        }
                    )
                }
            }
            .sheet(item: $viewModel.selectedOperationApp, onDismiss: viewModel.dismissOperation) { app in
                AppSigningSheet(
                    app: app,
                    viewModel: viewModel,
                    onFinish: { mode = .installed }
                )
                    .presentationDetents([.height(560)])
                    .compatiblePresentationCornerRadius(28)
            }
            .sheet(item: $viewModel.accountSelectionApp) { app in
                AccountSelectionView(
                    app: app,
                    accounts: viewModel.verifiedAccounts,
                    onSelect: { viewModel.selectAccount($0, for: app) }
                )
            }
            .sheet(item: $viewModel.batchRefreshSession) { _ in
                BatchRefreshView(viewModel: viewModel)
                    .presentationDetents([.height(560)])
                    .compatiblePresentationCornerRadius(28)
            }
            .sheet(item: $detailApp) { app in
                NavigationStack {
                    AppDetailView(appID: app.id, viewModel: viewModel)
                }
                .presentationDetents([.large])
                .compatiblePresentationCornerRadius(28)
            }
            .alert(item: rootAlertFailure) { failure in
                vpnAwareAlert(failure)
            }
            .task {
                await settingsViewModel.load()
                await viewModel.load()
                if settingsViewModel.environment.isConfigured {
                    _ = await viewModel.refreshSigningChannel()
                }
            }
        }
        .sealScreenBackground()
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Seal")
                .font(.system(size: sealTitleSize, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                viewModel.presentImporter()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color.sealAccent)
                    .frame(width: 56, height: 56)
                    .background(
                        Color.white.opacity(0.52),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    }
            }
            .accessibilityLabel("导入应用")
            .accessibilityIdentifier("import-toolbar-button")
            .disabled(viewModel.phase != .idle)
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 44) {
            modeButton(.unsigned, count: viewModel.unsignedApps.count)
            modeButton(.installed, count: viewModel.installedApps.count)
            Spacer(minLength: 0)
        }
    }

    private func modeButton(_ item: ListMode, count: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { mode = item }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(item.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(count)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(mode == item ? Color.sealAccent : Color.sealTextSecondary)
                        .frame(minWidth: 32, minHeight: 32)
                        .background(
                            mode == item ? Color.sealAccent.opacity(0.10) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                Capsule()
                    .fill(mode == item ? Color.sealAccent : .clear)
                    .frame(width: 78, height: 4)
            }
            .foregroundStyle(mode == item ? Color.sealAccent : Color.sealTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.rawValue)，\(count) 个")
        .accessibilityAddTraits(mode == item ? .isSelected : [])
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(mode == .unsigned ? "待签名应用" : "已安装应用")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                if mode == .installed, viewModel.installedApps.isEmpty == false {
                    batchRefreshMenu
                }
            }
            appList
        }
    }

    private var batchRefreshMenu: some View {
        Menu {
            Button("续签临期应用") {
                viewModel.refreshDueApps(
                    leadHours: settingsViewModel.reminderHours,
                    enforceCooldown: false
                )
            }
            Button("续签全部已安装应用") {
                viewModel.refreshAll()
            }
            if viewModel.pendingRefreshCount > 0 {
                Button("继续上次续签") {
                    viewModel.resumeRefresh()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("批量续签")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.sealAccent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.sealAccent.opacity(0.10), in: Capsule())
        }
        .accessibilityLabel("批量续签")
    }

    @ViewBuilder
    private var appList: some View {
        let apps = mode == .installed ? viewModel.installedApps : viewModel.unsignedApps
        if viewModel.phase == .preparing {
            HStack(spacing: 12) {
                ProgressView()
                Text("正在读取 IPA")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .sealListCard(cornerRadius: 18)
        } else if apps.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    Button {
                        viewModel.presentOperation(for: app)
                    } label: {
                        ImportedAppRow(app: app, iconData: viewModel.iconData[app.id])
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("查看详情") { detailApp = app }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !app.isSeal {
                            Button(role: .destructive) {
                                Task { _ = await viewModel.delete(app) }
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            detailApp = app
                        } label: {
                            Label("详情", systemImage: "info.circle")
                        }
                        .tint(.sealAccent)
                    }

                    if index < apps.count - 1 {
                        Divider()
                            .padding(.leading, 88)
                            .padding(.trailing, 18)
                    }
                }
            }
            .sealListCard(cornerRadius: 20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: mode == .installed ? "app.badge.checkmark" : "square.and.arrow.down")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.sealAccent)
            Text(mode == .installed ? "暂无已安装应用" : "暂无待签名应用")
                .font(.headline)
            if mode == .unsigned {
                Text("点击右上角 + 导入 IPA")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .sealListCard(cornerRadius: 20)
    }

    private func vpnAwareAlert(_ failure: ImportFailure) -> Alert {
        if (failure.code == "SEAL-INSTALL-701" || failure.code == "SEAL-INSTALL-706"), viewModel.hasPendingVPNRecovery {
            return Alert(
                title: Text(failure.title),
                message: Text(failure.reason),
                primaryButton: .default(Text("打开 LocalDevVPN")) { openLocalDevVPN() },
                secondaryButton: .cancel(Text("取消")) { viewModel.cancelPendingVPNRecovery() }
            )
        }
        return Alert(
            title: Text(failure.title),
            message: Text("\(failure.reason)\n\(failure.code)"),
            dismissButton: .default(Text(failure.recovery)) {
                viewModel.performAlertRecovery(for: failure)
            }
        )
    }

    private var rootAlertFailure: Binding<ImportFailure?> {
        Binding(
            get: {
                viewModel.selectedOperationApp == nil ? viewModel.alertFailure : nil
            },
            set: { viewModel.alertFailure = $0 }
        )
    }

    private func cancelDraftIfNeeded() {
        if viewModel.phase != .committing, viewModel.sheetDraft != nil {
            Task { await viewModel.cancelImport() }
        }
    }

    private func openLocalDevVPN() {
        openURL(LocalDevVPNLink.enableAndReturn) { accepted in
            guard accepted == false else { return }
            openURL(LocalDevVPNLink.appStore)
        }
    }
}

private extension UTType {
    static let ipaArchive = UTType(filenameExtension: "ipa") ?? .data
    static let zipArchive = UTType(filenameExtension: "zip") ?? .archive
}

private struct SealListCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.sealHairline.opacity(0.55), lineWidth: 0.8)
            }
    }
}

private extension View {
    func sealListCard(cornerRadius: CGFloat) -> some View {
        modifier(SealListCardModifier(cornerRadius: cornerRadius))
    }
}

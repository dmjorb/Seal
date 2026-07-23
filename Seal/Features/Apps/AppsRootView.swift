import SwiftUI
import UniformTypeIdentifiers

struct AppsRootView: View {
    private enum ListMode: String, Identifiable, CaseIterable {
        case unsigned = "待签名"
        case signed = "已签名"
        case installed = "已安装"

        var id: Self { self }
    }

    @ObservedObject var viewModel: AppsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ScaledMetric(relativeTo: .largeTitle) private var sealTitleSize = 38
    @Namespace private var tabIndicatorNamespace
    @State private var mode: ListMode = .installed
    @State private var detailApp: AppRecord?
    @State private var pendingDeleteApp: AppRecord?
    @State private var signedActionApp: AppRecord?
    @State private var installedActionApp: AppRecord?
    @State private var operationAppID: UUID?
    @State private var didResolveInitialMode = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                modeTabs
                appPager
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
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
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(item: $viewModel.selectedOperationApp, onDismiss: operationSheetDismissed) { app in
                AppSigningSheet(
                    app: app,
                    viewModel: viewModel,
                    onFinish: { completionMode in
                        withAnimation(.easeOut(duration: 0.2)) {
                            mode = completionMode == .signOnly ? .signed : .installed
                        }
                    },
                    onDelete: {
                        pendingDeleteApp = app
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $signedActionApp) { app in
                SignedAppActionSheet(
                    app: app,
                    viewModel: viewModel,
                    onInstalled: { withAnimation { mode = .installed } },
                    onDeleted: { withAnimation { mode = viewModel.unsignedApps.isEmpty ? .signed : .unsigned } }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $installedActionApp) { app in
                InstalledAppActionSheet(
                    app: app,
                    viewModel: viewModel,
                    onRenew: {
                        operationAppID = app.id
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            viewModel.presentOperation(for: app)
                        }
                    },
                    onShowDetail: {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            detailApp = app
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $viewModel.accountSelectionApp) { app in
                AccountSelectionView(
                    app: app,
                    accounts: viewModel.availableAccounts,
                    onSelect: { viewModel.selectAccount($0, for: app) }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $viewModel.batchRefreshSession) { _ in
                BatchRefreshView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $detailApp) { app in
                AppDetailView(appID: app.id, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .alert(deleteAlertTitle, isPresented: Binding(
                get: { pendingDeleteApp != nil },
                set: { if !$0 { pendingDeleteApp = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDeleteApp = nil }
                Button("删除", role: .destructive) {
                    guard let app = pendingDeleteApp else { return }
                    pendingDeleteApp = nil
                    Task { _ = await viewModel.delete(app) }
                }
            } message: {
                Text(deleteAlertMessage)
            }
            .alert(item: rootAlertFailure) { failure in
                standardAlert(failure)
            }
            .task {
                await settingsViewModel.load()
                await viewModel.load()
                resolveInitialModeIfNeeded()
                if settingsViewModel.environment.isConfigured {
                    _ = await viewModel.refreshSigningChannel()
                }
            }
            .onChange(of: viewModel.importCompletionCount) { _ in
                withAnimation(.easeOut(duration: 0.18)) { mode = .unsigned }
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
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.sealAccent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("导入应用")
            .accessibilityIdentifier("import-toolbar-button")
            .disabled(viewModel.phase != .idle)
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 28) {
            modeButton(.unsigned, count: viewModel.unsignedApps.count)
            modeButton(.signed, count: viewModel.signedApps.count)
            modeButton(.installed, count: viewModel.installedApps.count)
            Spacer(minLength: 0)
        }
    }

    private func modeButton(_ item: ListMode, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { mode = item }
        } label: {
            VStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Text(item.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sealTextSecondary)
                }
                ZStack {
                    Capsule().fill(Color.clear).frame(height: 3)
                    if mode == item {
                        Capsule()
                            .fill(Color.sealAccent)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "apps-tab-indicator", in: tabIndicatorNamespace)
                    }
                }
            }
            .foregroundStyle(mode == item ? Color.sealAccent : Color.sealTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.rawValue)，\(count) 个")
        .accessibilityAddTraits(mode == item ? .isSelected : [])
    }

    private var appPager: some View {
        TabView(selection: $mode) {
            appPage(.unsigned, apps: viewModel.unsignedApps).tag(ListMode.unsigned)
            appPage(.signed, apps: viewModel.signedApps).tag(ListMode.signed)
            appPage(.installed, apps: viewModel.installedApps).tag(ListMode.installed)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityIdentifier("apps-stage-pager")
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private func appPage(_ pageMode: ListMode, apps: [AppRecord]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                pageHeader(pageMode)
                    .frame(height: 38)
                appList(pageMode, apps: apps)
            }
            .padding(.bottom, 30)
        }
    }

    private func pageHeader(_ pageMode: ListMode) -> some View {
        HStack(alignment: .center) {
            Text(sectionTitle(for: pageMode))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if pageMode == .installed, viewModel.installedApps.isEmpty == false {
                batchRefreshMenu
            } else {
                Color.clear.frame(width: 1, height: 30)
            }
        }
    }

    @ViewBuilder
    private func appList(_ pageMode: ListMode, apps: [AppRecord]) -> some View {
        if pageMode == .unsigned, viewModel.phase == .preparing {
            HStack(spacing: 12) {
                ProgressView()
                Text("正在读取 IPA")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .sealListCard(cornerRadius: 18)
        } else if apps.isEmpty {
            emptyState(pageMode)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    Button {
                        openApp(app, in: pageMode)
                    } label: {
                        ImportedAppRow(app: app, iconData: viewModel.iconData[app.id])
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("查看详情") { detailApp = app }
                        if pageMode == .unsigned {
                            Button("删除应用", role: .destructive) { pendingDeleteApp = app }
                        } else if pageMode == .signed {
                            Button("已签名 IPA 操作") { signedActionApp = app }
                        } else if app.isSeal == false, isExpired(app) {
                            Button("删除记录", role: .destructive) { pendingDeleteApp = app }
                        }
                    }

                    if index < apps.count - 1 {
                        Divider()
                            .padding(.leading, 84)
                            .padding(.trailing, 18)
                    }
                }
            }
            .sealListCard(cornerRadius: 20)
        }
    }

    private func emptyState(_ pageMode: ListMode) -> some View {
        VStack(spacing: 12) {
            Image(systemName: emptyIcon(for: pageMode))
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.sealAccent)
            Text(emptyTitle(for: pageMode))
                .font(.headline)
            if pageMode == .unsigned {
                Text("点击右上角 + 导入 IPA")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .sealListCard(cornerRadius: 20)
    }

    private func openApp(_ app: AppRecord, in pageMode: ListMode) {
        switch pageMode {
        case .unsigned:
            operationAppID = app.id
            viewModel.presentOperation(for: app)
        case .signed:
            signedActionApp = app
        case .installed:
            installedActionApp = app
        }
    }

    private func operationSheetDismissed() {
        viewModel.dismissOperation()
        guard let operationAppID else { return }
        self.operationAppID = nil
        Task { @MainActor in
            await viewModel.load(force: true)
            if viewModel.installedApps.contains(where: { $0.id == operationAppID }) {
                withAnimation { mode = .installed }
            } else if viewModel.signedApps.contains(where: { $0.id == operationAppID }) {
                withAnimation { mode = .signed }
            }
        }
    }

    private func resolveInitialModeIfNeeded() {
        guard didResolveInitialMode == false else { return }
        didResolveInitialMode = true
        if viewModel.unsignedApps.isEmpty && viewModel.signedApps.isEmpty && viewModel.installedApps.isEmpty {
            mode = .unsigned
        } else {
            mode = .installed
        }
    }

    private func sectionTitle(for pageMode: ListMode) -> String {
        switch pageMode {
        case .unsigned: "待签名应用"
        case .signed: "已签名应用"
        case .installed: "已安装应用"
        }
    }

    private func emptyTitle(for pageMode: ListMode) -> String {
        switch pageMode {
        case .unsigned: "暂无待签名应用"
        case .signed: "暂无已签名应用"
        case .installed: "暂无已安装应用"
        }
    }

    private func emptyIcon(for pageMode: ListMode) -> String {
        switch pageMode {
        case .unsigned: "square.and.arrow.down"
        case .signed: "checkmark.seal"
        case .installed: "app.badge.checkmark"
        }
    }

    private var deleteAlertTitle: String {
        pendingDeleteApp?.state == .installed ? "删除记录？" : "删除应用？"
    }

    private var deleteAlertMessage: String {
        guard pendingDeleteApp?.state == .installed else {
            return "删除后将从 Seal 的待签名列表中移除，并删除 Seal 保存的原始 IPA，不会影响手机上已安装的应用。"
        }
        return "删除后将从 Seal 的已安装列表中移除，不会卸载手机上的应用。"
    }

    private var batchRefreshMenu: some View {
        Menu {
            Button("续签临期应用") {
                viewModel.refreshDueApps(leadHours: settingsViewModel.reminderHours, enforceCooldown: false)
            }
            Button("续签全部已安装应用") { viewModel.refreshAll() }
            if viewModel.pendingRefreshCount > 0 {
                Button("继续上次续签") { viewModel.resumeRefresh() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("批量续签")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.sealAccent)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.sealAccent.opacity(0.10), in: Capsule())
        }
        .accessibilityLabel("批量续签")
    }

    private func isExpired(_ app: AppRecord, now: Date = Date()) -> Bool {
        guard let expiryDate = app.expiryDate else { return false }
        return expiryDate <= now
    }

    private func standardAlert(_ failure: ImportFailure) -> Alert {
        Alert(
            title: Text(failure.title),
            message: Text(failure.userMessage),
            dismissButton: .default(Text(failure.recovery)) {
                viewModel.performAlertRecovery(for: failure)
            }
        )
    }

    private var rootAlertFailure: Binding<ImportFailure?> {
        Binding(
            get: {
                viewModel.selectedOperationApp == nil && signedActionApp == nil && installedActionApp == nil
                    ? viewModel.alertFailure
                    : nil
            },
            set: { viewModel.alertFailure = $0 }
        )
    }

    private func cancelDraftIfNeeded() {
        if viewModel.phase != .committing, viewModel.sheetDraft != nil {
            Task { await viewModel.cancelImport() }
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
                    .fill(Color.sealSurface)
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

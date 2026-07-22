import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AppsRootView: View {
    @ObservedObject var viewModel: AppsViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    @ScaledMetric(relativeTo: .largeTitle) private var sealTitleSize = 38
    @State private var mode: AppListPresentationMode = .installed
    @State private var didResolveInitialMode = false
    @State private var detailApp: AppRecord?
    @State private var signedActionApp: AppRecord?
    @State private var pendingDeleteApp: AppRecord?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                modeTabs
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                TabView(selection: $mode) {
                    appPage(.unsigned).tag(AppListPresentationMode.unsigned)
                    appPage(.signed).tag(AppListPresentationMode.signed)
                    appPage(.installed).tag(AppListPresentationMode.installed)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: mode)
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
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(item: $viewModel.selectedOperationApp, onDismiss: viewModel.dismissOperation) { app in
                AppSigningSheet(
                    app: app,
                    viewModel: viewModel,
                    onFinish: moveToSigningResult
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $signedActionApp) { app in
                SignedIPAActionSheet(
                    app: app,
                    viewModel: viewModel,
                    onInstalled: { move(to: .installed) },
                    onDeleted: { move(to: .unsigned) },
                    onResign: { presentSigningAfterSignedDrawer(for: app) }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $viewModel.accountSelectionApp) { app in
                AccountSelectionView(
                    app: app,
                    accounts: viewModel.selectableAccounts,
                    onSelect: { viewModel.selectAccount($0, for: app) }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $viewModel.batchRefreshSession) { _ in
                BatchRefreshView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $detailApp) { app in
                NavigationStack {
                    AppDetailView(appID: app.id, viewModel: viewModel)
                }
                .sealSheetBackground()
                .presentationDetents([.large])
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
                move(to: .unsigned)
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
        GeometryReader { proxy in
            let itemWidth = proxy.size.width / CGFloat(AppListPresentationMode.allCases.count)
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    ForEach(AppListPresentationMode.allCases) { item in
                        Button {
                            move(to: item)
                        } label: {
                            HStack(spacing: 7) {
                                Text(item.rawValue)
                                let count = appCount(for: item)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(mode == item ? Color.sealAccent : Color.sealTextSecondary)
                                }
                            }
                            .font(.headline.weight(mode == item ? .semibold : .regular))
                            .foregroundStyle(mode == item ? Color.primary : Color.sealTextSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.rawValue)，\(appCount(for: item)) 个")
                        .accessibilityAddTraits(mode == item ? .isSelected : [])
                    }
                }

                Capsule()
                    .fill(Color.sealAccent)
                    .frame(width: itemWidth * 0.42, height: 3)
                    .offset(
                        x: itemWidth * CGFloat(modeIndex) + itemWidth * 0.29,
                        y: 0
                    )
                    .animation(.easeInOut(duration: 0.25), value: mode)
            }
        }
        .frame(height: 52)
        .accessibilityElement(children: .contain)
    }

    private func appPage(_ pageMode: AppListPresentationMode) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(pageMode)
                appList(pageMode)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionHeader(_ pageMode: AppListPresentationMode) -> some View {
        HStack(alignment: .center) {
            Text(pageMode.sectionTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            if pageMode == .installed, viewModel.installedApps.isEmpty == false {
                batchRefreshMenu
            }
        }
        .frame(height: 32)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.sealAccent)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.sealAccent.opacity(0.10), in: Capsule())
        }
        .accessibilityLabel("批量续签")
    }

    @ViewBuilder
    private func appList(_ pageMode: AppListPresentationMode) -> some View {
        let apps = apps(for: pageMode)
        if viewModel.phase == .preparing, pageMode == .unsigned {
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
                        open(app, in: pageMode)
                    } label: {
                        ImportedAppRow(
                            app: app,
                            mode: pageMode,
                            displayName: viewModel.displayName(for: app),
                            iconData: viewModel.displayIconData(for: app),
                            signedIPAFileStatus: viewModel.signedIPAFileStatus(for: app)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("复制 Bundle ID") {
                            SealPasteboard.copy(
                                displayBundleIdentifier(for: app, mode: pageMode),
                                announcement: "Bundle ID 已复制"
                            )
                        }
                        Button("查看详情") { detailApp = app }
                        if pageMode == .unsigned {
                            Button(role: .destructive) { pendingDeleteApp = app } label: {
                                Text(viewModel.isDeleting(appID: app.id) ? "正在删除…" : "删除应用")
                            }
                            .disabled(viewModel.isDeleting(appID: app.id))
                        } else if pageMode == .signed {
                            Button("安装") { signedActionApp = app }
                            Button("导出") { signedActionApp = app }
                            Button(role: .destructive) { signedActionApp = app } label: {
                                Text("删除已签名 IPA")
                            }
                        } else if app.isSeal == false, isExpired(app) {
                            Button(role: .destructive) { pendingDeleteApp = app } label: {
                                Text(viewModel.isDeleting(appID: app.id) ? "正在删除…" : "删除记录")
                            }
                            .disabled(viewModel.isDeleting(appID: app.id))
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

    private func displayBundleIdentifier(
        for app: AppRecord,
        mode pageMode: AppListPresentationMode
    ) -> String {
        switch pageMode {
        case .unsigned:
            return app.preferredBundleIdentifier
                ?? BundleIDPolicy.recommendedBundleIdentifier(for: app.originalBundleIdentifier)
        case .signed, .installed:
            return app.mappedBundleIdentifier
                ?? app.preferredBundleIdentifier
                ?? app.originalBundleIdentifier
        }
    }

    private func emptyState(_ pageMode: AppListPresentationMode) -> some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateIcon(pageMode))
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.sealAccent)
            Text(emptyStateTitle(pageMode))
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

    private func open(_ app: AppRecord, in pageMode: AppListPresentationMode) {
        switch pageMode {
        case .unsigned, .installed:
            viewModel.presentOperation(for: app)
        case .signed:
            signedActionApp = app
        }
    }

    private func apps(for pageMode: AppListPresentationMode) -> [AppRecord] {
        switch pageMode {
        case .unsigned: viewModel.unsignedApps
        case .signed: viewModel.signedApps
        case .installed: viewModel.installedApps
        }
    }

    private func appCount(for pageMode: AppListPresentationMode) -> Int {
        apps(for: pageMode).count
    }

    private var modeIndex: Int {
        AppListPresentationMode.allCases.firstIndex(of: mode) ?? 0
    }

    private func move(to destination: AppListPresentationMode) {
        withAnimation(.easeInOut(duration: 0.25)) {
            mode = destination
        }
    }

    private func moveToSigningResult() {
        guard case .succeeded(let result) = viewModel.signingSession?.status else { return }
        move(to: result.state == .installed ? .installed : .signed)
    }

    private func presentSigningAfterSignedDrawer(for app: AppRecord) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            viewModel.presentOperation(for: app)
        }
    }

    private func resolveInitialModeIfNeeded() {
        guard didResolveInitialMode == false else { return }
        didResolveInitialMode = true
        let allEmpty = viewModel.unsignedApps.isEmpty
            && viewModel.signedApps.isEmpty
            && viewModel.installedApps.isEmpty
        mode = allEmpty ? .unsigned : .installed
    }

    private func emptyStateIcon(_ pageMode: AppListPresentationMode) -> String {
        switch pageMode {
        case .unsigned: "square.and.arrow.down"
        case .signed: "checkmark.seal"
        case .installed: "app.badge.checkmark"
        }
    }

    private func emptyStateTitle(_ pageMode: AppListPresentationMode) -> String {
        switch pageMode {
        case .unsigned: "暂无待签名应用"
        case .signed: "暂无已签名 IPA"
        case .installed: "暂无已安装应用"
        }
    }

    private var deleteAlertTitle: String {
        pendingDeleteApp?.state == .installed ? "删除记录？" : "删除应用？"
    }

    private var deleteAlertMessage: String {
        guard pendingDeleteApp?.state == .installed else {
            return "删除后将从 Seal 的待签名列表中移除，并删除 Seal 保存的 IPA 文件，不会影响手机上已安装的应用。"
        }
        return "该应用已过期。删除后将从 Seal 的已安装列表中移除，不会卸载手机上的应用。"
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
                viewModel.selectedOperationApp == nil && signedActionApp == nil
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

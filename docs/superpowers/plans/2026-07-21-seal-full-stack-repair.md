# Seal Full-Stack Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Seal 已审查出的安全、数据一致性、签名安装状态和前端体验缺陷，并产出可由 macOS CI 打包的非纯黑自适应主题版本。

**Architecture:** 保留现有 SwiftUI + actor/service + Core Data 架构，在基础设施边界增加可回滚文件事务与应用操作 lease，在签名/安装边界传播结构化取消，在 ViewModel 层集中导航和异步意图。每项行为先由 XCTest 固定，再做最小实现。

**Tech Stack:** Swift 6、SwiftUI、Core Data、XCTest、AltSign、Minimuxer、XcodeGen、GitHub Actions。

---

> 当前工作区没有 `.git` 元数据。以下提交命令记录推荐的提交边界，但在本工作区不能执行；实施时以计划勾选和文件校验代替。

## 文件结构

- `Seal/Core/Operations/AppOperationCoordinator.swift`：应用级互斥 lease 与 busy 快照。
- `Seal/Infrastructure/Storage/AppFileTransaction.swift`：两阶段文件提交句柄，唯一负责 finalize/rollback。
- `Seal/Core/Accounts/AppleTeamOption.swift`：账号团队选择的 Sendable 展示模型。
- `Seal/DesignSystem/SealPalette.swift`：浅色/深色语义颜色的唯一来源。
- 现有 service/coordinator 文件只保留领域流程；视图不直接拼装事务或并发控制。

### Task 1: 修正测试与 CI 基线

**Files:**
- Modify: `.github/workflows/ios.yml`
- Modify: `project.yml`
- Modify: `SealTests/Import/ImportWorkflowTests.swift`
- Modify: `SealTests/Signing/BundleIDMapperTests.swift`
- Modify: `SealTests/Signing/SelfRenewalContextValidatorTests.swift`
- Modify: `SealTests/Recovery/AppRecordRecoveryTests.swift`
- Modify: `SealUITests/ImportFlowUITests.swift`
- Modify: `SealUITests/RootNavigationUITests.swift`

- [ ] **Step 1: 让失效测试表达当前批准的产品契约**

将断言固定为：导入确认前为 `.imported`；默认 Bundle ID 为 `original + ".seal"`；孤儿恢复为 `.imported`；UI 标题使用当前实际文案和稳定 accessibility identifier。

```swift
XCTAssertEqual(record.state, .imported)
XCTAssertEqual(mapped, "com.example.demo.seal")
XCTAssertEqual(recovered.state, .imported)
```

- [ ] **Step 2: 在 macOS 上运行旧实现并验证新断言失败**

Run: `xcodegen generate && bash Scripts/ci-test.sh`

Expected: Bundle ID、恢复状态或旧 UI 断言至少一项 FAIL，证明测试会捕获缺陷。

- [ ] **Step 3: CI 在打包前执行测试**

在 `Generate Xcode project` 后加入：

```yaml
      - name: Run tests
        run: bash Scripts/ci-test.sh

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: Seal-TestResults-${{ github.run_number }}
          path: build/TestResults.xcresult
          if-no-files-found: warn
```

并在 `project.yml` 同时声明 portrait 与 landscape：

```yaml
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
```

- [ ] **Step 4: 生成工程并验证 YAML/脚本**

Run: `xcodegen generate && bash Scripts/ci-test.sh`

Expected: 工程可生成；测试继续只因尚未实现的行为而失败。

- [ ] **Step 5: 推荐提交边界**

```bash
git add .github/workflows/ios.yml project.yml SealTests SealUITests
git commit -m "test: align CI and regression expectations"
```

### Task 2: Portal、Bundle ID 与团队选择安全

**Files:**
- Create: `Seal/Core/Accounts/AppleTeamOption.swift`
- Modify: `Seal/Core/Accounts/AuthenticatedAppleAccount.swift`
- Modify: `Seal/Infrastructure/Accounts/AppleAccountClient.swift`
- Modify: `Seal/Features/Settings/AddAccountView.swift`
- Modify: `Seal/Features/Settings/SettingsViewModel.swift`
- Modify: `Seal/Core/Signing/BundleIDMapper.swift`
- Modify: `Seal/Core/Signing/BundleIDPolicy.swift`
- Modify: `Seal/Infrastructure/Signing/ApplePortalSigningService.swift`
- Test: `SealTests/Accounts/AppleAccountClientTests.swift`
- Test: `SealTests/Signing/ApplePortalSigningFailureTests.swift`
- Test: `SealTests/Signing/BundleIDMapperTests.swift`

- [ ] **Step 1: 写证书上限、Bundle ID 与多团队失败测试**

```swift
func testCertificateLimitNeverRequestsAutomaticRevocation() async throws {
    let portal = PortalSpy(certificates: [.existing("A"), .existing("B")])
    await XCTAssertThrowsImportFailure(code: "SEAL-CERT-211") {
        try await service.ensureCertificate(using: portal)
    }
    XCTAssertEqual(portal.revokedSerialNumbers, [])
}

func testDefaultBundleIDUsesSealSuffix() throws {
    XCTAssertEqual(try BundleIDMapper.map("com.example.app"), "com.example.app.seal")
}

func testMultipleTeamsRequireExplicitSelection() async throws {
    let result = try await client.beginAuthentication(email: "a@b.com", password: "x", verificationCode: { nil })
    XCTAssertEqual(result.teams.map(\.identifier), ["T1", "T2"])
    XCTAssertNil(result.selectedAccount)
}
```

- [ ] **Step 2: 在 macOS 验证测试因自动撤销、原 Bundle ID 和自动选首队失败**

Run: `xcodebuild test -project Seal.xcodeproj -scheme Seal -only-testing:SealTests/AppleAccountClientTests -only-testing:SealTests/ApplePortalSigningFailureTests -only-testing:SealTests/BundleIDMapperTests`

Expected: FAIL with unexpected revoke / original identifier / selected first team.

- [ ] **Step 3: 引入显式团队选择模型**

```swift
struct AppleTeamOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isFreeTeam: Bool
}

struct PendingAppleAuthentication: Sendable {
    let accountIdentifier: String
    let secret: AccountSecret
    let maskedEmail: String
    let teams: [AppleTeamOption]

    func complete(team: AppleTeamOption) -> AuthenticatedAppleAccount
}
```

`AppleAccountClient` 先返回 `PendingAppleAuthentication`，只有一个团队时可由界面明确展示并确认；两个及以上团队必须由 `AddAccountView` 选择后完成。密码、token 与 session 只留在当前 ViewModel 生命周期，不写入日志或 UserDefaults。

- [ ] **Step 4: 禁用证书自动撤销并安全合并 App ID**

证书满额直接抛出：

```swift
throw ImportFailure(
    title: "证书数量已达上限",
    reason: "Apple 开发者账号没有可用的证书名额。Seal 不会自动撤销现有证书。",
    recovery: "请在证书管理中明确选择要撤销的证书后重试",
    code: "SEAL-CERT-211"
)
```

Portal 更新使用保守合并：

```swift
updated.features.merge(features) { existing, _ in existing }
updated.entitlements.merge(filteredEntitlements) { existing, _ in existing }
```

- [ ] **Step 5: 实现 `.seal` 默认映射并保留显式覆盖**

```swift
let normalized = original.trimmingCharacters(in: .whitespacesAndNewlines)
return requested?.nonEmpty ?? "\(normalized).seal"
```

- [ ] **Step 6: 运行定向与全量测试**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/AppleAccountClientTests -only-testing:SealTests/ApplePortalSigningFailureTests -only-testing:SealTests/BundleIDMapperTests`

Expected: PASS, revoke spy count is zero.

- [ ] **Step 7: 推荐提交边界**

```bash
git add Seal/Core/Accounts Seal/Core/Signing Seal/Infrastructure/Accounts Seal/Infrastructure/Signing Seal/Features/Settings SealTests
git commit -m "fix: require explicit portal and team choices"
```

### Task 3: 两阶段文件事务与恢复一致性

**Files:**
- Create: `Seal/Infrastructure/Storage/AppFileTransaction.swift`
- Modify: `Seal/Infrastructure/Storage/AppFileStore.swift`
- Modify: `Seal/Core/Import/ImportWorkflow.swift`
- Modify: `Seal/Infrastructure/Persistence/CoreDataAppStore.swift`
- Modify: `Seal/Core/Recovery/AppRecordRecovery.swift`
- Test: `SealTests/Storage/AppFileStoreTests.swift`
- Test: `SealTests/Import/ImportWorkflowTests.swift`
- Test: `SealTests/Persistence/CoreDataAppStoreTests.swift`
- Test: `SealTests/Recovery/AppRecordRecoveryTests.swift`

- [ ] **Step 1: 写数据库失败恢复旧 IPA 的测试**

```swift
func testReplacementSaveFailureRestoresPreviousIPA() async throws {
    let previous = try await fixture.importOriginalIPA()
    appStore.failNextSave = true
    await workflow.importReplacement(fixture.replacementIPA)
    XCTAssertEqual(try Data(contentsOf: previous.url), previous.data)
    XCTAssertFalse(fileManager.fileExists(atPath: previous.backupPath))
}
```

同时新增 Core Data delete 失败后 context `hasChanges == false` 的测试，以及孤儿文件恢复为 `.imported` 的测试。

- [ ] **Step 2: 验证旧实现会删除备份或留下脏 context**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/AppFileStoreTests -only-testing:SealTests/ImportWorkflowTests -only-testing:SealTests/CoreDataAppStoreTests -only-testing:SealTests/AppRecordRecoveryTests`

Expected: FAIL because backup is removed before database commit.

- [ ] **Step 3: 创建事务句柄**

```swift
struct AppFileTransaction: Sendable {
    let files: StoredAppFiles
    fileprivate let finalURLs: [URL]
    fileprivate let backupPairs: [(original: URL, backup: URL)]
}

actor AppFileStore {
    func prepareCommit(...) async throws -> AppFileTransaction
    func finalize(_ transaction: AppFileTransaction) async throws
    func rollback(_ transaction: AppFileTransaction) async throws
}
```

`prepareCommit` 不删除备份；`finalize` 只删除备份；`rollback` 先移除新文件，再原子恢复每个旧文件。

- [ ] **Step 4: ImportWorkflow 先保存数据库再 finalize**

```swift
let transaction = try await fileStore.prepareCommit(draft)
do {
    try await appStore.replace(existing: existing, with: record(using: transaction.files))
    try await fileStore.finalize(transaction)
} catch {
    try? await fileStore.rollback(transaction)
    throw error
}
```

- [ ] **Step 5: Core Data 所有写操作统一 rollback**

```swift
do {
    try context.save()
} catch {
    context.rollback()
    throw AppStoreError.persistence(error)
}
```

- [ ] **Step 6: 恢复扫描不推断安装完成**

```swift
record.state = .imported
record.expiryDate = nil
record.lastInstalledAt = nil
```

- [ ] **Step 7: 运行测试并推荐提交**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/AppFileStoreTests -only-testing:SealTests/ImportWorkflowTests -only-testing:SealTests/CoreDataAppStoreTests -only-testing:SealTests/AppRecordRecoveryTests`

Expected: PASS.

```bash
git add Seal/Infrastructure/Storage Seal/Core/Import Seal/Infrastructure/Persistence Seal/Core/Recovery SealTests
git commit -m "fix: make app file replacement transactional"
```

### Task 4: 操作 lease、清理与 SelfAppRegistrar

**Files:**
- Create: `Seal/Core/Operations/AppOperationCoordinator.swift`
- Modify: `Seal/Application/AppContainer.swift`
- Modify: `Seal/Features/Apps/AppsViewModel.swift`
- Modify: `Seal/Features/Settings/SettingsViewModel.swift`
- Modify: `Seal/Core/Renewal/SelfAppRegistrar.swift`
- Modify: `Seal/Infrastructure/Storage/AppFileStore.swift`
- Test: `SealTests/Renewal/SelfAppRegistrarTests.swift`
- Test: `SealTests/Storage/AppFileStoreTests.swift`

- [ ] **Step 1: 写清理跳过活动应用和 registrar 保留元数据的测试**

```swift
func testClearCacheSkipsLeasedApp() async throws {
    let lease = try await coordinator.acquire(appID: app.id, operation: .signing)
    defer { Task { await lease.release() } }
    let result = try await maintenance.clearCaches()
    XCTAssertTrue(result.skippedAppIDs.contains(app.id))
}

func testRegistrarPreservesAccountAndInstallMetadata() async throws {
    let updated = try await registrar.register(existingSignedSeal)
    XCTAssertEqual(updated.accountID, existing.accountID)
    XCTAssertEqual(updated.lastInstalledAt, existing.lastInstalledAt)
    XCTAssertEqual(updated.signedIPARelativePath, existing.signedIPARelativePath)
}
```

- [ ] **Step 2: 验证旧实现会清理瞬时状态或覆盖元数据**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/SelfAppRegistrarTests -only-testing:SealTests/AppFileStoreTests`

Expected: FAIL.

- [ ] **Step 3: 实现 lease actor**

```swift
actor AppOperationCoordinator {
    enum Kind: Sendable { case importing, signing, installing, refreshing, selfReplacing, cleaning }
    struct Lease: Sendable { let id: UUID; let appID: UUID?; let kind: Kind }

    func acquire(appID: UUID?, kind: Kind) throws -> Lease
    func release(_ lease: Lease)
    func isBusy(appID: UUID) -> Bool
    func snapshot() -> Set<UUID>
}
```

清理先获取全局 `.cleaning` lease，并根据 snapshot 跳过活动 app；业务流程在 `defer` 中释放 lease。

- [ ] **Step 4: Registrar 使用事务并保守合并**

账号读取失败直接抛出；无法匹配新账号时保留 existing binding；只有新值经过验证时才覆盖签名字段。重复数据库记录在同一维护操作中删除其受控文件，且恢复扫描看不到残留。

- [ ] **Step 5: 运行测试并推荐提交**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/SelfAppRegistrarTests -only-testing:SealTests/AppFileStoreTests`

Expected: PASS.

```bash
git add Seal/Core/Operations Seal/Application Seal/Features Seal/Core/Renewal Seal/Infrastructure/Storage SealTests
git commit -m "fix: coordinate destructive app operations"
```

### Task 5: 配对、签名、缓存与取消状态机

**Files:**
- Modify: `Vendor/Minimuxer/Sources/Muxer.swift`
- Modify: `Seal/Infrastructure/Installation/MinimuxerInstallChannel.swift`
- Modify: `Seal/Core/Installation/InstallChannel.swift`
- Modify: `Seal/Core/Signing/SigningCoordinator.swift`
- Modify: `Seal/Core/Signing/SigningSession.swift`
- Modify: `Seal/Features/Apps/AppsViewModel.swift`
- Test: `SealTests/Installation/MinimuxerInstallChannelTests.swift`
- Test: `SealTests/Signing/SigningCoordinatorTests.swift`

- [ ] **Step 1: 写敏感缓存释放、缓存安装和取消传播测试**

```swift
func testPairRecordIsUnavailableAfterOperationStops() async throws {
    try await channel.start()
    await channel.stop()
    XCTAssertNil(await muxer.cachedPairRecord)
    XCTAssertFalse(await muxer.isListening)
}

func testValidSignedIPAInstallsWithoutPortalSigning() async throws {
    _ = try await coordinator.signAndInstall(appID: app.id, accountID: account.id, progress: { _ in })
    XCTAssertEqual(portal.signCallCount, 0)
    XCTAssertEqual(channel.installCallCount, 1)
}

func testCancellationRemainsCancellation() async {
    channel.installError = CancellationError()
    await XCTAssertThrowsCancellation { try await coordinator.signAndInstall(...) }
}
```

- [ ] **Step 2: 验证旧实现泄露/未命中缓存/把取消包装为错误**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/MinimuxerInstallChannelTests -only-testing:SealTests/SigningCoordinatorTests`

Expected: FAIL.

- [ ] **Step 3: 收紧配对记录生命周期**

`Muxer` 在单次 operation scope 外不保存 pairing XML；`stop()` 关闭 listener、取消 connection tasks 并清空 Data。无法做到进程内凭据消费的旧配对格式返回明确错误 `SEAL-PAIR-301`，引导重新配对，不开放长期 `ReadPairRecord`。

- [ ] **Step 4: 使用结构化取消**

删除 self-replacing 的 `Task.detached`；所有 `catch` 首先保留 `CancellationError`：

```swift
} catch is CancellationError {
    throw CancellationError()
} catch {
    throw Self.installFailure(from: error)
}
```

同步底层调用前后 `try Task.checkCancellation()`；等待轮询不再使用 `try? await Task.sleep` 吞掉取消。

- [ ] **Step 5: 在 Portal 签名前调用缓存安装**

```swift
let deviceIdentifier = try await installChannel.start()
if let cached = try await installCachedSignedIPAIfPossible(
    app: app,
    account: account,
    targetBundleIdentifier: targetBundleIdentifier,
    certificateSerialNumber: effectiveCertificateSerialNumber,
    deviceIdentifier: deviceIdentifier,
    progress: progress
) { return cached }
```

- [ ] **Step 6: 运行测试并推荐提交**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/MinimuxerInstallChannelTests -only-testing:SealTests/SigningCoordinatorTests`

Expected: PASS.

```bash
git add Vendor/Minimuxer Seal/Infrastructure/Installation Seal/Core/Installation Seal/Core/Signing Seal/Features/Apps SealTests
git commit -m "fix: secure and cancel installation operations"
```

### Task 6: 每日续签与通知调度竞态

**Files:**
- Modify: `Seal/Core/Renewal/DailyAutoRenewStateStore.swift`
- Modify: `Seal/Core/Renewal/BatchRefreshSession.swift`
- Modify: `Seal/Core/Renewal/RenewalCoordinator.swift`
- Modify: `Seal/Infrastructure/Renewal/RefreshQueueStore.swift`
- Modify: `Seal/Infrastructure/Notifications/ExpiryNotificationScheduler.swift`
- Modify: `Seal/Features/Settings/SettingsViewModel.swift`
- Test: `SealTests/Renewal/DailyAutoRenewStateStoreTests.swift`
- Test: `SealTests/Renewal/RefreshQueueStoreTests.swift`
- Test: `SealTests/Notifications/ExpiryNotificationSchedulerTests.swift`

- [ ] **Step 1: 写部分成功续跑和 latest-intent-wins 测试**

```swift
func testNextDailyRunOnlyRetriesUnfinishedItems() async throws {
    await session.recordSuccess(appID: first.id)
    await session.recordFailure(appID: second.id, failure: failure)
    XCTAssertEqual(await session.pendingIDsForNextRun(), [second.id])
}

func testOlderEnableCannotOverrideNewerDisable() async throws {
    async let enable: Void = scheduler.setEnabled(true)
    await scheduler.setEnabled(false)
    _ = try await enable
    XCTAssertEqual(center.pendingIdentifiers, [])
}
```

- [ ] **Step 2: 验证旧实现重复成功项并允许旧请求回写**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/DailyAutoRenewStateStoreTests -only-testing:SealTests/RefreshQueueStoreTests -only-testing:SealTests/ExpiryNotificationSchedulerTests`

Expected: FAIL.

- [ ] **Step 3: 持久化单项终态**

队列合并时保留 `.succeeded`，新计划只加入缺失或失败项；`previousExpiry == nil` 不能被判定为续签成功，必须以新的签名产物/安装时间为依据。

- [ ] **Step 4: 调度器加入 generation**

```swift
private var generation = 0

func setEnabled(_ enabled: Bool) async throws {
    generation += 1
    let requestGeneration = generation
    // await authorization / pending requests
    guard requestGeneration == generation else { return }
    if enabled { try await addCurrentRequests() } else { await removeAll() }
}
```

设置页通过一个受控 Task 串行提交最新意图，并在请求中禁用 Toggle。

- [ ] **Step 5: 运行测试并推荐提交**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/DailyAutoRenewStateStoreTests -only-testing:SealTests/RefreshQueueStoreTests -only-testing:SealTests/ExpiryNotificationSchedulerTests`

Expected: PASS.

```bash
git add Seal/Core/Renewal Seal/Infrastructure/Renewal Seal/Infrastructure/Notifications Seal/Features/Settings SealTests
git commit -m "fix: resume renewal and serialize notifications"
```

### Task 7: 前端导航、确认、错误恢复和加载

**Files:**
- Modify: `Seal/Features/Apps/AppsRootView.swift`
- Modify: `Seal/Features/Apps/AppDetailView.swift`
- Modify: `Seal/Features/Apps/AppSigningSheet.swift`
- Modify: `Seal/Features/Apps/SigningProgressView.swift`
- Modify: `Seal/Features/Apps/BatchRefreshView.swift`
- Modify: `Seal/Features/Apps/AppsViewModel.swift`
- Modify: `Seal/Features/Import/ImportConfirmationView.swift`
- Modify: `Seal/Features/Settings/SettingsRootView.swift`
- Modify: `Seal/Features/Settings/SettingsViewModel.swift`
- Test: `SealTests/Apps/AppPresentationTests.swift`
- Test: `SealUITests/ImportFlowUITests.swift`
- Test: `SealUITests/RootNavigationUITests.swift`

- [ ] **Step 1: 写纯状态测试覆盖确认、sheet handoff 和 INSTALL-706 恢复**

```swift
func testPreflightDoesNotAutoConfirmImport() async {
    await viewModel.consumeWorkflowState(.readyForConfirmation(draft))
    XCTAssertEqual(viewModel.presentedSheet, .importConfirmation)
    XCTAssertFalse(viewModel.didConfirmImport)
}

func testDetailOperationWaitsForDismissal() {
    router.requestOperation(.sign(appID))
    XCTAssertNil(router.presentedOperation)
    router.detailDidDismiss()
    XCTAssertEqual(router.presentedOperation, .sign(appID))
}
```

- [ ] **Step 2: 验证旧实现自动确认或竞争展示**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/AppPresentationTests`

Expected: FAIL.

- [ ] **Step 3: 集中父级 presentation route**

详情只写 `pendingOperation` 并 dismiss；`AppsRootView` 在 detail sheet `onDismiss` 调用 `presentPendingOperation()`。错误恢复先保存 route，再清空 alert。

- [ ] **Step 4: 暴露取消按钮和中间状态**

```swift
Button(viewModel.isCancellationPending ? "正在等待当前步骤结束…" : "取消") {
    viewModel.cancelSigning()
}
.disabled(viewModel.isCancellationPending)
.accessibilityIdentifier("signing.cancel")
```

批量续签使用对应 `cancelBatchRefresh()`，只有终态允许交互式 dismiss。

- [ ] **Step 5: 删除重复生命周期加载并实现 single-flight**

根视图保留一个 `.task { await viewModel.loadIfNeeded() }`；ViewModel 保存 `loadTask`，并发调用等待同一任务而不是 force reload。

- [ ] **Step 6: 设置页统一类型化导航**

```swift
enum SettingsRoute: Hashable {
    case account(UUID), certificates, notifications, storage, pairing
    case guide, privacy, about, licenses, logs
}
```

所有 `NavigationLink(value:)` 由单一 `.navigationDestination(for: SettingsRoute.self)` 解析。

- [ ] **Step 7: 运行测试并推荐提交**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/AppPresentationTests -only-testing:SealUITests`

Expected: PASS.

```bash
git add Seal/Features/Apps Seal/Features/Import Seal/Features/Settings SealTests SealUITests
git commit -m "fix: stabilize navigation and async controls"
```

### Task 8: 自适应主题、布局、无障碍与性能

**Files:**
- Create: `Seal/DesignSystem/SealPalette.swift`
- Modify: `Seal/DesignSystem/SealBackdrop.swift`
- Modify: `Seal/DesignSystem/GlassSurface.swift`
- Modify: `Seal/App/RootTabView.swift`
- Modify: `Seal/Features/Apps/AppsRootView.swift`
- Modify: `Seal/Features/Apps/ImportedAppRow.swift`
- Modify: `Seal/Features/Apps/AccountSelectionView.swift`
- Modify: `Seal/Features/Apps/AppSigningSheet.swift`
- Modify: `Seal/Features/Import/ImportConfirmationView.swift`
- Modify: `Seal/Features/Settings/CertificatesRootView.swift`
- Modify: `Seal/Features/Settings/AppleAccountDetailView.swift`
- Modify: remaining `Seal/Features/**/*.swift` fixed-size fonts and icon buttons
- Test: `SealTests/Apps/AppPresentationTests.swift`
- Test: `SealUITests/RootNavigationUITests.swift`

- [ ] **Step 1: 写主题与 accessibility identifier 静态回归测试**

```swift
func testBackdropColorsAreNotPureBlack() {
    XCTAssertNotEqual(SealPalette.dark.background, UIColor.black)
    XCTAssertGreaterThan(SealPalette.light.background.relativeLuminance, 0.7)
}
```

UI 测试在浅色与深色 launch argument 下验证根页面、取消按钮和账号选择元素存在。

- [ ] **Step 2: 验证旧主题因强制 dark/black 失败**

Run: `bash Scripts/ci-test.sh -only-testing:SealTests/AppPresentationTests -only-testing:SealUITests/RootNavigationUITests`

Expected: FAIL because root forces dark and backdrop uses near-black literals.

- [ ] **Step 3: 建立语义 palette 并移除强制深色**

```swift
enum SealPalette {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.075, blue: 0.13, alpha: 1)
            : UIColor(red: 0.94, green: 0.965, blue: 0.985, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
}
```

删除 `.preferredColorScheme(.dark)`；背景渐变以 palette 为输入，深色使用海军蓝而不是纯黑。

- [ ] **Step 4: 让 sheet 和列表适配小屏/横屏/大字**

固定 `VStack` 改为 `ScrollView { LazyVStack(...) }`，底部主操作使用 `safeAreaInset(edge: .bottom)`；移除仅 `.height(260)`/`.height(500)` detent，至少加入 `.large`。

- [ ] **Step 5: 修复无障碍**

所有 icon-only button 增加 `accessibilityLabel`，点击区域至少 44×44；选中账号增加 `.accessibilityAddTraits(.isSelected)`；装饰图 `.accessibilityHidden(true)`；应用行朗读 `displayName` 和本地化状态。

- [ ] **Step 6: 修复 Dynamic Type 和渲染热点**

固定字号替换为 `.body/.headline/.caption/.title2` 等语义字体；列表使用 `LazyVStack` 与稳定 `Identifiable`；`UIImage(data:)` 解码移到 `@MainActor` ViewModel 缓存，不在 View body 重复执行。

- [ ] **Step 7: 运行测试并推荐提交**

Run: `bash Scripts/ci-test.sh`

Expected: unit + UI tests PASS on macOS simulator.

```bash
git add Seal/DesignSystem Seal/App Seal/Features project.yml SealTests SealUITests
git commit -m "feat: add adaptive accessible Seal theme"
```

### Task 9: 全量验证与 IPA 产物

**Files:**
- Modify: `修改验收说明.md`
- Verify: `Scripts/build-unsigned-ipa.sh`
- Verify: `Scripts/verify-ipa.sh`

- [ ] **Step 1: 全量静态检查**

Run: `rg '\.preferredColorScheme\(\.dark\)|UIColor\.black|Color\.black' Seal`

Expected: 没有全局背景强制 dark/black；业务上确有语义的黑色内容必须有行内说明。

Run: `rg 'Task \{|Task\.detached|try\? await Task\.sleep' Seal Vendor/Minimuxer/Sources`

Expected: 所有命中均经人工确认有所有者、取消和生命周期。

- [ ] **Step 2: macOS 全量构建测试**

Run: `xcodegen generate && bash Scripts/ci-test.sh`

Expected: PASS with no Swift 6 concurrency errors.

- [ ] **Step 3: 构建并验证 unsigned IPA**

Run: `bash Scripts/build-unsigned-ipa.sh && bash Scripts/verify-ipa.sh build/Seal.ipa`

Expected: `build/Seal.ipa`、`build/Seal.ipa.sha256`、`build/Seal-Info.plist` 存在，校验脚本 PASS。

- [ ] **Step 4: 更新验收说明**

记录主题、取消、团队选择、证书策略、事务回滚、续签恢复、测试结果和 IPA SHA-256；明确 unsigned IPA 仍需用户使用自己的 Apple 账号签名。

- [ ] **Step 5: 推荐提交边界**

```bash
git add 修改验收说明.md
git commit -m "docs: record full-stack repair acceptance"
```

## 计划自检

- 设计文档第 3 节由 Tasks 2–5 覆盖。
- 第 4 节由 Tasks 5–7 覆盖。
- 第 5–7 节由 Tasks 7–8 覆盖。
- 第 8–10 节由每个任务的失败测试、Task 1 CI 和 Task 9 验收覆盖。
- 计划不包含占位步骤或未定义的“以后处理”事项。
- 新增类型名称在所有后续任务中保持一致：`AppleTeamOption`、`PendingAppleAuthentication`、`AppFileTransaction`、`AppOperationCoordinator`、`SealPalette`。

# Seal 严格闭环修复与验证报告

## 1. 交付基线与变更边界

- 稳定基线：`5e83814`（稳定构建与外观审计基线）
- 本次最终本地提交：`578f507 Complete strict signed IPA storage and drawer recovery`
- 从基线到最终提交共变更 59 个源代码／测试／CI 文件。
- 修改范围仅覆盖已确认事项：Apple ID 离线恢复、Bundle ID、App 名称与图标、已签名 IPA、三段导航、抽屉系统、数据事务、操作协调、通知与队列、外观、无障碍、日志安全、Vendor 崩溃点和 CI 测试。
- 未改回 RustBridge 每次重编译路线；保留预编译 `RustBridge.xcframework`。
- 未改变已确认的全局左右排版；未替换固定文案 `Team / Bundle ID / Serial / LocalDevVPN / Apple 返回`。

## 2. P0：飞行模式后 Apple ID 不可选择

已完成：

- 网络断开、飞行模式、DNS、超时、TLS 中断、Apple 服务暂时异常归类为临时网络错误。
- 临时网络错误不再把 Apple ID 持久化为 `needsVerification`。
- 本机已保存的 Apple ID 无论当前状态如何都保留在选择器中；`verified` 账号优先排序。
- 保留 `activeAccountID`，重新联网后无需删除账号或重新添加。
- 只有明确认证失效、会话撤销、凭据不一致或 Keychain 凭据缺失才进入重新验证流程。
- 已被旧版本误标的账号仍可选择；成功访问 Apple 服务后自动恢复为 `verified`。
- 增加离线、超时、真正认证失效和重新加载选择器回归测试。

## 3. Bundle ID 闭环

已完成：

- 第三方 IPA 首次签名默认在原 Bundle ID 后追加 `.seal`。
- 已有 `.seal` 后缀时忽略大小写防重复，不产生 `.seal.seal`。
- Seal 自身续签沿用实际安装 Bundle ID，不追加 `.seal`。
- `.seal` 在列表、签名确认和签名结果中使用 Seal 蓝色显示。
- Bundle ID 编辑采用统一抽屉：标题 `修改 Bundle ID`、实时校验、错误显示在输入框下方、取消与保存同一行，不包含“恢复默认”。
- 首次签名可编辑；续签锁定上次成功的 `mappedBundleIdentifier`。
- 扩展 Bundle ID 保持相对后缀映射，例如主 App `.seal` 后，Widget／Share 延续原扩展后缀。
- 分离 `originalBundleIdentifier / preferredBundleIdentifier / mappedBundleIdentifier`。

## 4. App 名称、图标与签名草稿

已完成：

- 首次签名前可修改安装后的 App 名称。
- 可从照片或文件选择图标，也可使用原图。
- 修改内容进入实际签名工作区，不仅改变 Seal 列表预览。
- 签名失败或安装失败后保留名称、图标、Bundle ID、Apple ID、Team、Serial 和签名方式。
- 成功生成正式签名 IPA 后，以原始 Bundle ID 为键保存名称、图标和上次成功 Bundle ID；下次导入相同 App 自动带入。

## 5. 待签名／已签名／已安装三段导航

已完成：

- 顺序固定为 `待签名｜已签名｜已安装`。
- 支持点击和左右滑动。
- 使用底部蓝色细指示条平滑移动，不使用蓝色胶囊选中背景。
- 正常启动默认已安装；全部为空默认待签名。
- 导入后进入待签名；仅签名成功进入已签名；签名并安装成功进入已安装；签名成功但安装失败进入已签名。
- 保留现有左右排版：图标在左，名称与版本在第一行，Bundle ID 在第二行，右侧显示大小／有效期／时间。
- 有效期仅显示 `6天 / 23小时 / 1小时 / 已过期`，不显示“剩余”“不足”“0天”或负数。
- 批量续签仍位于已安装标题右侧，三页标题栏采用相同高度，列表首项对齐。

## 6. 正式“已签名 IPA”闭环

已完成：

- 增加“仅签名”。
- 签名成功后先保存正式已签名 IPA，再执行安装。
- 正式签名文件使用版本化文件名，避免新旧文件覆盖时丢失。
- 每个正式签名 IPA 保存 SHA-256 与字节数元数据。
- 列表加载、安装和导出前验证文件存在性、大小和 SHA-256。
- 文件缺失或损坏时显示明确状态，并切换为重新签名操作。
- 签名成功、安装失败后保留签名包；再次操作直接安装，不重新创建 App ID、描述文件或签名。
- 已签名 IPA 支持安装、重新安装、导出和删除。
- 导出使用修改后的 App 名称与版本生成安全文件名，并显示设备描述文件限制提示。
- 删除已签名 IPA 不卸载设备上的 App，也不删除原始 IPA、Apple ID、Team、Serial 或名称／图标偏好。
- 安装完成后的自动清理只清理临时工作区，不删除正式已签名 IPA。

## 7. 文件和数据库事务

已完成：

- 原始 IPA 导入继续使用 prepare／commit／finalize／rollback 事务。
- 正式已签名 IPA 保存采用新文件写入、数据库提交、旧文件延后清理的顺序。
- 数据库保存失败时删除未提交的新签名文件并恢复原记录。
- 已签名 IPA 删除采用 tombstone 事务：先移动文件、再更新数据库、失败回滚、成功 finalize。
- App 启动时恢复未完成的原始文件事务、App 删除事务和已签名 IPA 删除事务。
- 数据库仍引用签名包时恢复文件；数据库已清除引用时完成残留删除。
- 无数据库引用的未提交签名版本与 `.pending` 文件会被清理。
- 仅发现原始 IPA 时恢复为待签名记录，不再误标为已安装。

## 8. Apple ID、Team、Serial 和证书

已完成／保留：

- 多 Team 时进入选择流程，不静默切换到错误 Team。
- 签名与续签记录绑定 Apple ID、Team、Serial、Bundle ID、描述文件和设备信息。
- Serial 选择按账号与 Team 验证，续签沿用原绑定身份。
- 新证书本地保存失败时执行本地回滚和远程撤销补偿，并保留明确错误信息。
- 网络错误与认证错误不再共用宽泛的失效处理。

## 9. 统一抽屉系统

已完成：

- 所有业务抽屉使用统一 `SealDrawer`。
- 顶部使用同一个拖动条和 30 pt 连续圆角。
- 移除固定 `.height(...)` detent，统一使用 medium／large 或 large。
- 中间正文使用 `ScrollView`，长内容、小屏和大字体不再直接裁切。
- 底部按钮通过 `safeAreaInset` 固定，适配 Home Indicator 与键盘。
- Bundle ID、App 名称、导入、签名、签名结果、账号选择、批量续签和已签名 IPA 操作均使用固定底部操作区。
- 移除自定义抽屉父级重复圆角设置；背景和圆角只由统一容器控制。
- 系统分享 Sheet 保留系统呈现方式，不混入业务抽屉结构。

## 10. 外观、排版与无障碍

已完成：

- 外观支持 `跟随系统 / 浅色 / 深色`，默认跟随系统并持久化。
- 删除固定深色锁定。
- 背景、卡片、抽屉、文字、状态色和分隔线使用动态颜色。
- 文本改用语义字体和 `@ScaledMetric`；固定字号主要仅保留在 SF Symbol 图标尺寸。
- App 行、导航、复制操作、状态和主要按钮增加 VoiceOver 信息。
- Bundle ID／Serial 支持完整查看、文本选择和复制。
- 错误操作按网络、认证、证书、Bundle ID、配对、LocalDevVPN、扩展和安装分别显示，不再出现两个相同“重试”。

## 11. 通知、续签队列、加载与日志

已完成：

- 通知区分 Seal 开关、系统授权状态、调度状态、下一次提醒和数量。
- 续签队列关键保存／删除失败不再全部静默忽略，并写入日志或页面错误。
- 设置页重复加载入口已移除；Apps／Settings 使用请求 generation 防止旧结果覆盖新结果。
- Tab 切换时刷新对应数据，使存储清理、签名和账号状态及时反映。
- 日志脱敏覆盖邮箱、Team、Serial、UDID、UUID、JWT、Cookie、Header、Base64 Token、描述文件标识及认证字段。

## 12. 崩溃风险与构建链

已完成：

- 移除 Minimuxer 中已审计的环境变量、Data 指针、设备字段和网络端口强制解包。
- 保留预编译 `Vendor/Minimuxer/RustBridge/lib/RustBridge.xcframework`。
- GitHub Actions 固定 `macos-15` 与 Xcode 16.4。
- CI 生成 Xcode 工程后运行 Swift 测试，再构建和校验未签名 IPA。
- CI 和脚本中没有重新引入 cargo／rustup／RustBridge 每次重编译步骤。

## 13. 本地验证结果

已执行：

- `swiftc -frontend -parse`：195 个 Swift 文件，失败 0。
- Swift Testing 声明数量：202 个 `@Test`。
- `git diff --check`：通过。
- `Scripts/*.sh` 的 `bash -n`：通过。
- `.github/workflows/ios.yml` YAML 解析：通过。
- 固定高度 Sheet 搜索：0。
- 固定 `.preferredColorScheme(.dark)` 搜索：0。
- CI／脚本 Rust 重编译命令搜索：0。
- 已审计 Minimuxer 强制解包模式搜索：0。
- 预编译 RustBridge：存在。
- 当前工作树：干净。

## 14. 环境限制

当前执行环境为 Linux，未安装 Xcode、iOS SDK、Simulator 和真机连接能力，因此未在本地声称完成：

- `xcodebuild` 全量类型检查；
- iOS Simulator UI 测试；
- 真机 Apple ID／LocalDevVPN／签名／安装测试。

这些测试已接入 macOS GitHub Actions。首次推送后应以 Actions 的 Swift 测试和 IPA 构建结果作为最终编译证据。

## 15. GitHub 状态

GitHub 写入集成此前返回 403，因此本次没有直接修改远端 `main`。交付 ZIP 是完整源码快照，不包含 `.git` 元数据；不得用它覆盖本地仓库的 `.git` 目录。

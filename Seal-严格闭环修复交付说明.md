# Seal 严格闭环修复交付说明

## 交付目标

本交付不是继续绕过单个 Swift 编译错误，而是统一 Seal 上层安装通道、
Minimuxer Swift API、Rust FFI、Rust 状态管理、测试依赖和 GitHub Actions
构建顺序，目标为：

`远程配对 → LocalDevVPN → 真实设备连接 → IPA 暂存 → 安装 → 真实 Bundle ID 查询验证 → 续签`

## 本次结构性修复

1. 恢复与当前 Seal 安装安全测试匹配的纯 Rust remote-pairing Minimuxer。
2. 补齐并统一 `stop / setRemotePairingFile / securitySnapshot` 生命周期 API。
3. Rust 配对文件改为可替换状态；停止时清除配对文件和缓存 RSD 连接。
4. `ready()` 必须同时满足已启动、存在配对文件和设备端口真实可达。
5. `lookupApp()` 通过 Installation Proxy 查询设备，不再直接返回传入 Bundle ID。
6. 删除旧的 Swift/libimobiledevice Rust bridge和不匹配的预编译 XCFramework。
7. GitHub Actions 在 XcodeGen 和 Swift 编译前，从锁定源码重建 RustBridge。
8. 删除阻塞 Rust 编译的未公开 personalized DDI 方法调用。
9. Personalized DDI 不属于 Seal 的签名、安装、续签闭环；保留兼容入口但明确返回不可用，
   不无限重试，也不伪造成功。
10. 新增源码契约检查，构建前验证关键 API、Rust 导出、真实安装查询和旧桥接残留。

## 已完成的本地验证

- 190 个 Swift 文件执行 `swiftc -frontend -parse`：通过。
- Minimuxer Swift 层使用临时 RustBridge 模块执行完整类型检查：通过。
- `Scripts/*.sh` 执行 `bash -n`：通过。
- `project.yml` 和 GitHub Actions YAML 解析：通过。
- `git diff --check`：通过。
- 冲突标记检查：通过。
- 关键 Swift/Rust API 契约检查：通过。
- 已确认此前纯 Rust 构建只剩 personalized DDI 单一编译阻塞；该调用现已从
  Rust 模块、FFI 和 Swift wrapper 中完整移除。

## 最终验证边界

当前执行环境没有 macOS、Xcode、iOS SDK 和 Apple 真机，因此不能在本地伪称 IPA
已经完成构建或真机闭环已经通过。交付包中的一键脚本会提交到 GitHub，并由
`macos-15 + Xcode 16.4` 完成以下最终门禁：

1. 源码契约检查；
2. Rust 单元测试；
3. iOS device / simulator / macOS Rust 静态库构建；
4. RustBridge.xcframework 生成及符号审计；
5. XcodeGen；
6. Swift 单元测试与 UI 测试；
7. 未签名 `Seal.ipa` 构建；
8. IPA 内容校验和上传。

只有 Actions 全绿并产出 `Seal.ipa`，才视为编译与打包闭环完成；真机 Apple ID、
签名、安装和续签仍以实际设备验收为最终证据。

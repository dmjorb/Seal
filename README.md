# Seal

## License

Seal is licensed under the GNU Affero General Public License v3.0. See
`LICENSE` and `Seal/Resources/ThirdPartyNotices.txt`.

Seal 是个人使用的 iOS IPA 管理、自签、安装与续签工具，最低支持 iOS 16。

## 功能

- 导入并检查 IPA，读取图标、版本、扩展与权限信息
- 添加 Apple ID、双重认证、免费与付费团队签名
- 导入设备配对文件，通过 LocalDevVPN 安装到当前 iPhone
- 单应用续签、批量刷新、失败续传与 Seal 自续签
- 到期提醒、连接诊断、日志导出、缓存清理与覆盖恢复
- 本机加密保存账号会话、证书和配对数据，不保存 Apple ID 密码

## 首次使用

1. 在 GitHub 仓库的 `Actions` 页面打开最新成功的 `iOS` 任务。
2. 下载 `Seal-任务编号`，解压后取得 `Seal.ipa`。
3. 在 Windows 使用自己的自签工具签名并安装 `Seal.ipa`。
4. 打开 Seal，在“设置”中添加 Apple ID、导入配对文件并安装 LocalDevVPN。
5. 返回“应用”，导入 IPA 后选择“签名并安装”。

后续更新 Seal 时使用相同 Bundle ID 覆盖安装，不要先卸载。

## 构建

Windows 可运行基础检查：

```powershell
.\Scripts\Tests\Test-Foundation.ps1
```

推送到 `feature/**` 或 `main` 后，GitHub Actions 会在 macOS 上生成 Xcode 工程、运行测试并打包未签名 IPA。构建产物同时包含 SHA-256 校验文件、Info.plist 和 UI 测试截图。

## 安全

不要提交证书、描述文件、Apple 登录信息或设备配对文件。仓库和 CI 均检查常见敏感文件。第三方组件及许可见 `Seal/Resources/ThirdPartyNotices.txt`。

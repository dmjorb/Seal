# Seal 配对助手

Windows 配对助手固定使用上游 `jkcoxson/idevice_pair` 的真实设备协议实现，Seal 只增加品牌、视觉和 App 集成层。

## 保留的上游功能

- USB 自动发现 iPhone/iPad
- Lockdown pairing
- RPPairing / CoreDeviceProxy / RSD
- 无线调试
- Developer Mode 检测
- Developer Disk Image 自动挂载
- Pairing 文件生成、加载、保存、验证
- 上游所有已支持 App 的直接写入
- Seal 直接写入

Seal 使用 `SealPairing.mobiledevicepairing` 作为 Documents 收件文件。Seal 会自动导入；手动导入继续作为恢复入口。

Windows 11 使用微软 DWM Desktop Acrylic 系统背景；Seal overlay 只改变品牌、视觉和 App 集成，不替换上游设备协议。配对密钥内容默认不在界面中明文展示。

## Windows 前置条件

按上游要求使用 Apple 官网 Windows iTunes / Apple Mobile Device 组件提供 usbmuxd 通道。
不再要求用户手工复制 `idevice_id.exe`、`idevicepair.exe`、`ideviceinfo.exe`。

## 上游固定版本

- repository: `jkcoxson/idevice_pair`
- commit: `e3abb341b73a4fbeb96cdfc5e6652687e4bee130`
- version: `0.1.14`
- license: MIT

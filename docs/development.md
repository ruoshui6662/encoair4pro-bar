# 开发说明

## 环境与模块

构建需要 Apple Silicon、macOS 26 SDK、Swift 6.2+ 和 Python 3。运行目标为 macOS 13+；Liquid Glass 使用可用性判断，旧系统回退到 NSVisualEffectView。

- `Sources/EncoBar/main.swift`：菜单栏入口、定时同步与应用生命周期。
- `Sources/EncoBar/UI/`：面板、SwiftUI 视图和卸载入口。
- `Sources/EncoBar/Model/`：查询、超时、模式确认、连接及用户状态。
- `Sources/EncoBar/Bluetooth/`：已配对设备选择、SDP 和厂商 RFCOMM 通道。
- `Sources/EncoBar/Diagnostics/`、`tools/Probe/`：显式启用的本地诊断。
- `Sources/EncoCore/`：可复用的协议和状态规则。
- `Sources/EncoUninstaller/`：独立原生卸载应用。

## 常用命令

```sh
bash scripts/test.sh
bash scripts/build.sh
open dist/app/EncoBar.app
bash scripts/package.sh
bash scripts/release.sh
```

`test.sh` 运行 Swift 核心检查、真实 EarbudModel 的传输替身测试，以及 Python 发布工具测试，不操作真实耳机。使用独立检查程序是为了兼容仅有 Command Line Tools 的开发环境，不依赖 XCTest。

构建缓存位于 `.build/`，App 位于 `dist/app/`，PKG 位于 `dist/packages/`，完整发布文件位于 `dist/releases/v版本号/`。这些目录均由 Git 忽略。

图标源程序位于 `tools/IconGenerator/`，运行 `bash scripts/generate-icon.sh` 重新生成。`bash scripts/build-probe.sh` 仅构建开发探针，不会运行或连接耳机。

## 本地诊断

```sh
open dist/app/EncoBar.app --args --log-file /tmp/encobar-diagnostic.log
```

正常运行不写日志。诊断日志仅保存在明确指定的本地文件，分享前必须检查设备标识与个人信息。不要把原始日志提交进仓库。

`--exercise` 会切换通透、降噪、关闭并在成功后恢复原模式，属于显式硬件验证。其他探针写入选项仅供协议调试，不应作为日常启动参数。请先退出其他 EncoBar 实例，且只对自己的耳机进行验证。

## 版本与签名

只修改 `Resources/Info.plist` 的产品版本及构建号，构建脚本会同步内嵌卸载器的版本。当前是 ad-hoc 签名，重新编译后系统可能再次要求蓝牙授权。

公开分发前应另行配置 Developer ID Application / Installer 签名和 Apple 公证；当前工作流没有证书或公证配置，不会把本地签名描述为受信任的发行签名。

# EncoBar

EncoBar 是一款 macOS 菜单栏小工具，用来查看 OPPO Enco Air4 Pro 的电量，并切换降噪、通透和关闭模式。

## 安装

1. 打开 [Releases 下载页](https://github.com/ruoshui6662/encoair4pro-bar/releases/latest)。
2. 下载 `EncoBar-0.3.2-macos-arm64.pkg`，双击后按提示安装。
3. 在 Mac 的“系统设置 → 蓝牙”中连接耳机，然后打开“应用程序”里的 EncoBar。
4. 首次打开时，允许 EncoBar 使用蓝牙。

需要 Apple 芯片的 Mac 和 macOS 13 或更新版本。安装包尚未经过 Apple 公证，macOS 可能提示无法验证开发者。

## 使用

点击菜单栏里的耳机图标，即可查看左右耳和耳机仓电量，并点击“降噪”“通透”或“关闭”切换模式。耳机未连接时会显示“未连接”。耳机仓电量通常要把双耳放回盒内并打开盒盖后才能读取；合盖后可能显示上次读数。

## 删除

点击面板右上角“…”→“卸载 EncoBar…”，再确认卸载。卸载工具会删除 EncoBar 自己保存的数据和蓝牙授权，并将应用移到废纸篓。

## 支持的耳机

目前仅在 **OPPO Enco Air4 Pro**（产品 ID `067C10`）上完成适配和实机验证。其他型号暂不支持。

后续二次开发可尝试使用 HeyMelody 蓝牙控制协议的 OPPO Enco、OnePlus Buds 或 realme Buds 型号。产品名称相近不代表协议相同；每个型号都需要确认蓝牙产品 ID、命令格式和电量字段，并用实机验证后才能列为支持。

## 开发与许可

本项目采用 [MIT 许可证](LICENSE)，允许使用和修改并保留署名。构建说明见[开发文档](docs/development.md)。本项目为独立社区工具，与 OPPO、OnePlus、realme 或 HeyMelody 无隶属关系。

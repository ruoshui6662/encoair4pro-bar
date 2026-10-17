# 说明与参考

EncoBar 使用系统的 AppKit、SwiftUI、IOBluetooth、CoreBluetooth 和 CryptoKit，不包含第三方运行库、耳机固件或官方应用。

协议字段与机型差异参考了以下公开资料，并以 Air4 Pro 本机回读验证当前实现：

- [OppoPods 协议笔记](https://github.com/Leaf-lsgtky/OppoPods/blob/master/docs/HeyMelody_Bluetooth_Protocol_Notes.md)与[型号表](https://github.com/Leaf-lsgtky/OppoPods/blob/master/app/src/main/assets/device_models.json)。
- [QuickBuds 协议记录](https://github.com/spizganed/QuickBuds/blob/main/docs/PROTOCOL.md)。
- [cracked-oneplus-buds](https://github.com/AasheeshLikePanner/cracked-oneplus-buds)与 [open-oneplus-buds](https://github.com/vedanth-jadhav/open-oneplus-buds)提供的 macOS 实现思路。
- [Apple IOBluetooth 文档](https://developer.apple.com/documentation/iobluetooth)。

这些链接用于注明资料来源，不表示代码被纳入本仓库，也不改变上游项目自己的许可证。以后引入第三方代码时，需分别保留其许可证并检查兼容性。

OPPO、OnePlus、HeyMelody 及相关产品名称和商标归各自权利人所有。

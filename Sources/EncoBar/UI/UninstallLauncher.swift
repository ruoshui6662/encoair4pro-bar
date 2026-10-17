import AppKit

enum UninstallLauncher {
    static func open() {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/EncoBar Uninstaller.app")
        if !NSWorkspace.shared.open(helper) {
            let alert = NSAlert()
            alert.messageText = "无法打开卸载工具"
            alert.informativeText = "卸载组件缺失或无法运行，请重新安装后重试。"
            alert.runModal()
        }
    }
}

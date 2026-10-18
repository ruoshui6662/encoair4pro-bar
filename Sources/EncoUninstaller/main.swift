import AppKit
import EncoCore

func runTool(_ path: String, _ arguments: [String]) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 0 }
    catch { return false }
}

let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
guard let application = UninstallLayout.application(containingHelper: executable),
      Bundle(url: application)?.bundleIdentifier == UninstallLayout.bundleID else {
    fputs("卸载工具必须从 EncoBar.app 内运行。\n", stderr)
    exit(1)
}
let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
let data = UninstallLayout.dataLocations(home: home)
if CommandLine.arguments.contains("--migrate-legacy-install") {
    guard application.path == "/Applications/EncoBar.app", getuid() != 0 else { exit(1) }
    if let legacy = UninstallLayout.legacyApplication(home: home) {
        do {
            try FileManager.default.trashItem(at: legacy, resultingItemURL: nil)
            // rmdir is atomic and refuses a directory containing any other app.
            _ = runTool("/bin/rmdir", [legacy.deletingLastPathComponent().path])
        } catch {
            fputs("旧版 EncoBar 未能移至废纸篓：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    if runTool("/usr/sbin/pkgutil", ["--volume", home.path, "--pkg-info", UninstallLayout.packageID]),
       !runTool("/usr/sbin/pkgutil", ["--volume", home.path, "--forget", UninstallLayout.packageID]) {
        fputs("旧版个人安装收据未能移除。\n", stderr)
        exit(1)
    }
    exit(0)
}
if CommandLine.arguments.contains("--list") {
    let output = ["application": application.path, "data": data.map(\.path), "receipt": UninstallLayout.packageID] as [String: Any]
    let encoded = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.applicationIconImage = NSImage(contentsOf: application.appendingPathComponent("Contents/Resources/AppIcon.icns"))
app.finishLaunching()
app.activate(ignoringOtherApps: true)
let confirm = NSAlert()
confirm.messageText = "卸载 EncoBar？"
let systemInstallation = application.path == "/Applications/EncoBar.app"
confirm.informativeText = "将退出 EncoBar，把应用及本用户的电量记录、缓存和保存状态移至废纸篓，并撤销它的蓝牙授权和安装收据。\n\n" + (systemInstallation ? "移除系统应用和收据需要管理员授权，其他用户将无法再运行此应用。其他用户的数据会保留。" : "不会搜索或清理源码、其他应用以及其他用户的文件。")
confirm.addButton(withTitle: "取消")
confirm.addButton(withTitle: "卸载")
guard confirm.runModal() == .alertSecondButtonReturn else { exit(0) }

var failures: [String] = []
let processes = NSRunningApplication.runningApplications(withBundleIdentifier: UninstallLayout.bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
processes.forEach { _ = $0.terminate() }
let deadline = Date().addingTimeInterval(4)
while processes.contains(where: { !$0.isTerminated }), Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
processes.filter { !$0.isTerminated }.forEach { _ = $0.forceTerminate() }
let forceDeadline = Date().addingTimeInterval(2)
while processes.contains(where: { !$0.isTerminated }), Date() < forceDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
if processes.contains(where: { !$0.isTerminated }) {
    let error = NSAlert()
    error.messageText = "EncoBar 尚未退出"
    error.informativeText = "请先在活动监视器中退出 EncoBar，再重新卸载。尚未清理文件。"
    error.runModal()
    exit(1)
}

// Request elevation before clearing any user data; cancelling leaves those files intact.
if systemInstallation {
    do {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        guard let command = UninstallLayout.systemRemovalCommand(application: application, home: home, token: UUID()) else { exit(1) }
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        var scriptError: NSDictionary?
        let script = NSAppleScript(source: "do shell script \"\(literal)\" with administrator privileges")
        _ = script?.executeAndReturnError(&scriptError)
        if script == nil || scriptError != nil || FileManager.default.fileExists(atPath: application.path) {
            if scriptError?[NSAppleScript.errorNumber] as? Int == -128 { exit(0) }
            let alert = NSAlert()
            alert.messageText = "系统应用未能完整移除"
            alert.informativeText = "\(scriptError?[NSAppleScript.errorMessage] ?? "请重新尝试卸载。")\n\n个人电量记录及偏好尚未清理。应用可能已在废纸篓中。"
            alert.runModal()
            exit(1)
        }
    } catch {
        let alert = NSAlert()
        alert.messageText = "无法访问废纸篓"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        exit(1)
    }
}

// Move exact owned paths, never match names across the user's filesystem.
for item in data where FileManager.default.fileExists(atPath: item.path) {
    do { try FileManager.default.trashItem(at: item, resultingItemURL: nil) }
    catch { failures.append("\(item.path)：\(error.localizedDescription)") }
}
// Flush cfprefsd's cached domain after the backup has been moved to Trash.
UserDefaults.standard.removePersistentDomain(forName: UninstallLayout.bundleID)
UserDefaults.standard.synchronize()
CFPreferencesAppSynchronize(UninstallLayout.bundleID as CFString)
// cfprefsd can persist an empty 42-byte plist while clearing the domain.
// Dispose of that final file after the daemon has flushed its cache.
let preferences = home.appendingPathComponent("Library/Preferences/\(UninstallLayout.bundleID).plist")
if FileManager.default.fileExists(atPath: preferences.path) {
    do { try FileManager.default.trashItem(at: preferences, resultingItemURL: nil) }
    catch { failures.append("空偏好文件：\(error.localizedDescription)") }
}
if !runTool("/usr/bin/tccutil", ["reset", "BluetoothAlways", UninstallLayout.bundleID]) {
    failures.append("蓝牙授权未能自动撤销；可在系统设置的蓝牙隐私列表中管理。")
}
if runTool("/usr/sbin/pkgutil", ["--volume", home.path, "--pkg-info", UninstallLayout.packageID]),
   !runTool("/usr/sbin/pkgutil", ["--volume", home.path, "--forget", UninstallLayout.packageID]) {
    failures.append("安装收据未能自动移除。")
}
if !systemInstallation {
    do { try FileManager.default.trashItem(at: application, resultingItemURL: nil) }
    catch { failures.append("应用：\(error.localizedDescription)") }
}

let result = NSAlert()
result.messageText = failures.isEmpty ? "EncoBar 已卸载" : "卸载未全部完成"
result.informativeText = failures.isEmpty
    ? "应用及已有数据已移至废纸篓。macOS 自身的安装历史和系统日志由系统管理。"
    : failures.joined(separator: "\n\n")
result.runModal()
exit(failures.isEmpty ? 0 : 1)

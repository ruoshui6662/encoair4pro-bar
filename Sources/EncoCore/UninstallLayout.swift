import Foundation

public enum UninstallLayout {
    public static let bundleID = "local.encobar.air4pro"
    public static let packageID = "local.encobar.air4pro.installer"

    // Upgrade only the exact legacy user installation, never a symlink or a source checkout.
    public static func legacyApplication(home: URL) -> URL? {
        let folder = home.appendingPathComponent("Applications")
        let application = folder.appendingPathComponent("EncoBar.app")
        for item in [folder, application] {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
        }
        guard let data = try? Data(contentsOf: application.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID else { return nil }
        return application
    }

    public static func shellLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    // Elevation is limited to our fixed system bundle and its system receipt.
    public static func systemRemovalCommand(application: URL, home: URL, token: UUID) -> String? {
        guard application.path == "/Applications/EncoBar.app", home.isFileURL, home.path != "/" else { return nil }
        let trash = home.appendingPathComponent(".Trash")
        let destination = trash.appendingPathComponent("EncoBar-\(token.uuidString).app")
        let source = shellLiteral(application.path)
        let target = shellLiteral(destination.path)
        let trashPath = shellLiteral(trash.path)
        return """
        set -eu
        test ! -L \(source)
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \(shellLiteral(application.appendingPathComponent("Contents/Info.plist").path)))" = \(shellLiteral(bundleID))
        test -d \(trashPath)
        test ! -L \(trashPath)
        test ! -e \(target)
        test ! -L \(target)
        /bin/mv -n \(source) \(target)
        test ! -e \(source)
        if /usr/sbin/pkgutil --pkg-info \(shellLiteral(packageID)) >/dev/null 2>&1; then
            /usr/sbin/pkgutil --forget \(shellLiteral(packageID)) >/dev/null
        fi
        """
    }

    public static func application(containingHelper helper: URL) -> URL? {
        let path = helper.standardizedFileURL
        let suffix = ["EncoBar.app", "Contents", "Helpers", "EncoBar Uninstaller.app", "Contents", "MacOS", "EncoBarUninstaller"]
        guard Array(path.pathComponents.suffix(7)) == suffix else { return nil }
        let app = (0..<6).reduce(path) { result, _ in result.deletingLastPathComponent() }
        return app.lastPathComponent == "EncoBar.app" ? app : nil
    }

    public static func dataLocations(home: URL) -> [URL] {
        ["Preferences/\(bundleID).plist", "Caches/\(bundleID)",
         "Application Support/\(bundleID)", "Saved Application State/\(bundleID).savedState",
         "Preferences/\(bundleID).uninstaller.plist", "Caches/\(bundleID).uninstaller",
         "Saved Application State/\(bundleID).uninstaller.savedState"]
            .map { home.appendingPathComponent("Library/" + $0) }
    }
}

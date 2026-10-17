import Foundation

public enum UninstallLayout {
    public static let bundleID = "local.encobar.air4pro"
    public static let packageID = "local.encobar.air4pro.installer"

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

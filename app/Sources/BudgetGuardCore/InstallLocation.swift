import Foundation

/// Where the app may run from: Sparkle and the login item need a stable path (not a disk image, not App Translocation).
public enum InstallLocation {
    public static func isAcceptable(bundlePath: String, homeDirectory: String) -> Bool {
        if bundlePath.contains("/AppTranslocation/") { return false }
        if bundlePath.hasPrefix("/Applications/") { return true }
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return bundlePath.hasPrefix(home + "/Applications/")
    }
}

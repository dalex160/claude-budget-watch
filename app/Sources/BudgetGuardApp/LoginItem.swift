import Foundation
import ServiceManagement

/// « Lancer au démarrage du Mac ». SMAppService.mainApp only works for a bundled app:
/// unbundled (`swift run`) it reports off and ignores changes.
enum LoginItem {
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        guard isBundled else { return }
        let service = SMAppService.mainApp
        if on {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}

import AppKit
import Sparkle

/// Sparkle wrapper. The updater only starts when the bundle carries a public EdDSA key
/// (`SUPublicEDKey`); without it (dev builds, `swift run`) the menu entry explains why instead.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if let key, !key.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    /// Call at launch so automatic checks start.
    func start() { _ = controller }

    func checkForUpdates() {
        if let controller {
            controller.checkForUpdates(nil)
        } else {
            let alert = NSAlert()
            alert.messageText = "Les mises à jour automatiques ne sont pas encore configurées."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

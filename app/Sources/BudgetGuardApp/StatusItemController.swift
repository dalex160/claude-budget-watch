import AppKit
import BudgetGuardCore

/// Owns the menu bar item: icon + coloured value, and the menu built from a `MenuDisplay`.
@MainActor
final class StatusItemController: NSObject {
    var onReconnect: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onUseClaudeCode: (() -> Void)?
    var onEnableAlerts: (() -> Void)?
    var notificationsAuthorized = false

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var last: MenuDisplay?

    override init() {
        super.init()
        item.button?.image = Self.icon()
        item.button?.imagePosition = .imageLeading
    }

    func render(_ display: MenuDisplay) {
        last = display
        item.button?.attributedTitle = NSAttributedString(
            string: " " + display.title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ].merging(Self.color(display.tone).map { [NSAttributedString.Key.foregroundColor: $0] } ?? [:]) { $1 }
        )
        item.menu = makeMenu(display)
    }

    /// Re-render after a state change that is not a new usage value (e.g. notification authorization).
    func refreshMenu() { if let last { render(last) } }

    // MARK: - Menu

    private func makeMenu(_ d: MenuDisplay) -> NSMenu {
        let menu = NSMenu()
        for line in d.lines {
            let i = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(action("Actualiser maintenant", #selector(refresh)))
        if d.showsReconnect {
            menu.addItem(action("Se reconnecter à Claude…", #selector(reconnect)))
            if ClaudeCodeSource.isAvailable() {
                menu.addItem(action("Utiliser ma connexion Claude Code", #selector(useClaudeCode)))
            }
        }
        if !notificationsAuthorized {
            menu.addItem(action("Activer les alertes", #selector(enableAlerts)))
        }
        let launch = action("Lancer au démarrage du Mac", #selector(toggleLaunchAtLogin))
        launch.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(action("Rechercher des mises à jour…", #selector(checkForUpdates)))
        menu.addItem(NSMenuItem(title: "Quitter Budget Guard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func refresh() { onRefresh?() }
    @objc private func reconnect() { onReconnect?() }
    @objc private func toggleLaunchAtLogin() {
        try? LoginItem.setEnabled(!LoginItem.isEnabled)
        refreshMenu()
    }
    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }
    @objc private func enableAlerts() { onEnableAlerts?() }

    @objc private func useClaudeCode() {
        let alert = NSAlert()
        alert.messageText = "macOS va vous demander l’autorisation de lire votre connexion Claude Code. Cliquez sur « Toujours autoriser »."
        alert.addButton(withTitle: "Continuer")
        alert.addButton(withTitle: "Annuler")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { onUseClaudeCode?() }
    }

    // MARK: - Look

    static func color(_ tone: DisplayTone) -> NSColor? {
        switch tone {
        case .neutral: return nil
        case .normal: return NSColor(srgbRed: 0x7F / 255, green: 0xD9 / 255, blue: 0x9A / 255, alpha: 1)
        case .warning: return NSColor(srgbRed: 0xFF / 255, green: 0xB8 / 255, blue: 0x66 / 255, alpha: 1)
        case .critical: return NSColor(srgbRed: 0xFF / 255, green: 0x80 / 255, blue: 0x80 / 255, alpha: 1)
        case .stale: return NSColor(srgbRed: 0x9A / 255, green: 0x9A / 255, blue: 0x9A / 255, alpha: 1)
        }
    }

    /// Template glyph drawn by scripts/make-menubar-icon.swift. Bundled app: Resources; `swift run`: the source tree.
    static func icon() -> NSImage {
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/MenuBarIcon.pdf")
        let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf") ?? dev
        let image = NSImage(contentsOf: url) ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}

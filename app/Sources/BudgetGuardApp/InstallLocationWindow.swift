import AppKit

/// Shown instead of the assistant when the app runs from a disk image or a translocated path.
@MainActor
final class InstallLocationWindow: NSObject {
    private var window: NSWindow?

    func show() {
        let title = NSTextField(labelWithString: "Encore une petite étape")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: "Pour que Budget Guard fonctionne correctement, glissez-le dans le dossier Applications, puis ouvrez-le depuis là.")
        text.font = .systemFont(ofSize: 14)
        text.preferredMaxLayoutWidth = 380
        let open = NSButton(title: "Ouvrir le dossier Applications", target: self, action: #selector(openApplications))
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"
        let quit = NSButton(title: "Quitter", target: self, action: #selector(quit))
        quit.bezelStyle = .rounded
        let buttons = NSStackView(views: [quit, open])
        buttons.spacing = 12

        let stack = NSStackView(views: [title, text, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)

        let w = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Budget Guard"
        w.isReleasedWhenClosed = false
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc private func openApplications() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

import AppKit
import WebKit

/// `--login-test [--snapshot <path>]` opens the login view in a window; `--logout` clears the default store.
@MainActor
enum LoginTest {
    private static var login: LoginWebView?
    private static var window: NSWindow?

    static func run(snapshotPath: String?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let l = LoginWebView()
        l.onLoggedIn = { print("logged in"); exit(0) }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Budget Guard — connexion"
        w.contentView = l.view
        w.center()
        w.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        l.start()
        login = l
        window = w

        if let path = snapshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                guard let content = w.contentView else { exit(1) }
                let web = content.subviews.compactMap { $0 as? WKWebView }.first
                snapshot(content: content, web: web, path: path)
            }
        }
        app.run()
        exit(0)
    }

    private static func snapshot(content: NSView, web: WKWebView?, path: String) {
        // Compose banner (AppKit) and page (takeSnapshot) into one image.
        let size = content.bounds.size
        let image = NSImage(size: size)
        guard let bannerRep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
        content.cacheDisplay(in: content.bounds, to: bannerRep)
        image.addRepresentation(bannerRep)
        func save(_ img: NSImage) {
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: path)); print("snapshot saved"); exit(0) } catch { exit(1) }
        }
        guard let web else { save(image); return }
        web.takeSnapshot(with: nil) { snap, _ in
            let out = NSImage(size: size)
            out.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: size))
            if let snap { snap.draw(in: web.convert(web.bounds, to: content)) }
            out.unlockFocus()
            save(out)
        }
    }

    static func logout() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var done = false
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { done = true }
        let deadline = Date().addingTimeInterval(15)
        while !done && Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
        print(done ? "logged out" : "error: timeout")
        exit(done ? 0 : 1)
    }
}

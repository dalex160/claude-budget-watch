import AppKit
import WebKit
import BudgetGuardCore

/// `--onboarding-preview <welcome|login|check|settings|done> [--percent N] [--state ok|reading|unsupported|failed] --snapshot <path>`
/// renders one assistant step to a PNG and exits. Never logs in and never asks macOS for anything.
@MainActor
enum OnboardingPreview {
    private static var controller: OnboardingWindowController?

    static func run(stepName: String, args: [String]) -> Never {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        let steps: [String: OnboardingStep] = ["welcome": .welcome, "login": .login, "check": .check, "settings": .settings, "done": .done]
        guard let step = steps[stepName], let path = value("--snapshot") else {
            print("usage: --onboarding-preview <welcome|login|check|settings|done> [--percent N] [--state ok|reading|unsupported|failed] --snapshot <path>")
            exit(2)
        }
        let percent = value("--percent").flatMap(Int.init) ?? 29
        let state: CheckState
        switch value("--state") ?? "ok" {
        case "reading": state = .reading
        case "unsupported": state = .unsupportedPlan
        case "failed": state = .failed
        default: state = .success(fakeSnapshot(percent: percent))
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let c = OnboardingWindowController(notifier: Notifier())
        controller = c
        let w = c.previewWindow(step: step, check: state)
        w.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        // The login step needs time to load the real claude.ai page.
        let delay: Double = step == .login ? 8 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let content = w.contentView else { exit(1) }
            capture(content: content, path: path)
        }
        app.run()
        exit(0)
    }

    private static func fakeSnapshot(percent: Int) -> UsageSnapshot {
        let cal = Calendar.current
        let now = Date()
        let reset = cal.nextDate(after: now, matching: DateComponents(hour: 14, minute: 0, weekday: 7), matchingPolicy: .nextTime)
        return UsageSnapshot(weeklyPercent: percent, resetsAt: reset, extraUsage: nil, fetchedAt: now)
    }

    private static func findWebView(in view: NSView) -> WKWebView? {
        if let w = view as? WKWebView { return w }
        for s in view.subviews { if let w = findWebView(in: s) { return w } }
        return nil
    }

    private static func capture(content: NSView, path: String) {
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
        content.cacheDisplay(in: content.bounds, to: rep)
        let base = NSImage(size: content.bounds.size)
        base.addRepresentation(rep)
        func save(_ img: NSImage) {
            guard let tiff = img.tiffRepresentation, let r = NSBitmapImageRep(data: tiff),
                  let png = r.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: path)); print("snapshot saved"); exit(0) } catch { exit(1) }
        }
        // WKWebView does not render through cacheDisplay: overlay its own snapshot.
        guard let web = findWebView(in: content) else { save(base); return }
        web.takeSnapshot(with: nil) { snap, _ in
            let out = NSImage(size: content.bounds.size)
            out.lockFocus()
            base.draw(in: NSRect(origin: .zero, size: content.bounds.size))
            if let snap {
                var r = web.convert(web.bounds, to: content)
                if content.isFlipped { r.origin.y = content.bounds.height - r.maxY }
                snap.draw(in: r)
            }
            out.unlockFocus()
            save(out)
        }
    }
}

import AppKit
import BudgetGuardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = StatusItemController()
    private let notifier = Notifier()
    private let alerts = AlertTracker(store: UserDefaultsAlertStateStore(defaults: .standard))
    private lazy var webSource = WebSessionSource()
    private lazy var claudeCodeSource = ClaudeCodeSource()
    private lazy var loop = RefreshLoop(sourceProvider: { [unowned self] () -> UsageSource in
        if SourceKind.current == .claudeCode { return self.claudeCodeSource }
        return self.webSource
    })
    private var loginWindow: NSWindow?
    private var login: LoginWebView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        render(snapshot: nil, error: nil)
        statusItem.onRefresh = { [weak self] in self?.loop.refreshNow() }
        statusItem.onReconnect = { [weak self] in self?.showLogin() }
        statusItem.onUseClaudeCode = { [weak self] in self?.switchSource(.claudeCode) }
        statusItem.onEnableAlerts = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                _ = await self.notifier.requestAuthorization()
                await self.updateAuthorization()
            }
        }
        loop.onUpdate = { [weak self] snapshot, error in self?.handle(snapshot, error) }
        Task { @MainActor in
            await updateAuthorization()
            loop.start()
        }
    }

    private func handle(_ snapshot: UsageSnapshot?, _ error: UsageFetchError?) {
        render(snapshot: snapshot, error: error)
        guard let percent = alertPercent(snapshot: snapshot, error: error) else { return }
        for threshold in alerts.thresholdsToAlert(for: percent) {
            notifier.post(threshold: threshold, percent: percent)
        }
    }

    private func render(snapshot: UsageSnapshot?, error: UsageFetchError?) {
        statusItem.render(makeMenuDisplay(snapshot: snapshot, error: error, now: Date(), calendar: .current))
    }

    private func updateAuthorization() async {
        statusItem.notificationsAuthorized = await notifier.isAuthorized()
        statusItem.refreshMenu()
    }

    private func switchSource(_ kind: SourceKind) {
        SourceKind.current = kind
        loop.resetSnapshot()
        render(snapshot: nil, error: nil)
        loop.refreshNow()
    }

    // Task 7 routes this to the onboarding.
    private func showLogin() {
        if let w = loginWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let l = LoginWebView()
        l.onLoggedIn = { [weak self] in self?.loginDone() }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Se connecter à Claude"
        w.isReleasedWhenClosed = false
        w.contentView = l.view
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        l.start()
        login = l
        loginWindow = w
    }

    private func loginDone() {
        // Hide on the next turn: closing synchronously from the web view callback crashed in the spike.
        DispatchQueue.main.async { [weak self] in
            self?.loginWindow?.orderOut(nil)
            self?.loginWindow = nil
            self?.login = nil
        }
        switchSource(.web)
    }
}

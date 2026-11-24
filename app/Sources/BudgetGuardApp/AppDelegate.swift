import AppKit
import BudgetGuardCore
import UserNotifications

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
    private lazy var onboarding = OnboardingWindowController(notifier: notifier)

    private let installWindow = InstallLocationWindow()

    /// Bundled but not in /Applications (disk image, translocation): Sparkle and the login item would break.
    private var runsFromBadLocation: Bool {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        return !InstallLocation.isAcceptable(bundlePath: Bundle.main.bundlePath, homeDirectory: NSHomeDirectory())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        if runsFromBadLocation {
            installWindow.show()
            return
        }
        Updater.shared.start()
        render(snapshot: nil, error: nil)
        statusItem.onRefresh = { [weak self] in self?.loop.refreshNow() }
        statusItem.onReconnect = { [weak self] in self?.showOnboarding(startAt: .login) }
        statusItem.onUseClaudeCode = { [weak self] in self?.switchSource(.claudeCode) }
        statusItem.onEnableAlerts = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if await self.notifier.authorizationStatus() == .denied {
                    self.openNotificationSettings()
                } else {
                    _ = await self.notifier.requestAuthorization()
                }
                await self.updateAuthorization()
            }
        }
        if !UserDefaults.standard.bool(forKey: OnboardingWindowController.completedKey) {
            showOnboarding(startAt: .welcome)
        }
        onboarding.onLoggedIn = { [weak self] in self?.switchSource(.web) }
        loop.onUpdate = { [weak self] snapshot, error in self?.handle(snapshot, error) }
        Task { @MainActor in
            await updateAuthorization()
            loop.start()
        }
    }

    private func handle(_ snapshot: UsageSnapshot?, _ error: UsageFetchError?) {
        render(snapshot: snapshot, error: error)
        Task { @MainActor in
            // Re-read the permission each time: it may have been granted in System Settings since the last refresh.
            await updateAuthorization()
            // Consult the tracker only when a notification can actually be shown, otherwise the crossing
            // would be marked as announced and never delivered after « Activer les alertes ».
            guard statusItem.notificationsAuthorized,
                  let percent = alertPercent(snapshot: snapshot, error: error) else { return }
            for threshold in alerts.thresholdsToAlert(for: percent) {
                notifier.post(threshold: threshold, percent: percent)
            }
        }
    }

    /// Permission was refused earlier: macOS will not ask again, so point to System Settings.
    private func openNotificationSettings() {
        let alert = NSAlert()
        alert.messageText = "Autorisez les notifications de Budget Guard dans Réglages Système, puis revenez ici."
        alert.addButton(withTitle: "Ouvrir Réglages Système")
        alert.addButton(withTitle: "Annuler")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func render(snapshot: UsageSnapshot?, error: UsageFetchError?) {
        statusItem.render(makeMenuDisplay(snapshot: snapshot, error: error, now: Date(), calendar: .current))
    }

    private func updateAuthorization() async {
        let authorized = await notifier.isAuthorized()
        guard authorized != statusItem.notificationsAuthorized else { return }
        statusItem.notificationsAuthorized = authorized
        statusItem.refreshMenu()
    }

    private func showOnboarding(startAt step: OnboardingStep) {
        onboarding.show(startAt: step) { [weak self] in
            guard let self else { return }
            // The assistant may have changed the notification permission or logged in.
            Task { @MainActor in await self.updateAuthorization() }
        }
    }

    private func switchSource(_ kind: SourceKind) {
        SourceKind.current = kind
        loop.resetSnapshot()
        render(snapshot: nil, error: nil)
        loop.refreshNow()
    }
}

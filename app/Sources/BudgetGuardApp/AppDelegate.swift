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
    private lazy var onboarding = OnboardingWindowController(notifier: notifier)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.start()
        render(snapshot: nil, error: nil)
        statusItem.onRefresh = { [weak self] in self?.loop.refreshNow() }
        statusItem.onReconnect = { [weak self] in self?.showOnboarding(startAt: .login) }
        statusItem.onUseClaudeCode = { [weak self] in self?.switchSource(.claudeCode) }
        statusItem.onEnableAlerts = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                _ = await self.notifier.requestAuthorization()
                await self.updateAuthorization()
            }
        }
        if !UserDefaults.standard.bool(forKey: OnboardingWindowController.completedKey) {
            showOnboarding(startAt: .welcome)
        }
        loop.onUpdate = { [weak self] snapshot, error in self?.handle(snapshot, error) }
        Task { @MainActor in
            await updateAuthorization()
            loop.start()
        }
    }

    private func handle(_ snapshot: UsageSnapshot?, _ error: UsageFetchError?) {
        render(snapshot: snapshot, error: error)
        // Consult the tracker only when a notification can actually be shown, otherwise the crossing
        // would be marked as announced and never delivered after « Activer les alertes ».
        guard statusItem.notificationsAuthorized,
              let percent = alertPercent(snapshot: snapshot, error: error) else { return }
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

    private func showOnboarding(startAt step: OnboardingStep) {
        onboarding.show(startAt: step) { [weak self] in
            guard let self else { return }
            // The assistant may have changed the notification permission or logged in.
            Task { @MainActor in await self.updateAuthorization() }
            if self.onboarding.didLogIn { self.switchSource(.web) }
        }
    }

    private func switchSource(_ kind: SourceKind) {
        SourceKind.current = kind
        loop.resetSnapshot()
        render(snapshot: nil, error: nil)
        loop.refreshNow()
    }
}

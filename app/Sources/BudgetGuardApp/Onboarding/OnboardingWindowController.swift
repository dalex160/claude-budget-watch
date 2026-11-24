import AppKit
import SwiftUI
import BudgetGuardCore

/// First-launch assistant (and « Se reconnecter à Claude… » when opened at `.login`).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let completedKey = "onboarding.completed"

    /// True once the user got through the login step during the last `show`.
    private(set) var didLogIn = false

    private let notifier: Notifier
    private let model = OnboardingModel()
    private var window: NSWindow?
    private var login: LoginWebView?
    private var checkTask: Task<Void, Never>?
    private var completion: (() -> Void)?
    private var reconnect = false
    private var finished = true
    private var previousPolicy: NSApplication.ActivationPolicy?

    init(notifier: Notifier) {
        self.notifier = notifier
        super.init()
    }

    func show(startAt step: OnboardingStep = .welcome, completion: @escaping () -> Void) {
        if let window, !finished {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.completion = completion
        finished = false
        didLogIn = false
        reconnect = step == .login
        // An accessory app's window stays behind other apps; become a regular app while the assistant is open.
        previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let w = makeWindow()
        window = w
        enter(step)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Debug preview: builds the window at `step` without running any fetch or system request.
    func previewWindow(step: OnboardingStep, check: CheckState) -> NSWindow {
        let w = makeWindow()
        window = w
        model.check = check
        if step == .login { startLogin() }
        model.step = step
        return w
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let l = LoginWebView()
        l.onLoggedIn = { [weak self] in
            // Leave the web view's callback before changing the hierarchy that hosts it.
            DispatchQueue.main.async { self?.didLogIn = true; self?.handle(.loggedIn) }
        }
        login = l
        model.loginView = l.view
        model.step = .welcome
        model.check = .reading
        model.launchAtLogin = true
        model.alertsEnabled = true
        model.applying = false
        model.onStart = { [weak self] in self?.handle(.start) }
        model.onContinue = { [weak self] in self?.handle(.continueTapped) }
        model.onBackToLogin = { [weak self] in self?.handle(.backToLogin) }
        model.onRetry = { [weak self] in self?.runCheck() }
        model.onQuit = { NSApp.terminate(nil) }

        let host = NSHostingView(rootView: OnboardingView(model: model))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Budget Guard"
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.setContentSize(NSSize(width: 560, height: 760))
        w.delegate = self
        w.center()
        return w
    }

    func windowWillClose(_ notification: Notification) {
        // Closed with the X: counts as completed only from the last step (see OnboardingFlow).
        handle(.windowClosed)
    }

    // MARK: - Steps

    private func handle(_ event: OnboardingEvent) {
        guard !finished else { return }
        // Settings applies the choices first, then moves on.
        if model.step == .settings, event == .continueTapped {
            applySettings()
            return
        }
        switch OnboardingFlow.next(from: model.step, event: event, reconnect: reconnect) {
        case .stay: break
        case .go(let step): enter(step)
        case .close:
            if OnboardingFlow.marksCompleted(closingFrom: model.step) {
                UserDefaults.standard.set(true, forKey: Self.completedKey)
            }
            finish()
        }
    }

    private func enter(_ step: OnboardingStep) {
        checkTask?.cancel()
        model.step = step
        switch step {
        case .login: startLogin()
        case .check: runCheck()
        default: break
        }
    }

    private func startLogin() { login?.start() }

    private func runCheck() {
        checkTask?.cancel()
        model.check = .reading
        let source = WebSessionSource()
        checkTask = Task { @MainActor [weak self] in
            let result: CheckState
            do {
                result = .success(try await source.fetchSnapshot())
            } catch UsageFetchError.unsupportedPlan {
                result = .unsupportedPlan
            } catch {
                result = .failed
            }
            guard let self, !Task.isCancelled, self.model.step == .check else { return }
            self.model.check = result
            if case .success = result { self.handle(.checkSucceeded) }
        }
    }

    private func applySettings() {
        model.applying = true
        let wantsLogin = model.launchAtLogin
        let wantsAlerts = model.alertsEnabled
        Task { @MainActor [weak self] in
            try? LoginItem.setEnabled(wantsLogin)
            if wantsAlerts { _ = await self?.notifier.requestAuthorization() }
            guard let self, !self.finished else { return }
            self.model.applying = false
            self.enter(.done)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        checkTask?.cancel()
        let done = completion
        completion = nil
        // Hide on the next turn: closing synchronously from a web view callback crashed in the spike.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.orderOut(nil)
            self.window = nil
            self.login = nil
            self.model.loginView = nil
            if let p = self.previousPolicy { NSApp.setActivationPolicy(p) }
            self.previousPolicy = nil
            done?()
        }
    }
}

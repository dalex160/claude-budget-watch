import AppKit
import WebKit

/// Embeddable claude.ai login: a hint banner above a web view. Calls `onLoggedIn` once when a session works.
@MainActor
final class LoginWebView: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let hint = "Connectez-vous comme d’habitude. Si Google vous parle de Bluetooth, cliquez sur « Essayer une autre méthode », ou choisissez « Continuer avec l’e-mail » et entrez votre adresse : vous recevrez un code."
    private static let loginURL = URL(string: "https://claude.ai/login")!

    let view: NSView
    var onLoggedIn: (() -> Void)?

    private let webView: WKWebView
    private let source: WebSessionSource
    static let offlineMessage = "Impossible d’afficher la page de connexion. Vérifiez votre connexion Internet."
    private var offlineView: NSStackView?
    private var retryButton: NSButton?
    private var popups: [NSWindow] = []
    private var timer: Timer?
    private var checking = false
    private var finished = false

    init(dataStore: WKWebsiteDataStore? = nil) {
        let dataStore = dataStore ?? .default()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: cfg)
        source = WebSessionSource(dataStore: dataStore)

        let label = NSTextField(wrappingLabelWithString: Self.hint)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let banner = TintedBanner()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(icon)
        banner.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -12),
        ])

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let errorLabel = NSTextField(wrappingLabelWithString: Self.offlineMessage)
        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.alignment = .center
        let retry = NSButton(title: "Réessayer", target: nil, action: nil)
        retry.bezelStyle = .rounded
        let errorStack = NSStackView(views: [errorLabel, retry])
        errorStack.orientation = .vertical
        errorStack.spacing = 14
        errorStack.edgeInsets = NSEdgeInsets(top: 40, left: 32, bottom: 40, right: 32)
        errorStack.isHidden = true
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        offlineView = errorStack
        retryButton = retry

        let stack = NSStackView(views: [banner, separator, errorStack, webView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        webView.translatesAutoresizingMaskIntoConstraints = false
        banner.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        webView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        errorStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        view = stack
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        retryButton?.target = self
        retryButton?.action = #selector(retryLoad)
    }

    @objc private func retryLoad() {
        showOffline(false)
        webView.load(URLRequest(url: Self.loginURL))
    }

    private func showOffline(_ on: Bool) {
        offlineView?.isHidden = !on
        webView.isHidden = on
    }

    // MARK: - Offline

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { showOffline(false) }
    }

    private func navigationFailed(_ failed: WKWebView, _ error: Error) {
        guard failed === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        showOffline(true)
    }

    deinit { MainActor.assumeIsolated { timer?.invalidate() } }

    func start() {
        finished = false
        checking = false
        webView.load(URLRequest(url: Self.loginURL))
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    // MARK: - Login detection

    private func poll() {
        guard !finished, !checking, let url = webView.url,
              url.host == "claude.ai", !url.path.hasPrefix("/login") else { return }
        checking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.source.hasSession()
            self.checking = false
            guard ok, !self.finished else { return }
            self.finished = true
            self.timer?.invalidate()
            self.timer = nil
            self.onLoggedIn?()
        }
    }

    // MARK: - Popups (Google sign-in uses window.open + postMessage to the opener)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let pop = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        pop.uiDelegate = self
        pop.navigationDelegate = self
        let w = NSWindow(contentRect: pop.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = pop
        w.center()
        w.makeKeyAndOrderFront(nil)
        popups.append(w)
        return pop
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let w = popups.first(where: { $0.contentView === webView }) else { return }
        release(w)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, popups.contains(where: { $0 === w }) else { return }
        release(w)
    }

    /// Closing synchronously crashed in the spike: hide on the next turn, then drop the reference.
    private func release(_ w: NSWindow) {
        DispatchQueue.main.async { [weak self] in
            w.orderOut(nil)
            DispatchQueue.main.async { self?.popups.removeAll { $0 === w } }
        }
    }
}

/// Soft attention background that adapts to light/dark (resolved at draw time).
private final class TintedBanner: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        }
    }
}

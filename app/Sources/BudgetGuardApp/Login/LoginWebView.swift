import AppKit
import WebKit

/// Embeddable claude.ai login: a hint banner above a web view. Calls `onLoggedIn` once when a session works.
@MainActor
final class LoginWebView: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let hint = "Connectez-vous comme d’habitude. Si Google vous parle de Bluetooth, cliquez sur « Essayer une autre méthode », ou choisissez « Continuer avec l’e-mail » et entrez votre adresse : vous recevrez un code."
    private static let loginURL = URL(string: "https://claude.ai/login")!

    let view: NSView
    var onLoggedIn: (() -> Void)?

    private let webView: WKWebView
    private let source: WebSessionSource
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

        let banner = NSTextField(wrappingLabelWithString: Self.hint)
        banner.font = .systemFont(ofSize: 13)
        banner.textColor = .secondaryLabelColor
        banner.drawsBackground = true
        banner.backgroundColor = .controlBackgroundColor
        banner.isSelectable = false
        banner.setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = NSStackView(views: [banner, webView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        banner.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        banner.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        webView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        view = stack
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    deinit { MainActor.assumeIsolated { timer?.invalidate() } }

    func start() {
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
            let ok = (try? await self.source.fetchSnapshot()) != nil
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
        w.contentView = pop
        w.center()
        w.makeKeyAndOrderFront(nil)
        popups.append(w)
        return pop
    }

    func webViewDidClose(_ webView: WKWebView) {
        // Closing synchronously crashed in the spike: hide on the next turn, then drop the reference.
        guard let w = popups.first(where: { $0.contentView === webView }) else { return }
        DispatchQueue.main.async { [weak self] in
            w.orderOut(nil)
            DispatchQueue.main.async { self?.popups.removeAll { $0 === w } }
        }
    }
}

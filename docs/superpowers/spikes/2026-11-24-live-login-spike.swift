// Throwaway spike: a human logs into claude.ai inside a WKWebView; we then read the usage %.
// Prints only usage numbers, never cookies or account identifiers.
import AppKit
import WebKit

func log(_ s: String) { FileHandle.standardOutput.write("\(s)\n".data(using: .utf8)!) }

final class Spike: NSObject, WKNavigationDelegate, WKUIDelegate {
    let window: NSWindow
    let web: WKWebView
    var popups: [NSWindow] = []
    var done = false

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 760), configuration: cfg)
        window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Essai Budget Guard — connectez-vous à Claude"
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in self.probe() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let host = action.request.url?.host, action.targetFrame?.isMainFrame ?? true { log("nav: \(host)\(action.request.url?.path ?? "")") }
        decisionHandler(.allow)
    }

    // Real popup window (Google sign-in uses window.open + postMessage back to the opener).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        log("popup: \(action.request.url?.host ?? "?")")
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
        log("popup closed")
        // Keep the window object alive (no release on close) to avoid the crash seen in run 1.
        for w in popups where w.contentView === webView { DispatchQueue.main.async { w.orderOut(nil) } }
    }

    func probe() {
        guard !done, web.url?.host == "claude.ai", !(web.url?.path.hasPrefix("/login") ?? true) else { return }
        let js = """
        const o = await fetch('/api/organizations', {headers: {accept: 'application/json'}});
        if (!o.ok) return JSON.stringify({step: 'orgs', status: o.status});
        const orgs = await o.json();
        const org = orgs.find(x => (x.capabilities||[]).includes('chat')) || orgs[0];
        const u = await fetch('/api/organizations/' + org.uuid + '/usage', {headers: {accept: 'application/json'}});
        const body = u.ok ? await u.json() : null;
        return JSON.stringify({orgCount: orgs.length, capabilities: org.capabilities, usageStatus: u.status,
          seven_day: body && body.seven_day, five_hour: body && body.five_hour, extra_usage: body && body.extra_usage,
          keys: body ? Object.keys(body) : []});
        """
        web.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let v):
                let s = "\(v ?? "nil")"
                log("USAGE: \(s)")
                if s.contains("usageStatus\":200") {
                    self.done = true
                    self.web.evaluateJavaScript("document.body.insertAdjacentHTML('afterbegin', '<div style=\"position:fixed;z-index:99999;top:0;left:0;right:0;padding:16px;background:#1a7f37;color:#fff;font:600 16px -apple-system\">Essai réussi : pourcentage lu. Vous pouvez fermer cette fenêtre.</div>')")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
                }
            case .failure(let e): log("probe error: \(e.localizedDescription)")
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let spike = Spike()
DispatchQueue.main.asyncAfter(deadline: .now() + 900) { log("timeout 15 min"); exit(1) }
app.run()

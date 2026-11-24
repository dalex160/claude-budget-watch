import Foundation
import WebKit
import BudgetGuardCore

/// Reads usage from inside a hidden claude.ai page, so the session cookies never leave WebKit.
@MainActor
final class WebSessionSource: NSObject, UsageSource, WKNavigationDelegate {
    private static let home = URL(string: "https://claude.ai/")!
    private static let maxPageAge: TimeInterval = 30 * 60
    private static let maxBody = 64 * 1024

    let webView: WKWebView
    private var loadedAt: Date?
    private var pendingLoad: [CheckedContinuation<Void, Never>] = []
    private var loading = false

    init(dataStore: WKWebsiteDataStore? = nil) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore ?? .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 760), configuration: cfg)
        super.init()
        webView.navigationDelegate = self
    }

    /// True when the page is on claude.ai and the organizations endpoint answers 2xx.
    func hasSession() async -> Bool {
        guard await ensurePage() else { return false }
        guard let r = try? await fetchJSON(path: "/api/organizations") else { return false }
        return ResponseClassifier.error(status: r.status, body: r.body) == nil
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        guard await ensurePage() else { throw UsageFetchError.network }
        let orgs = try await fetchJSON(path: "/api/organizations")
        if let e = ResponseClassifier.error(status: orgs.status, body: orgs.body) { throw e }
        let uuid: String
        do { uuid = try UsageParser.organizationID(fromOrganizationsJSON: Data(orgs.body.utf8)) }
        catch UsageParseError.noOrganization { throw UsageFetchError.unsupportedPlan }
        catch { throw UsageFetchError.malformed }

        let usage = try await fetchJSON(path: "/api/organizations/\(uuid)/usage")
        if let e = ResponseClassifier.error(status: usage.status, body: usage.body) { throw e }
        do { return try UsageParser.snapshot(fromUsageJSON: Data(usage.body.utf8), now: Date()) }
        catch UsageParseError.noWeeklyLimit { throw UsageFetchError.unsupportedPlan }
        catch { throw UsageFetchError.malformed }
    }

    // MARK: - Page lifecycle

    private func ensurePage() async -> Bool {
        let onClaude = webView.url?.host == "claude.ai"
        let fresh = loadedAt.map { Date().timeIntervalSince($0) < Self.maxPageAge } ?? false
        if onClaude && fresh && !webView.isLoading { return true }
        if onClaude && fresh && webView.isLoading { await waitForLoad(); return webView.url?.host == "claude.ai" }
        if !loading {
            loading = true
            webView.load(URLRequest(url: Self.home))
        }
        await waitForLoad()
        return webView.url?.host == "claude.ai"
    }

    private func waitForLoad() async {
        await withCheckedContinuation { pendingLoad.append($0) }
    }

    private func finishLoad(success: Bool) {
        loading = false
        if success { loadedAt = Date() }
        let waiting = pendingLoad
        pendingLoad = []
        waiting.forEach { $0.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad(success: true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad(success: false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad(success: false) }

    // MARK: - In-page fetch

    /// One GET inside the page; returns the raw status and (truncated) body. JS failure (offline) -> `.network`.
    private func fetchJSON(path: String) async throws -> (status: Int, body: String) {
        let js = """
        const r = await fetch(path, {headers: {accept: 'application/json'}, credentials: 'include'});
        const t = await r.text();
        return JSON.stringify({status: r.status, body: t.slice(0, \(Self.maxBody))});
        """
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(js, arguments: ["path": path], in: nil, contentWorld: .page)
        } catch {
            throw UsageFetchError.network
        }
        guard let s = value as? String,
              let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let status = obj["status"] as? Int,
              let body = obj["body"] as? String
        else { throw UsageFetchError.malformed }
        return (status, body)
    }
}

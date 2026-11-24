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
    private var lastLoadSucceeded = false
    private var loadTimeout: Task<Void, Never>?
    private static let loadTimeoutSeconds: Double = 20

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

        guard OrganizationID.isSafe(uuid) else { throw UsageFetchError.malformed }
        let usage = try await fetchJSON(path: "/api/organizations/\(uuid)/usage")
        if let e = ResponseClassifier.error(status: usage.status, body: usage.body) { throw e }
        do { return try UsageParser.snapshot(fromUsageJSON: Data(usage.body.utf8), now: Date()) }
        catch UsageParseError.noWeeklyLimit { throw UsageFetchError.unsupportedPlan }
        catch { throw UsageFetchError.malformed }
    }

    // MARK: - Page lifecycle

    private func ensurePage() async -> Bool {
        let fresh = loadedAt.map { Date().timeIntervalSince($0) < Self.maxPageAge } ?? false
        if webView.url?.host == "claude.ai" && fresh && !webView.isLoading && !loading { return true }
        if !loading {
            loading = true
            webView.load(URLRequest(url: Self.home))
            loadTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.loadTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.webView.stopLoading()
                self?.finishLoad(success: false)
            }
        }
        await waitForLoad()
        return lastLoadSucceeded && webView.url?.host == "claude.ai"
    }

    private func waitForLoad() async {
        await withCheckedContinuation { pendingLoad.append($0) }
    }

    /// Resolves every waiter exactly once; ignored when no load is in flight.
    private func finishLoad(success: Bool) {
        guard loading else { return }
        loading = false
        loadTimeout?.cancel()
        loadTimeout = nil
        lastLoadSucceeded = success
        loadedAt = success ? Date() : nil
        let waiting = pendingLoad
        pendingLoad = []
        waiting.forEach { $0.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad(success: true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad(success: false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad(success: false) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadedAt = nil
        finishLoad(success: false)
    }

    // MARK: - In-page fetch

    /// One GET inside the page; returns the raw status and (truncated) body. JS failure (offline) -> `.network`.
    private func fetchJSON(path: String) async throws -> (status: Int, body: String) {
        let js = """
        const r = await fetch(path, {headers: {accept: 'application/json'}, credentials: 'include', signal: AbortSignal.timeout(20000)});
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

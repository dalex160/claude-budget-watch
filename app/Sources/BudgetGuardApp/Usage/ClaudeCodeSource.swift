import Foundation
import Security
import BudgetGuardCore

/// Fallback: reads Claude Code's own OAuth token. Never refreshes it.
final class ClaudeCodeSource: UsageSource {
    private static let service = "Claude Code-credentials"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Existence check only: never reads the secret, so it cannot trigger a Keychain prompt.
    static func isAvailable() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return true }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    @MainActor func fetchSnapshot() async throws -> UsageSnapshot {
        let token = try Self.readToken()
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw UsageFetchError.network }
        guard let http = response as? HTTPURLResponse else { throw UsageFetchError.network }
        let body = String(data: data.prefix(64 * 1024), encoding: .utf8) ?? ""
        if let e = ResponseClassifier.error(status: http.statusCode, body: body) { throw e }
        do { return try UsageParser.snapshot(fromUsageJSON: data, now: Date()) }
        catch UsageParseError.noWeeklyLimit { throw UsageFetchError.unsupportedPlan }
        catch { throw UsageFetchError.malformed }
    }

    // MARK: - Credentials

    private static func readToken() throws -> String {
        guard let json = credentialsJSON(),
              let oauth = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw UsageFetchError.notLoggedIn }
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: ms / 1000) <= Date() {
            throw UsageFetchError.notLoggedIn
        }
        return token
    }

    private static func credentialsJSON() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return d }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: file)
    }
}

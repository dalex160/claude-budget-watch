import Foundation

public enum ResponseClassifier {
    /// Maps an HTTP status and body to a fetch error; nil for any 2xx.
    public static func error(status: Int, body: String) -> UsageFetchError? {
        if (200..<300).contains(status) { return nil }
        let challenge = body.contains("Just a moment") || body.contains("cf-chl") || body.contains("cf-mitigated")
            || body.contains("cf-ray") || body.contains("cf-browser-verification")
        switch status {
        case 403 where challenge, 503 where challenge: return .cloudflare
        case 401, 403: return .notLoggedIn
        case 429: return .rateLimited
        default: return .network
        }
    }
}

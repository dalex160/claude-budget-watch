import XCTest
@testable import BudgetGuardCore

final class ResponseClassifierTests: XCTestCase {
    func testSuccessIsNil() { XCTAssertNil(ResponseClassifier.error(status: 200, body: "{}")) }
    func test401IsNotLoggedIn() { XCTAssertEqual(ResponseClassifier.error(status: 401, body: ""), .notLoggedIn) }
    func test403WithoutChallengeIsNotLoggedIn() {
        XCTAssertEqual(ResponseClassifier.error(status: 403, body: "{\"error\":\"permission\"}"), .notLoggedIn)
    }
    func test403ChallengeIsCloudflare() {
        XCTAssertEqual(ResponseClassifier.error(status: 403, body: "<title>Just a moment...</title>"), .cloudflare)
    }
    func test503ChallengeIsCloudflare() {
        XCTAssertEqual(ResponseClassifier.error(status: 503, body: "<script src=\"/cdn-cgi/challenge-platform/cf-chl\">"), .cloudflare)
    }
    func test429IsRateLimited() { XCTAssertEqual(ResponseClassifier.error(status: 429, body: ""), .rateLimited) }
    func test500IsNetwork() { XCTAssertEqual(ResponseClassifier.error(status: 500, body: ""), .network) }
}

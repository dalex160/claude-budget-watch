import XCTest
@testable import BudgetGuardCore

final class OnboardingFlowTests: XCTestCase {
    func testWelcomeToLoginOnStart() {
        XCTAssertEqual(OnboardingFlow.next(from: .welcome, event: .start), .go(.login))
    }

    func testLoginToCheckOnLoggedIn() {
        XCTAssertEqual(OnboardingFlow.next(from: .login, event: .loggedIn), .go(.check))
    }

    func testCheckToSettingsOnContinue() {
        XCTAssertEqual(OnboardingFlow.next(from: .check, event: .continueTapped), .go(.settings))
    }

    func testCheckBackToLogin() {
        XCTAssertEqual(OnboardingFlow.next(from: .check, event: .backToLogin), .go(.login))
    }

    func testSettingsToDone() {
        XCTAssertEqual(OnboardingFlow.next(from: .settings, event: .continueTapped), .go(.done))
    }

    func testDoneClosesOnContinue() {
        XCTAssertEqual(OnboardingFlow.next(from: .done, event: .continueTapped), .close)
    }

    func testReconnectClosesAfterSuccessfulCheck() {
        XCTAssertEqual(OnboardingFlow.next(from: .check, event: .checkSucceeded, reconnect: true), .close)
    }

    func testFirstRunStaysOnCheckAfterSuccess() {
        XCTAssertEqual(OnboardingFlow.next(from: .check, event: .checkSucceeded), .stay)
    }

    func testReconnectStillAllowsBackToLoginOnFailure() {
        XCTAssertEqual(OnboardingFlow.next(from: .check, event: .backToLogin, reconnect: true), .go(.login))
    }

    func testIrrelevantEventsStay() {
        XCTAssertEqual(OnboardingFlow.next(from: .welcome, event: .loggedIn), .stay)
        XCTAssertEqual(OnboardingFlow.next(from: .login, event: .continueTapped), .stay)
        XCTAssertEqual(OnboardingFlow.next(from: .done, event: .backToLogin), .stay)
    }

    func testOnlyDoneMarksCompleted() {
        XCTAssertTrue(OnboardingFlow.marksCompleted(closingFrom: .done))
        XCTAssertFalse(OnboardingFlow.marksCompleted(closingFrom: .check))
    }

    func testWindowCloseAlwaysClosesAndOnlyDoneCounts() {
        for step in [OnboardingStep.welcome, .login, .check, .settings, .done] {
            XCTAssertEqual(OnboardingFlow.next(from: step, event: .windowClosed), .close)
            XCTAssertEqual(OnboardingFlow.marksCompleted(closingFrom: step), step == .done)
        }
    }
}

import XCTest
@testable import BudgetGuardCore

final class InstallLocationTests: XCTestCase {
    private let home = "/Users/marie"

    func testApplicationsFolderIsOk() {
        XCTAssertTrue(InstallLocation.isAcceptable(bundlePath: "/Applications/Budget Guard.app", homeDirectory: home))
    }

    func testUserApplicationsFolderIsOk() {
        XCTAssertTrue(InstallLocation.isAcceptable(bundlePath: "/Users/marie/Applications/Budget Guard.app", homeDirectory: home))
    }

    func testMountedDiskImageIsNotOk() {
        XCTAssertFalse(InstallLocation.isAcceptable(bundlePath: "/Volumes/Budget Guard/Budget Guard.app", homeDirectory: home))
    }

    func testTranslocatedIsNotOk() {
        XCTAssertFalse(InstallLocation.isAcceptable(bundlePath: "/private/var/folders/ab/xyz/AppTranslocation/1234/d/Budget Guard.app", homeDirectory: home))
    }

    func testDownloadsIsNotOk() {
        XCTAssertFalse(InstallLocation.isAcceptable(bundlePath: "/Users/marie/Downloads/Budget Guard.app", homeDirectory: home))
    }

    func testTranslocatedUnderApplicationsLookalikeIsNotOk() {
        XCTAssertFalse(InstallLocation.isAcceptable(bundlePath: "/Applications/AppTranslocation/Budget Guard.app", homeDirectory: home))
        XCTAssertFalse(InstallLocation.isAcceptable(bundlePath: "/ApplicationsX/Budget Guard.app", homeDirectory: home))
    }
}

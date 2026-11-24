import XCTest
@testable import BudgetGuardCore

final class OrganizationIDTests: XCTestCase {
    func testAcceptsUUID() { XCTAssertTrue(OrganizationID.isSafe("0a1b2c3d-4E5f-6789-abcd-ef0123456789")) }
    func testRejectsEmpty() { XCTAssertFalse(OrganizationID.isSafe("")) }
    func testRejectsPathTraversal() { XCTAssertFalse(OrganizationID.isSafe("../x")) }
    func testRejectsSlashQueryAndSpace() {
        XCTAssertFalse(OrganizationID.isSafe("a/b"))
        XCTAssertFalse(OrganizationID.isSafe("a?b=1"))
        XCTAssertFalse(OrganizationID.isSafe("a b"))
    }
    func testRejectsNonASCII() { XCTAssertFalse(OrganizationID.isSafe("é-1")) }
}

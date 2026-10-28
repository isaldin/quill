import XCTest
@testable import QuillCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(QuillCore.version, "0.1.0")
    }
}

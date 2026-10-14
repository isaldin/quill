import XCTest
@testable import OpenWhisperCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(OpenWhisperCore.version, "0.1.0")
    }
}

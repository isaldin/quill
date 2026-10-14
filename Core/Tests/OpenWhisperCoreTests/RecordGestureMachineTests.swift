import XCTest
@testable import OpenWhisperCore

final class RecordGestureMachineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func testHoldStartsAndReleaseStops() {
        var machine = RecordGestureMachine()
        XCTAssertEqual(machine.keyDown(at: t0), .start)
        XCTAssertEqual(machine.keyUp(at: t0 + 1), .stop)
        XCTAssertEqual(machine.keyDown(at: t0 + 2), .start)
    }

    func testTapStartsAndSecondTapStops() {
        var machine = RecordGestureMachine()
        XCTAssertEqual(machine.keyDown(at: t0), .start)
        XCTAssertNil(machine.keyUp(at: t0 + 0.1))
        XCTAssertEqual(machine.keyDown(at: t0 + 5), .stop)
        XCTAssertNil(machine.keyUp(at: t0 + 5.1))
        XCTAssertEqual(machine.keyDown(at: t0 + 6), .start)
    }

    func testReleaseExactlyAtThresholdIsTap() {
        var machine = RecordGestureMachine()
        _ = machine.keyDown(at: t0)
        XCTAssertNil(machine.keyUp(at: t0 + RecordGestureMachine.holdThreshold))
    }

    func testKeyRepeatIsIgnored() {
        var machine = RecordGestureMachine()
        XCTAssertEqual(machine.keyDown(at: t0), .start)
        XCTAssertNil(machine.keyDown(at: t0 + 0.5))
        XCTAssertEqual(machine.keyUp(at: t0 + 1), .stop)
    }

    func testResetAfterExternalStopWhileHolding() {
        var machine = RecordGestureMachine()
        XCTAssertEqual(machine.keyDown(at: t0), .start)
        machine.reset()
        XCTAssertNil(machine.keyUp(at: t0 + 2))
        XCTAssertEqual(machine.keyDown(at: t0 + 3), .start)
    }

    func testResetAfterExternalStopInToggleMode() {
        var machine = RecordGestureMachine()
        _ = machine.keyDown(at: t0)
        _ = machine.keyUp(at: t0 + 0.1)
        machine.reset()
        XCTAssertEqual(machine.keyDown(at: t0 + 1), .start)
    }

    func testKeyUpWithoutKeyDownIsIgnored() {
        var machine = RecordGestureMachine()
        XCTAssertNil(machine.keyUp(at: t0))
    }
}

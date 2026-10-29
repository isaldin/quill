import XCTest
@testable import QuillCore

final class RecordingIndicatorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func testFullHappyPathPhases() {
        var model = RecordingIndicatorModel()
        XCTAssertEqual(model.phase, .hidden)
        model.recordingStarted(id: "a", profileName: "Чистка", at: t0)
        XCTAssertEqual(model.phase, .recording(profileName: "Чистка", startedAt: t0))
        model.recordingStopped()
        XCTAssertEqual(model.phase, .transcribing)
        model.apply(.stage(id: "a", .transcribing))
        XCTAssertEqual(model.phase, .transcribing)
        model.apply(.stage(id: "a", .postprocessing))
        XCTAssertEqual(model.phase, .postprocessing)
        model.apply(.finished(id: "a", .inserted))
        XCTAssertEqual(model.phase, .finished(.inserted))
        XCTAssertEqual(model.autoHideDelay, RecordingIndicatorModel.shortHideDelay)
        model.hide()
        XCTAssertEqual(model.phase, .hidden)
    }

    func testConnectingUntilCaptureStartsThenTimerFromCaptureStart() {
        var model = RecordingIndicatorModel()
        model.recordingConnecting(id: "a", profileName: "Чистка")
        XCTAssertEqual(model.phase, .connecting(profileName: "Чистка"))
        XCTAssertNil(model.autoHideDelay)
        model.captureStarted(id: "a", at: t0 + 3)
        XCTAssertEqual(model.phase, .recording(profileName: "Чистка", startedAt: t0 + 3))
    }

    func testStopWhileConnectingGoesToTranscribing() {
        var model = RecordingIndicatorModel()
        model.recordingConnecting(id: "a", profileName: "P")
        model.recordingStopped()
        XCTAssertEqual(model.phase, .transcribing)
        model.captureStarted(id: "a", at: t0)
        XCTAssertEqual(model.phase, .transcribing)
        model.apply(.finished(id: "a", .inserted))
        XCTAssertEqual(model.phase, .finished(.inserted))
    }

    func testCancelWhileConnecting() {
        var model = RecordingIndicatorModel()
        model.recordingConnecting(id: "a", profileName: "P")
        model.recordingCancelled()
        XCTAssertEqual(model.phase, .finished(.cancelled))
        model.captureStarted(id: "a", at: t0)
        XCTAssertEqual(model.phase, .finished(.cancelled))
    }

    func testCaptureStartOfAnotherRecordingIsIgnored() {
        var model = RecordingIndicatorModel()
        model.recordingConnecting(id: "b", profileName: "P")
        model.captureStarted(id: "a", at: t0)
        XCTAssertEqual(model.phase, .connecting(profileName: "P"))
    }

    func testEventsOfPreviousDictationAreIgnoredOnceNewRecordingStarts() {
        var model = RecordingIndicatorModel()
        model.recordingStarted(id: "a", profileName: "P", at: t0)
        model.recordingStopped()
        model.recordingStarted(id: "b", profileName: "P", at: t0 + 1)
        model.apply(.finished(id: "a", .inserted))
        XCTAssertEqual(model.phase, .recording(profileName: "P", startedAt: t0 + 1))
    }

    func testDiscardedRecordingHidesImmediately() {
        var model = RecordingIndicatorModel()
        model.recordingStarted(id: "a", profileName: "P", at: t0)
        model.recordingStopped()
        model.apply(.finished(id: "a", .discarded))
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertNil(model.autoHideDelay)
    }

    func testCancelShowsCancelledBriefly() {
        var model = RecordingIndicatorModel()
        model.recordingStarted(id: "a", profileName: "P", at: t0)
        model.recordingCancelled()
        XCTAssertEqual(model.phase, .finished(.cancelled))
        XCTAssertEqual(model.autoHideDelay, RecordingIndicatorModel.shortHideDelay)
    }

    func testFailureStaysLonger() {
        var model = RecordingIndicatorModel()
        model.recordingStarted(id: "a", profileName: "P", at: t0)
        model.recordingStopped()
        model.apply(.finished(id: "a", .failed("нет сети")))
        XCTAssertEqual(model.phase, .finished(.failed("нет сети")))
        XCTAssertEqual(model.autoHideDelay, RecordingIndicatorModel.longHideDelay)
    }

    func testCopiedToClipboardOutcome() {
        var model = RecordingIndicatorModel()
        model.recordingStarted(id: "a", profileName: "P", at: t0)
        model.recordingStopped()
        model.apply(.finished(id: "a", .copiedToClipboard))
        XCTAssertEqual(model.phase, .finished(.copiedToClipboard))
    }

    func testNoAutoHideWhileWorking() {
        var model = RecordingIndicatorModel()
        model.recordingStarted(id: "a", profileName: "P", at: t0)
        XCTAssertNil(model.autoHideDelay)
        model.recordingStopped()
        XCTAssertNil(model.autoHideDelay)
    }

    func testStopAndCancelWithoutRecordingAreIgnored() {
        var model = RecordingIndicatorModel()
        model.recordingStopped()
        model.recordingCancelled()
        XCTAssertEqual(model.phase, .hidden)
    }

    func testLevelMeterNormalization() {
        XCTAssertEqual(LevelMeter.normalized(decibels: -160), 0)
        XCTAssertEqual(LevelMeter.normalized(decibels: -50), 0)
        XCTAssertEqual(LevelMeter.normalized(decibels: -25), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LevelMeter.normalized(decibels: 0), 1)
        XCTAssertEqual(LevelMeter.normalized(decibels: 6), 1)
        XCTAssertEqual(LevelMeter.normalized(decibels: -.infinity), 0)
        XCTAssertEqual(LevelMeter.normalized(decibels: .nan), 0)
    }
}

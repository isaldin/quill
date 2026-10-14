import XCTest
@testable import OpenWhisperCore

final class AudioStoreTests: XCTestCase {
    var directory: URL!
    var store: AudioStore!
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ow-audio-\(UUID().uuidString)")
        store = try AudioStore(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func makeFile(_ id: String, bytes: Int, modified: Date) throws -> URL {
        let url = store.newRecordingURL(id: id)
        try Data(repeating: 1, count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: store.newRecordingURL(id: id).path)
    }

    func testInitCreatesDirectoryAndURLsLiveInside() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(store.newRecordingURL(id: "x"), directory.appending(path: "x.m4a"))
        XCTAssertEqual(store.url(for: "x.m4a"), directory.appending(path: "x.m4a"))
    }

    func testTotalSizeAndDelete() throws {
        try makeFile("a", bytes: 100, modified: now)
        try makeFile("b", bytes: 50, modified: now)
        XCTAssertEqual(store.totalSize(), 150)
        store.delete(fileName: "a.m4a")
        XCTAssertEqual(store.totalSize(), 50)
    }

    func testRotationDeletesOldestKnownFilesUntilUnderLimit() throws {
        try makeFile("a", bytes: 100, modified: now.addingTimeInterval(-300))
        try makeFile("b", bytes: 100, modified: now.addingTimeInterval(-200))
        try makeFile("c", bytes: 100, modified: now.addingTimeInterval(-100))
        let removed = store.rotate(limitBytes: 150, knownIDs: ["a", "b", "c"], now: now)
        XCTAssertEqual(removed, ["a", "b"])
        XCTAssertFalse(exists("a"))
        XCTAssertFalse(exists("b"))
        XCTAssertTrue(exists("c"))
    }

    func testRotationDoesNothingUnderLimit() throws {
        try makeFile("a", bytes: 100, modified: now)
        XCTAssertEqual(store.rotate(limitBytes: 1000, knownIDs: ["a"], now: now), [])
        XCTAssertTrue(exists("a"))
    }

    func testRotationKeepsFreshOrphansAndDeletesOldOnes() throws {
        try makeFile("old-orphan", bytes: 10, modified: now.addingTimeInterval(-3600))
        try makeFile("recording-now", bytes: 10, modified: now.addingTimeInterval(-60))
        let removed = store.rotate(limitBytes: 1_000_000, knownIDs: [], now: now)
        XCTAssertEqual(removed, [])
        XCTAssertFalse(exists("old-orphan"))
        XCTAssertTrue(exists("recording-now"))
    }

    func testRotationNeverDeletesFreshOrphanEvenOverLimit() throws {
        try makeFile("known", bytes: 100, modified: now.addingTimeInterval(-600))
        try makeFile("recording-now", bytes: 100, modified: now.addingTimeInterval(-10))
        let removed = store.rotate(limitBytes: 50, knownIDs: ["known"], now: now)
        XCTAssertEqual(removed, ["known"])
        XCTAssertTrue(exists("recording-now"))
    }
}

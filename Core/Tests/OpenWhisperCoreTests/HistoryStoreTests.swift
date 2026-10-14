import XCTest
@testable import OpenWhisperCore

final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!
    let base = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() async throws {
        store = try HistoryStore.inMemory()
    }

    private func record(_ id: String, minutes: Double = 0, raw: String? = nil, final: String? = nil, cost: Double = 0) -> DictationRecord {
        var record = DictationRecord(
            id: id, createdAt: base.addingTimeInterval(minutes * 60), profileID: "clean",
            durationSec: 3, audioFileName: "\(id).m4a"
        )
        record.rawText = raw
        record.finalText = final
        record.costUSD = cost
        return record
    }

    func testInsertFetchUpdateDelete() throws {
        var item = record("a", raw: "сырой")
        try store.insert(item)
        XCTAssertEqual(try store.record(id: "a"), item)
        XCTAssertEqual(item.status, .recorded)

        item.status = .inserted
        item.finalText = "итог"
        item.postprocessFailed = true
        item.error = "oops"
        try store.update(item)
        XCTAssertEqual(try store.record(id: "a"), item)

        try store.delete(id: "a")
        XCTAssertNil(try store.record(id: "a"))
    }

    func testRecentIsNewestFirst() throws {
        try store.insert(record("old", minutes: 0))
        try store.insert(record("new", minutes: 5))
        try store.insert(record("mid", minutes: 2))
        XCTAssertEqual(try store.recent().map(\.id), ["new", "mid", "old"])
        XCTAssertEqual(try store.recent(limit: 1).map(\.id), ["new"])
    }

    func testSearchFindsRawAndFinalTextByPrefix() throws {
        try store.insert(record("a", raw: "починить фронтенд"))
        try store.insert(record("b", final: "Обновить бэкенд"))
        XCTAssertEqual(try store.search("фронт").map(\.id), ["a"])
        XCTAssertEqual(try store.search("бэкенд").map(\.id), ["b"])
        XCTAssertEqual(try store.search("нигде").map(\.id), [])
    }

    func testSearchHandlesHyphensQuotesAndCase() throws {
        try store.insert(record("a", minutes: 1, final: "Обнови frontend-config и ПРИВЕТ"))
        try store.insert(record("b", minutes: 0, final: "другое"))
        XCTAssertEqual(try store.search("Frontend-Config").map(\.id), ["a"])
        XCTAssertEqual(try store.search("привет").map(\.id), ["a"])
        XCTAssertEqual(try store.search("\"").map(\.id), ["a", "b"])
        XCTAssertEqual(try store.search("   ").map(\.id), ["a", "b"])
    }

    func testSearchSeesUpdatedText() throws {
        var item = record("a", raw: "старый")
        try store.insert(item)
        item.finalText = "новый"
        try store.update(item)
        XCTAssertEqual(try store.search("новый").map(\.id), ["a"])
    }

    func testTotalCostSince() throws {
        try store.insert(record("a", minutes: -60, cost: 1.0))
        try store.insert(record("b", minutes: 0, cost: 0.25))
        try store.insert(record("c", minutes: 10, cost: 0.5))
        XCTAssertEqual(try store.totalCost(since: base), 0.75, accuracy: 1e-9)
        XCTAssertEqual(try store.totalCost(since: base.addingTimeInterval(3600)), 0)
    }

    func testAllIDsAndClearAudio() throws {
        try store.insert(record("a"))
        try store.insert(record("b"))
        XCTAssertEqual(try store.allIDs(), ["a", "b"])
        try store.clearAudio(ids: ["a"])
        XCTAssertNil(try store.record(id: "a")?.audioFileName)
        XCTAssertEqual(try store.record(id: "b")?.audioFileName, "b.m4a")
        try store.clearAudio(ids: [])
    }

    func testOpenOnDiskCreatesDirectoryAndPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ow-db-\(UUID().uuidString)/history.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try HistoryStore.open(at: url).insert(record("a"))
        XCTAssertEqual(try HistoryStore.open(at: url).allIDs(), ["a"])
    }

    func testDisplayTextPrefersFinal() {
        var item = record("a", raw: "сырой")
        XCTAssertEqual(item.displayText, "сырой")
        item.finalText = "итог"
        XCTAssertEqual(item.displayText, "итог")
    }

    func testIDsWithoutRawText() throws {
        try store.insert(record("pending"))
        try store.insert(record("done", raw: "текст"))
        XCTAssertEqual(try store.idsWithoutRawText(), ["pending"])
    }

    func testMarkInterruptedFailsOnlyUnfinishedDictations() throws {
        let statuses: [DictationStatus] = [.recorded, .transcribed, .processed, .inserted, .failed]
        for status in statuses {
            var item = record(status.rawValue)
            item.status = status
            try store.insert(item)
        }
        XCTAssertEqual(try store.markInterrupted(), 2)
        for status in statuses {
            let item = try XCTUnwrap(store.record(id: status.rawValue))
            switch status {
            case .recorded, .transcribed:
                XCTAssertEqual(item.status, .failed)
                XCTAssertEqual(item.error, HistoryStore.interruptedMessage)
            default:
                XCTAssertEqual(item.status, status)
                XCTAssertNil(item.error)
            }
        }
    }
}

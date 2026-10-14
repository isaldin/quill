import XCTest
@testable import OpenWhisperCore

@MainActor
final class SharedSettingsStoreTests: XCTestCase {
    var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ow-shared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appending(path: "settings.json") }

    private func writeFile(_ text: String) throws {
        try Data(text.utf8).write(to: fileURL)
    }

    func testReloadReadsFile() throws {
        try writeFile(#"{"default_llm_model":"x/y","sounds_enabled":false}"#)
        let store = SharedSettingsStore(directory: directory)
        store.reload()
        XCTAssertEqual(store.settings.defaultLLMModel, "x/y")
        XCTAssertFalse(store.settings.soundsEnabled)
        XCTAssertNil(store.loadError)
    }

    func testMissingFileKeepsInitialValues() {
        let initial = SharedSettings(defaultLLMModel: "init/llm")
        let store = SharedSettingsStore(directory: directory, initial: initial)
        store.reload()
        XCTAssertEqual(store.settings, initial)
        XCTAssertNil(store.loadError)
    }

    func testUpdateWritesValidFileAndRoundTrips() throws {
        let store = SharedSettingsStore(directory: directory)
        try store.update { $0.defaultLLMModel = "new/llm"; $0.audioLimitGB = 3 }
        XCTAssertEqual(store.settings.defaultLLMModel, "new/llm")
        let reread = SharedSettingsStore(directory: directory)
        reread.reload()
        XCTAssertEqual(reread.settings, store.settings)
    }

    func testUpdateNormalizes() throws {
        let store = SharedSettingsStore(directory: directory)
        try store.update { $0.defaultLLMModel = "  "; $0.audioLimitGB = 0 }
        XCTAssertEqual(store.settings.defaultLLMModel, SharedSettings.defaultLLMModelID)
        XCTAssertEqual(store.settings.audioLimitGB, 0.1)
    }

    func testAtomicWriteLeavesNoTemporaryFiles() throws {
        let store = SharedSettingsStore(directory: directory)
        try store.update { $0.soundsEnabled = false }
        try store.update { $0.soundsEnabled = true }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names, ["settings.json"])
    }

    func testBrokenFileKeepsLastGoodValuesAndReportsError() throws {
        try writeFile(#"{"default_llm_model":"good/llm"}"#)
        let store = SharedSettingsStore(directory: directory)
        store.reload()
        try writeFile(#"{"default_llm_model": "#)
        store.reload()
        XCTAssertEqual(store.settings.defaultLLMModel, "good/llm")
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), #"{"default_llm_model": "#)
    }

    func testUpdateAfterBrokenFileWritesValidFileAndClearsError() throws {
        try writeFile("{")
        let store = SharedSettingsStore(directory: directory)
        store.reload()
        XCTAssertNotNil(store.loadError)
        try store.update { $0.soundsEnabled = false }
        XCTAssertNil(store.loadError)
        XCTAssertFalse(try SharedSettings.decode(Data(contentsOf: fileURL)).soundsEnabled)
    }

    func testConflictCopiesAreIgnored() throws {
        try writeFile(#"{"default_llm_model":"main/llm"}"#)
        try Data(#"{"default_llm_model":"conflict/llm"}"#.utf8).write(to: directory.appending(path: "settings 2.json"))
        let store = SharedSettingsStore(directory: directory)
        store.reload()
        XCTAssertEqual(store.settings.defaultLLMModel, "main/llm")
    }

    func testPendingPlaceholderKeepsValues() throws {
        try Data().write(to: directory.appending(path: ".settings.json.icloud"))
        let initial = SharedSettings(soundsEnabled: false)
        let store = SharedSettingsStore(directory: directory, initial: initial)
        store.reload()
        XCTAssertEqual(store.settings, initial)
        XCTAssertNil(store.loadError)
    }

    func testUpdateWithoutChangesDoesNotRewriteFile() throws {
        let store = SharedSettingsStore(directory: directory)
        try store.update { $0.soundsEnabled = false }
        let past = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: fileURL.path)
        try store.update { $0.soundsEnabled = false }
        let modified = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        XCTAssertEqual(modified, past)
    }

    func testUpdateRecreatesDeletedDirectory() throws {
        let store = SharedSettingsStore(directory: directory)
        try FileManager.default.removeItem(at: directory)
        try store.update { $0.showIndicator = false }
        XCTAssertFalse(try SharedSettings.decode(Data(contentsOf: fileURL)).showIndicator)
    }
}

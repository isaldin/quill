import XCTest
@testable import OpenWhisperCore

@MainActor
final class ProfileStoreTests: XCTestCase {
    var directory: URL!
    var defaults: UserDefaults!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ow-profiles-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "ow-tests-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ id: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appending(path: "\(id).md"), atomically: true, encoding: .utf8)
    }

    private func makeStore() -> ProfileStore {
        ProfileStore(directory: directory, defaults: defaults)
    }

    func testBootstrapCreatesBuiltinsInEmptyDirectory() throws {
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.validProfiles.map(\.id), ["clean", "raw"])
        XCTAssertEqual(store.profile(id: "raw")?.postprocess, false)
        XCTAssertEqual(store.profile(id: "clean")?.postprocess, true)
    }

    func testBootstrapRecreatesBuiltinsWhenAllProfilesDeleted() throws {
        let store = makeStore()
        try store.bootstrap()
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        let restarted = makeStore()
        try restarted.bootstrap()
        XCTAssertEqual(restarted.validProfiles.map(\.id), ["clean", "raw"])
    }

    func testBootstrapDoesNotTouchExistingProfiles() throws {
        try write("my", "---\nname: Мой\n---\n")
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.validProfiles.map(\.id), ["my"])
    }

    func testInvalidProfileIsListedButNotSelectable() throws {
        try write("a", "---\nname: A\n---\n")
        try write("b", "без frontmatter")
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.entries.map(\.id), ["a", "b"])
        XCTAssertEqual(store.validProfiles.map(\.id), ["a"])
        guard case .invalid(_, let message) = store.entries[1] else { return XCTFail("b должен быть invalid") }
        XCTAssertFalse(message.isEmpty)
    }

    func testActiveFallsBackToRawWhenActiveProfileIsBroken() throws {
        try write("raw", "---\nname: Raw\npostprocess: false\n---\n")
        try write("work", "сломан")
        let store = makeStore()
        try store.bootstrap()
        store.activeProfileID = "work"
        XCTAssertEqual(store.activeProfile.id, "raw")
    }

    func testActiveFallsBackToBuiltinRawWhenNothingIsValid() throws {
        try write("broken", "сломан")
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.activeProfile, .fallbackRaw)
    }

    func testDefaultActiveProfileIsClean() throws {
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.activeProfile.id, "clean")
    }

    func testActiveProfileIDPersistsInDefaults() throws {
        let store = makeStore()
        try store.bootstrap()
        store.activeProfileID = "raw"
        let other = makeStore()
        XCTAssertEqual(other.activeProfileID, "raw")
    }

    func testSelectNextCyclesThroughValidProfiles() throws {
        try write("a", "---\nname: A\n---\n")
        try write("b", "---\nname: B\n---\n")
        try write("c", "---\nname: C\n---\n")
        try write("d", "сломан")
        let store = makeStore()
        try store.bootstrap()
        store.activeProfileID = "a"
        store.selectNext()
        XCTAssertEqual(store.activeProfileID, "b")
        store.selectNext()
        XCTAssertEqual(store.activeProfileID, "c")
        store.selectNext()
        XCTAssertEqual(store.activeProfileID, "a")
    }

    func testReloadPicksUpEditedFile() throws {
        try write("a", "---\nname: Старое\n---\n")
        let store = makeStore()
        try store.bootstrap()
        try write("a", "---\nname: Новое\n---\n")
        store.reload()
        XCTAssertEqual(store.profile(id: "a")?.name, "Новое")
    }

    func testIgnoresNonMarkdownFiles() throws {
        try write("a", "---\nname: A\n---\n")
        try "x".write(to: directory.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.entries.map(\.id), ["a"])
    }

    func testBootstrapDoesNotCreateBuiltinsWhileProfilesArePending() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appending(path: ".work.md.icloud"))
        let store = makeStore()
        try store.bootstrap()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "raw.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "clean.md").path))
    }

    func testPendingPlaceholderIsNotListedAsProfile() throws {
        try write("a", "---\nname: A\n---\n")
        try Data().write(to: directory.appending(path: ".work.md.icloud"))
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.entries.map(\.id), ["a"])
    }

    func testPendingActiveProfileFallsBackToRaw() throws {
        try write("raw", "---\nname: Raw\npostprocess: false\n---\n")
        try Data().write(to: directory.appending(path: ".work.md.icloud"))
        let store = makeStore()
        try store.bootstrap()
        store.activeProfileID = "work"
        XCTAssertEqual(store.activeProfile.id, "raw")
    }
}

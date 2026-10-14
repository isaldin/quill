import XCTest
@testable import OpenWhisperCore

final class SyncBootstrapTests: XCTestCase {
    var root: URL!
    var cloud: SyncLocation!
    var legacy: URL!
    var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ow-boot-\(UUID().uuidString)")
        cloud = SyncLocation(directory: root.appending(path: "iCloud/OpenWhisper"), isICloud: true)
        legacy = root.appending(path: "legacy")
        defaults = UserDefaults(suiteName: "ow-boot-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func sharedSettings(_ location: SyncLocation) throws -> SharedSettings {
        try SharedSettings.decode(Data(contentsOf: location.settingsURL))
    }

    private func profileNames(_ location: SyncLocation) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: location.profilesDirectory.path).sorted()
    }

    private func run(_ location: SyncLocation) throws {
        try SyncBootstrap.run(location: location, legacyDirectory: legacy, legacyDefaults: defaults)
    }

    func testCreatesDirectoriesAndDefaultSettings() throws {
        try run(cloud)
        XCTAssertEqual(try sharedSettings(cloud), .defaults)
        XCTAssertEqual(try profileNames(cloud), [])
    }

    func testSettingsFromLegacyFileFirst() throws {
        try write(#"{"default_llm_model":"file/llm"}"#, to: legacy.appending(path: "settings.json"))
        defaults.set("defaults/llm", forKey: "defaultLLMModel")
        try run(cloud)
        XCTAssertEqual(try sharedSettings(cloud).defaultLLMModel, "file/llm")
    }

    func testSettingsFromUserDefaultsWhenNoLegacyFile() throws {
        defaults.set("defaults/llm", forKey: "defaultLLMModel")
        defaults.set(false, forKey: "soundsEnabled")
        try run(cloud)
        XCTAssertEqual(try sharedSettings(cloud).defaultLLMModel, "defaults/llm")
        XCTAssertFalse(try sharedSettings(cloud).soundsEnabled)
    }

    func testBrokenLegacySettingsFallsBackToUserDefaults() throws {
        try write("{ broken", to: legacy.appending(path: "settings.json"))
        defaults.set("defaults/llm", forKey: "defaultLLMModel")
        try run(cloud)
        XCTAssertEqual(try sharedSettings(cloud).defaultLLMModel, "defaults/llm")
    }

    func testExistingSettingsAreNotTouched() throws {
        try write(#"{"default_llm_model":"cloud/llm"}"#, to: cloud.settingsURL)
        defaults.set("defaults/llm", forKey: "defaultLLMModel")
        try run(cloud)
        XCTAssertEqual(try String(contentsOf: cloud.settingsURL, encoding: .utf8), #"{"default_llm_model":"cloud/llm"}"#)
    }

    func testPendingSettingsPlaceholderIsNotOverwritten() throws {
        try write("", to: ICloudPlaceholder.placeholderURL(for: cloud.settingsURL))
        try run(cloud)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.settingsURL.path))
    }

    func testCopiesLegacyProfilesIntoEmptyCloudFolder() throws {
        try write("---\nname: A\n---\n", to: legacy.appending(path: "profiles/a.md"))
        try write("---\nname: B\n---\n", to: legacy.appending(path: "profiles/b.md"))
        try run(cloud)
        XCTAssertEqual(try profileNames(cloud), ["a.md", "b.md"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appending(path: "profiles/a.md").path))
    }

    func testCopiesOnlyMarkdownProfiles() throws {
        try write("---\nname: A\n---\n", to: legacy.appending(path: "profiles/a.md"))
        try write("заметка", to: legacy.appending(path: "profiles/notes.txt"))
        try write("x", to: legacy.appending(path: "profiles/.DS_Store"))
        try write("---\nname: Z\n---\n", to: legacy.appending(path: "profiles/sub/z.md"))
        try run(cloud)
        XCTAssertEqual(try profileNames(cloud), ["a.md"])
    }

    func testDoesNotCopyProfilesIntoNonEmptyCloudFolder() throws {
        try write("---\nname: Cloud\n---\n", to: cloud.profilesDirectory.appending(path: "cloud.md"))
        try write("---\nname: A\n---\n", to: legacy.appending(path: "profiles/a.md"))
        try run(cloud)
        XCTAssertEqual(try profileNames(cloud), ["cloud.md"])
    }

    func testDoesNotCopyProfilesWhileCloudProfilesArePending() throws {
        try write("", to: cloud.profilesDirectory.appending(path: ".cloud.md.icloud"))
        try write("---\nname: A\n---\n", to: legacy.appending(path: "profiles/a.md"))
        try run(cloud)
        XCTAssertEqual(try profileNames(cloud), [".cloud.md.icloud"])
    }

    func testLocalModeUsesUserDefaultsAndDoesNotCopyProfiles() throws {
        let local = SyncLocation(directory: legacy, isICloud: false)
        try write("---\nname: A\n---\n", to: legacy.appending(path: "profiles/a.md"))
        defaults.set("defaults/llm", forKey: "defaultLLMModel")
        try run(local)
        XCTAssertEqual(try sharedSettings(local).defaultLLMModel, "defaults/llm")
        XCTAssertEqual(try profileNames(local), ["a.md"])
    }
}

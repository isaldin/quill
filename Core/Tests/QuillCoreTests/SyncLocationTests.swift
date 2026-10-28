import XCTest
@testable import QuillCore

final class SyncLocationTests: XCTestCase {
    var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ow-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testResolvesICloudWhenRootExists() throws {
        let iCloud = root.appending(path: "CloudDocs")
        try FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
        let location = SyncLocation.resolve(iCloudRoot: iCloud, localDirectory: root.appending(path: "local"))
        XCTAssertTrue(location.isICloud)
        XCTAssertEqual(location.directory.path, iCloud.appending(path: "Quill").path)
        XCTAssertEqual(location.profilesDirectory.path, iCloud.appending(path: "Quill/profiles").path)
        XCTAssertEqual(location.settingsURL.path, iCloud.appending(path: "Quill/settings.json").path)
    }

    func testFallsBackToLocalWithoutICloud() {
        let local = root.appending(path: "local")
        let location = SyncLocation.resolve(iCloudRoot: root.appending(path: "missing"), localDirectory: local)
        XCTAssertFalse(location.isICloud)
        XCTAssertEqual(location.directory.path, local.path)
    }

    func testDefaultPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(SyncLocation.defaultICloudRoot.path, home + "/Library/Mobile Documents/com~apple~CloudDocs")
        XCTAssertEqual(SyncLocation.defaultLocalDirectory.path, home + "/.config/quill")
    }

    func testPlaceholderURL() {
        let file = root.appending(path: "settings.json")
        XCTAssertEqual(ICloudPlaceholder.placeholderURL(for: file).lastPathComponent, ".settings.json.icloud")
    }

    func testIsPendingOnlyWhenPlaceholderWithoutFile() throws {
        let file = root.appending(path: "settings.json")
        XCTAssertFalse(ICloudPlaceholder.isPending(file))
        try Data().write(to: ICloudPlaceholder.placeholderURL(for: file))
        XCTAssertTrue(ICloudPlaceholder.isPending(file))
        try Data("{}".utf8).write(to: file)
        XCTAssertFalse(ICloudPlaceholder.isPending(file))
    }

    func testPendingFilesListsOnlyMissingOriginalsWithExtension() throws {
        try Data().write(to: root.appending(path: ".work.md.icloud"))
        try Data().write(to: root.appending(path: ".notes.txt.icloud"))
        try Data().write(to: root.appending(path: ".done.md.icloud"))
        try Data().write(to: root.appending(path: "done.md"))
        let pending = ICloudPlaceholder.pendingFiles(in: root, pathExtension: "md")
        XCTAssertEqual(pending.map(\.lastPathComponent), ["work.md"])
    }

    func testRequestDownloadOutsideICloudDoesNotCrash() {
        ICloudPlaceholder.requestDownload(root.appending(path: "x.md"))
    }
}

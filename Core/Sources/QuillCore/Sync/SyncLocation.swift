import Foundation

public struct SyncLocation: Equatable, Sendable {
    public let directory: URL
    public let isICloud: Bool

    public init(directory: URL, isICloud: Bool) {
        self.directory = directory
        self.isICloud = isICloud
    }

    public var profilesDirectory: URL { directory.appending(path: "profiles", directoryHint: .isDirectory) }
    public var settingsURL: URL { directory.appending(path: SharedSettings.fileName) }

    public static var defaultICloudRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    }

    public static var defaultLocalDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/quill", directoryHint: .isDirectory)
    }

    public static func resolve(
        iCloudRoot: URL = SyncLocation.defaultICloudRoot,
        localDirectory: URL = SyncLocation.defaultLocalDirectory
    ) -> SyncLocation {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: iCloudRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return SyncLocation(
                directory: iCloudRoot.appending(path: "Quill", directoryHint: .isDirectory), isICloud: true
            )
        }
        return SyncLocation(directory: localDirectory, isICloud: false)
    }
}

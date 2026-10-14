import Foundation

/// Переезд при запуске: создаёт недостающее в общей папке, ничего существующего не трогает.
public enum SyncBootstrap {
    public static func run(location: SyncLocation, legacyDirectory: URL, legacyDefaults: UserDefaults) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: location.profilesDirectory, withIntermediateDirectories: true)

        let settingsURL = location.settingsURL
        if !fileManager.fileExists(atPath: settingsURL.path), !ICloudPlaceholder.isPending(settingsURL) {
            let initial = legacySettingsFile(location: location, legacyDirectory: legacyDirectory)
                ?? SharedSettings(legacyDefaults: legacyDefaults)
            try initial.encoded().write(to: settingsURL, options: .atomic)
        }

        guard location.isICloud else { return }
        let target = location.profilesDirectory
        let hasProfiles = !markdownFiles(in: target).isEmpty
            || !ICloudPlaceholder.pendingFiles(in: target, pathExtension: "md").isEmpty
        guard !hasProfiles else { return }
        for source in markdownFiles(in: legacyDirectory.appending(path: "profiles", directoryHint: .isDirectory)) {
            try fileManager.copyItem(at: source, to: target.appending(path: source.lastPathComponent))
        }
    }

    private static func legacySettingsFile(location: SyncLocation, legacyDirectory: URL) -> SharedSettings? {
        guard location.isICloud,
              let data = try? Data(contentsOf: legacyDirectory.appending(path: SharedSettings.fileName))
        else { return nil }
        return try? SharedSettings.decode(data)
    }

    private static func markdownFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        return urls.filter { url in
            url.pathExtension == "md"
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}

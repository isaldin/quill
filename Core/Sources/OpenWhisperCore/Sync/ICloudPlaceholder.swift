import Foundation

/// Пока iCloud не скачал файл (при «Оптимизации хранилища»), вместо `name` лежит `.name.icloud`.
public enum ICloudPlaceholder {
    public static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
    }

    public static func isPending(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        return !fileManager.fileExists(atPath: url.path)
            && fileManager.fileExists(atPath: placeholderURL(for: url).path)
    }

    /// URL оригиналов (`directory/name.ext`), для которых есть только заглушка.
    public static func pendingFiles(in directory: URL, pathExtension: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name -> URL? in
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
            let original = String(name.dropFirst().dropLast(".icloud".count))
            guard (original as NSString).pathExtension == pathExtension else { return nil }
            let url = directory.appending(path: original)
            return FileManager.default.fileExists(atPath: url.path) ? nil : url
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public static func requestDownload(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}

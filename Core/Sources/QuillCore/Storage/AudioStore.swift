import Foundation

public struct AudioStore: Sendable {
    /// Файл без записи в базе младше этого возраста считается идущей записью и не трогается.
    public static let orphanGracePeriod: TimeInterval = 15 * 60

    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Quill/audio", directoryHint: .isDirectory)
    }

    public func newRecordingURL(id: String) -> URL {
        directory.appending(path: "\(id).m4a")
    }

    public func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    public func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    public func totalSize() -> Int64 {
        files().reduce(0) { $0 + $1.size }
    }

    /// 1. Удаляет файлы без записи в базе, если они старше orphanGracePeriod.
    /// 2. Пока суммарный размер больше лимита, удаляет самые старые файлы известных записей,
    ///    кроме protectedIDs (записи без текста: их аудио — единственная копия диктовки).
    /// Возвращает id записей, у которых удалено аудио, в порядке удаления.
    public func rotate(
        limitBytes: Int64, knownIDs: Set<String>, protectedIDs: Set<String> = [], now: Date = Date()
    ) -> [String] {
        var known: [FileInfo] = []
        var total: Int64 = 0
        for file in files() {
            if knownIDs.contains(file.id) {
                if !protectedIDs.contains(file.id) {
                    known.append(file)
                }
                total += file.size
            } else if now.timeIntervalSince(file.modified) > Self.orphanGracePeriod {
                try? FileManager.default.removeItem(at: file.url)
            } else {
                total += file.size
            }
        }

        var removed: [String] = []
        for file in known.sorted(by: { $0.modified < $1.modified }) {
            guard total > limitBytes else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
            removed.append(file.id)
        }
        return removed
    }

    private struct FileInfo {
        let url: URL
        let id: String
        let size: Int64
        let modified: Date
    }

    private func files() -> [FileInfo] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        )) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                return nil
            }
            return FileInfo(
                url: url,
                id: url.deletingPathExtension().lastPathComponent,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast
            )
        }
    }
}

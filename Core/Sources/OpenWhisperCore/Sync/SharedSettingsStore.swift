import Foundation
import Observation

@MainActor
@Observable
public final class SharedSettingsStore {
    public let directory: URL
    public private(set) var settings: SharedSettings
    /// Текст ошибки разбора settings.json; пока он есть, работаем на последних корректных значениях.
    public private(set) var loadError: String?

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    public init(directory: URL, initial: SharedSettings = .defaults) {
        self.directory = directory
        self.settings = initial
    }

    public var fileURL: URL { directory.appending(path: SharedSettings.fileName) }

    public func reload() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            if ICloudPlaceholder.isPending(url) {
                ICloudPlaceholder.requestDownload(url)
            }
            return
        }
        do {
            let loaded = try SharedSettings.decode(Data(contentsOf: url))
            if loaded != settings { settings = loaded }
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Меняет настройки и атомарно переписывает settings.json.
    /// Если ничего не изменилось и файл корректен, файл не трогается.
    public func update(_ change: (inout SharedSettings) -> Void) throws {
        var next = settings
        change(&next)
        next = next.normalized
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        guard next != settings || loadError != nil || !fileExists else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try next.encoded().write(to: fileURL, options: .atomic)
        settings = next
        loadError = nil
    }

    public func startWatching() {
        guard watcher == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}

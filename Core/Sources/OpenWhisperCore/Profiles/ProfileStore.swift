import Foundation
import Observation

public enum ProfileEntry: Equatable, Sendable, Identifiable {
    case valid(Profile)
    case invalid(id: String, message: String)

    public var id: String {
        switch self {
        case .valid(let profile): profile.id
        case .invalid(let id, _): id
        }
    }

    public var profile: Profile? {
        if case .valid(let profile) = self { return profile }
        return nil
    }
}

@MainActor
@Observable
public final class ProfileStore {
    public static let activeProfileKey = "activeProfileID"

    public let directory: URL
    public private(set) var entries: [ProfileEntry] = []
    public var activeProfileID: String {
        didSet { defaults.set(activeProfileID, forKey: Self.activeProfileKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    public init(directory: URL, defaults: UserDefaults) {
        self.directory = directory
        self.defaults = defaults
        self.activeProfileID = defaults.string(forKey: Self.activeProfileKey) ?? "clean"
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/openwhisper/profiles", directoryHint: .isDirectory)
    }

    public var validProfiles: [Profile] { entries.compactMap(\.profile) }

    public var activeProfile: Profile {
        profile(id: activeProfileID) ?? profile(id: "raw") ?? .fallbackRaw
    }

    public func profile(id: String) -> Profile? {
        validProfiles.first { $0.id == id }
    }

    /// Создаёт каталог; если в нём нет ни одного .md и ни одной заглушки iCloud, кладёт встроенные профили.
    /// Затем загружает всё.
    public func bootstrap() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = ICloudPlaceholder.pendingFiles(in: directory, pathExtension: "md")
        if try markdownFiles().isEmpty, pending.isEmpty {
            for builtin in BuiltinProfiles.all {
                try builtin.contents.write(
                    to: directory.appending(path: "\(builtin.id).md"), atomically: true, encoding: .utf8
                )
            }
        }
        reload()
    }

    public func reload() {
        ICloudPlaceholder.pendingFiles(in: directory, pathExtension: "md").forEach(ICloudPlaceholder.requestDownload)
        let files = (try? markdownFiles()) ?? []
        entries = files.map { url in
            let id = url.deletingPathExtension().lastPathComponent
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                return .valid(try ProfileParser.parse(id: id, contents: text))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return .invalid(id: id, message: message)
            }
        }
    }

    public func selectNext() {
        let ids = validProfiles.map(\.id)
        guard !ids.isEmpty else { return }
        let current = ids.firstIndex(of: activeProfile.id) ?? -1
        activeProfileID = ids[(current + 1) % ids.count]
    }

    /// Следит за созданием, удалением и переименованием файлов в каталоге.
    /// Правку файла «на месте» (например, из VS Code) это не ловит, поэтому
    /// AppController дополнительно вызывает reload() перед каждой записью и при смене профиля.
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

    private func markdownFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

# OpenWhisper Settings & Profile Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Общие настройки (`settings.json`) и профили лежат в папке iCloud Drive и одинаковы на всех ноутбуках; ключ OpenRouter остаётся в Keychain каждой машины, но его можно показать и скопировать.

**Architecture:** В Core появляются `SharedSettings` (модель и терпимый JSON), `ICloudPlaceholder` (заглушки `.icloud`), `SyncLocation` (iCloud или `~/.config/openwhisper`), `SharedSettingsStore` (чтение, атомарная запись, наблюдение) и `SyncBootstrap` (переезд). `ProfileStore` учитывает заглушки. В приложении `AppSettings` проксирует общие поля в `SharedSettingsStore`, а локальные оставляет в `UserDefaults`; `SettingsView` получает работу с ключом и секцию «Синхронизация».

**Tech Stack:** Swift 6, Foundation (FileManager, JSONDecoder/Encoder, DispatchSource), SwiftUI, XCTest. Новых зависимостей нет.

**Spec:** `docs/superpowers/specs/2026-10-14-openwhisper-sync-design.md` (дополняет `docs/superpowers/specs/2026-10-14-openwhisper-design.md`)

## Global Constraints

- Общая папка: `~/Library/Mobile Documents/com~apple~CloudDocs/OpenWhisper/`, если существует `~/Library/Mobile Documents/com~apple~CloudDocs/`; иначе `~/.config/openwhisper/`. Выбирается при запуске.
- Файлы общей папки: `settings.json` и `profiles/*.md`.
- `settings.json`: ключи `version` (1), `default_transcription_model` («openai/gpt-4o-transcribe»), `default_llm_model` («openai/gpt-4.1-mini»), `audio_limit_gb` (1.0), `sounds_enabled` (true), `show_indicator` (true). Отсутствующее поле — значение по умолчанию; неизвестные поля игнорируются; неверный тип — файл битый; пустая модель — значение по умолчанию; `audio_limit_gb` < 0.1 → 0.1.
- Локально остаются: ключ (Keychain), микрофон (`inputDeviceUID`), «запускать при входе», горячие клавиши, активный профиль (`activeProfileID`), история и аудио.
- Ключи `UserDefaults` для переезда: `defaultTranscriptionModel`, `defaultLLMModel`, `audioLimitGB`, `soundsEnabled`, `showIndicator`.
- Переезд никогда не перезаписывает существующие файлы общей папки и не удаляет исходные.
- Читается только `settings.json`; `settings 2.json` и подобные игнорируются.
- Запись `settings.json` атомарная. Модели записываются по Enter или при потере фокуса.
- Ссылка на создание ключа: `https://openrouter.ai/settings/keys`.
- Swift language mode 6, macOS 15. Весь текст интерфейса на русском.
- Работа в ветке `feature/settings-sync`. Коммиты заканчиваются строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Сохранение без изменений не трогает файл.** Повторная запись того же значения (например, при потере фокуса поля модели) не должна перезаписывать `settings.json`, иначе iCloud будет гонять файл между машинами и плодить конфликтные копии. Тест в Task 3: `testUpdateWithoutChangesDoesNotRewriteFile`.
2. **`settings.json` с BOM** (сохранён редактором, который ставит BOM) должен читаться, а не помечаться битым. Тест в Task 1: `testDecodesUTF8BOM`.
3. **Папку `OpenWhisper` удалили в Finder при работающем приложении.** Следующее изменение настройки должно пересоздать папку и файл, а не упасть с ошибкой. Тест в Task 3: `testUpdateRecreatesDeletedDirectory`.
4. **В старой папке профилей лежит не только `.md`** (заметки, подпапки, `.DS_Store`). Переносить нужно только `.md`-файлы. Тест в Task 4: `testCopiesOnlyMarkdownProfiles`.
5. **Старый `~/.config/openwhisper/settings.json` битый.** Переезд должен перейти к следующему источнику (`UserDefaults`), а не остановиться и не скопировать мусор. Тест в Task 4: `testBrokenLegacySettingsFallsBackToUserDefaults`.

---

## File Structure

```
Core/Sources/OpenWhisperCore/Sync/
├── SharedSettings.swift        # модель, значения по умолчанию, decode/encode, переезд из UserDefaults
├── ICloudPlaceholder.swift     # распознавание заглушек .icloud и запрос скачивания
├── SyncLocation.swift          # выбор общей папки
├── SharedSettingsStore.swift   # @MainActor @Observable: reload/update/наблюдение
└── SyncBootstrap.swift         # переезд при запуске
Core/Sources/OpenWhisperCore/Profiles/ProfileStore.swift   # учёт заглушек
Core/Tests/OpenWhisperCoreTests/
├── SharedSettingsTests.swift
├── SyncLocationTests.swift     # + ICloudPlaceholder
├── SharedSettingsStoreTests.swift
├── SyncBootstrapTests.swift
└── ProfileStoreTests.swift     # + заглушки
App/Sources/AppSettings.swift          # общие поля через SharedSettingsStore
App/Sources/AppController.swift        # SyncLocation + SyncBootstrap + перечитывание
App/Sources/UI/SettingsView.swift      # ключ, модели по Enter/фокусу, секция «Синхронизация»
README.md                              # новые пути и пункты чек-листа
```

Все команды — из корня репозитория `~/dev/openwhisper`.

---

### Task 1: SharedSettings

**Files:**
- Create: `Core/Sources/OpenWhisperCore/Sync/SharedSettings.swift`
- Test: `Core/Tests/OpenWhisperCoreTests/SharedSettingsTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public struct SharedSettings: Equatable, Sendable` с полями `defaultTranscriptionModel: String`, `defaultLLMModel: String`, `audioLimitGB: Double`, `soundsEnabled: Bool`, `showIndicator: Bool`.
  - Статические члены: `fileName = "settings.json"`, `defaultTranscriptionModelID`, `defaultLLMModelID`, `minimumAudioLimitGB = 0.1`, `defaults`.
  - `init(defaultTranscriptionModel:defaultLLMModel:audioLimitGB:soundsEnabled:showIndicator:)` со значениями по умолчанию; `init(legacyDefaults: UserDefaults)`.
  - `var normalized: SharedSettings`, `static func decode(_ data: Data) throws -> SharedSettings`, `func encoded() throws -> Data`.
  - `public enum SharedSettingsError: Error, Equatable, LocalizedError { case invalidJSON(String) }`.

- [ ] **Step 1: Написать падающие тесты**

```swift
import XCTest
@testable import OpenWhisperCore

final class SharedSettingsTests: XCTestCase {
    func testDecodesFullFile() throws {
        let json = """
        {"version":1,"default_transcription_model":"a/stt","default_llm_model":"b/llm",
         "audio_limit_gb":2.5,"sounds_enabled":false,"show_indicator":false}
        """
        XCTAssertEqual(try SharedSettings.decode(Data(json.utf8)), SharedSettings(
            defaultTranscriptionModel: "a/stt", defaultLLMModel: "b/llm",
            audioLimitGB: 2.5, soundsEnabled: false, showIndicator: false
        ))
    }

    func testMissingFieldsUseDefaults() throws {
        XCTAssertEqual(try SharedSettings.decode(Data("{}".utf8)), .defaults)
        XCTAssertEqual(SharedSettings.defaults.defaultTranscriptionModel, "openai/gpt-4o-transcribe")
        XCTAssertEqual(SharedSettings.defaults.defaultLLMModel, "openai/gpt-4.1-mini")
        XCTAssertEqual(SharedSettings.defaults.audioLimitGB, 1.0)
        XCTAssertTrue(SharedSettings.defaults.soundsEnabled)
        XCTAssertTrue(SharedSettings.defaults.showIndicator)
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = #"{"sounds_enabled":false,"future_option":42,"nested":{"x":1}}"#
        XCTAssertFalse(try SharedSettings.decode(Data(json.utf8)).soundsEnabled)
    }

    func testBlankModelsAndTinyLimitAreNormalized() throws {
        let json = #"{"default_transcription_model":"  ","default_llm_model":"","audio_limit_gb":0.01}"#
        let settings = try SharedSettings.decode(Data(json.utf8))
        XCTAssertEqual(settings.defaultTranscriptionModel, SharedSettings.defaultTranscriptionModelID)
        XCTAssertEqual(settings.defaultLLMModel, SharedSettings.defaultLLMModelID)
        XCTAssertEqual(settings.audioLimitGB, 0.1)
    }

    func testModelsAreTrimmed() throws {
        let json = #"{"default_llm_model":"  x/y \n"}"#
        XCTAssertEqual(try SharedSettings.decode(Data(json.utf8)).defaultLLMModel, "x/y")
    }

    func testWrongTypeIsInvalid() {
        let json = #"{"audio_limit_gb":"много"}"#
        XCTAssertThrowsError(try SharedSettings.decode(Data(json.utf8))) {
            guard case .invalidJSON(let message) = $0 as? SharedSettingsError else { return XCTFail("\($0)") }
            XCTAssertTrue(message.contains("audio_limit_gb"), message)
        }
    }

    func testBrokenJSONIsInvalid() {
        for text in ["", "{", "[1,2]", #"{"sounds_enabled":true,}"#] {
            XCTAssertThrowsError(try SharedSettings.decode(Data(text.utf8)), text) {
                guard case .invalidJSON = $0 as? SharedSettingsError else { return XCTFail("\($0)") }
            }
        }
    }

    func testDecodesUTF8BOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(#"{"sounds_enabled":false}"#.utf8)
        XCTAssertFalse(try SharedSettings.decode(data).soundsEnabled)
    }

    func testEncodeRoundTripWithSnakeCaseAndVersion() throws {
        let settings = SharedSettings(defaultLLMModel: "x/y", audioLimitGB: 3, soundsEnabled: false)
        let data = try settings.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["default_llm_model"] as? String, "x/y")
        XCTAssertEqual(object["sounds_enabled"] as? Bool, false)
        XCTAssertEqual(try SharedSettings.decode(data), settings)
    }

    func testLegacyDefaultsMigration() {
        let defaults = UserDefaults(suiteName: "ow-legacy-\(UUID().uuidString)")!
        XCTAssertEqual(SharedSettings(legacyDefaults: defaults), .defaults)
        defaults.set("old/stt", forKey: "defaultTranscriptionModel")
        defaults.set("old/llm", forKey: "defaultLLMModel")
        defaults.set(4.0, forKey: "audioLimitGB")
        defaults.set(false, forKey: "soundsEnabled")
        defaults.set(false, forKey: "showIndicator")
        XCTAssertEqual(SharedSettings(legacyDefaults: defaults), SharedSettings(
            defaultTranscriptionModel: "old/stt", defaultLLMModel: "old/llm",
            audioLimitGB: 4, soundsEnabled: false, showIndicator: false
        ))
    }
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `swift test --package-path Core --disable-swift-testing --filter SharedSettingsTests`
Expected: ошибка компиляции `cannot find 'SharedSettings' in scope`.

- [ ] **Step 3: Реализовать `Sync/SharedSettings.swift`**

```swift
import Foundation

public enum SharedSettingsError: Error, Equatable, LocalizedError {
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let message): "Ошибка в settings.json: \(message)"
        }
    }
}

/// Настройки, общие для всех машин (файл settings.json в общей папке).
public struct SharedSettings: Equatable, Sendable {
    public static let fileName = "settings.json"
    public static let defaultTranscriptionModelID = "openai/gpt-4o-transcribe"
    public static let defaultLLMModelID = "openai/gpt-4.1-mini"
    public static let minimumAudioLimitGB = 0.1
    public static let defaults = SharedSettings()

    public var defaultTranscriptionModel: String
    public var defaultLLMModel: String
    public var audioLimitGB: Double
    public var soundsEnabled: Bool
    public var showIndicator: Bool

    public init(
        defaultTranscriptionModel: String = SharedSettings.defaultTranscriptionModelID,
        defaultLLMModel: String = SharedSettings.defaultLLMModelID,
        audioLimitGB: Double = 1.0,
        soundsEnabled: Bool = true,
        showIndicator: Bool = true
    ) {
        self.defaultTranscriptionModel = defaultTranscriptionModel
        self.defaultLLMModel = defaultLLMModel
        self.audioLimitGB = audioLimitGB
        self.soundsEnabled = soundsEnabled
        self.showIndicator = showIndicator
    }

    /// Значения, которые v1 хранил в UserDefaults.
    public init(legacyDefaults defaults: UserDefaults) {
        self.init(
            defaultTranscriptionModel: defaults.string(forKey: "defaultTranscriptionModel") ?? Self.defaultTranscriptionModelID,
            defaultLLMModel: defaults.string(forKey: "defaultLLMModel") ?? Self.defaultLLMModelID,
            audioLimitGB: defaults.object(forKey: "audioLimitGB") as? Double ?? 1.0,
            soundsEnabled: defaults.object(forKey: "soundsEnabled") as? Bool ?? true,
            showIndicator: defaults.object(forKey: "showIndicator") as? Bool ?? true
        )
        self = normalized
    }

    public var normalized: SharedSettings {
        var result = self
        let stt = defaultTranscriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let llm = defaultLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
        result.defaultTranscriptionModel = stt.isEmpty ? Self.defaultTranscriptionModelID : stt
        result.defaultLLMModel = llm.isEmpty ? Self.defaultLLMModelID : llm
        result.audioLimitGB = max(audioLimitGB, Self.minimumAudioLimitGB)
        return result
    }

    private struct FileFormat: Codable {
        var version: Int?
        var defaultTranscriptionModel: String?
        var defaultLLMModel: String?
        var audioLimitGB: Double?
        var soundsEnabled: Bool?
        var showIndicator: Bool?

        enum CodingKeys: String, CodingKey {
            case version
            case defaultTranscriptionModel = "default_transcription_model"
            case defaultLLMModel = "default_llm_model"
            case audioLimitGB = "audio_limit_gb"
            case soundsEnabled = "sounds_enabled"
            case showIndicator = "show_indicator"
        }
    }

    public static func decode(_ data: Data) throws -> SharedSettings {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        let file: FileFormat
        do {
            file = try JSONDecoder().decode(FileFormat.self, from: data)
        } catch {
            throw SharedSettingsError.invalidJSON(describe(error))
        }
        return SharedSettings(
            defaultTranscriptionModel: file.defaultTranscriptionModel ?? defaultTranscriptionModelID,
            defaultLLMModel: file.defaultLLMModel ?? defaultLLMModelID,
            audioLimitGB: file.audioLimitGB ?? 1.0,
            soundsEnabled: file.soundsEnabled ?? true,
            showIndicator: file.showIndicator ?? true
        ).normalized
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(FileFormat(
            version: 1,
            defaultTranscriptionModel: defaultTranscriptionModel,
            defaultLLMModel: defaultLLMModel,
            audioLimitGB: audioLimitGB,
            soundsEnabled: soundsEnabled,
            showIndicator: showIndicator
        ))
    }

    private static func describe(_ error: Error) -> String {
        let context: DecodingError.Context?
        switch error as? DecodingError {
        case .typeMismatch(_, let ctx)?, .valueNotFound(_, let ctx)?, .keyNotFound(_, let ctx)?, .dataCorrupted(let ctx)?:
            context = ctx
        default:
            context = nil
        }
        guard let context else { return error.localizedDescription }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }
}
```

- [ ] **Step 4: Запустить тесты**

Run: `swift test --package-path Core --disable-swift-testing --filter SharedSettingsTests`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Add SharedSettings model with tolerant settings.json decoding

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ICloudPlaceholder и SyncLocation

**Files:**
- Create: `Core/Sources/OpenWhisperCore/Sync/ICloudPlaceholder.swift`
- Create: `Core/Sources/OpenWhisperCore/Sync/SyncLocation.swift`
- Test: `Core/Tests/OpenWhisperCoreTests/SyncLocationTests.swift`

**Interfaces:**
- Consumes: `SharedSettings.fileName` (Task 1).
- Produces:
  - `public enum ICloudPlaceholder` со статическими методами `placeholderURL(for: URL) -> URL`, `isPending(_ url: URL) -> Bool`, `pendingFiles(in directory: URL, pathExtension: String) -> [URL]`, `requestDownload(_ url: URL)`.
  - `public struct SyncLocation: Equatable, Sendable` с полями `directory: URL`, `isICloud: Bool`, вычисляемыми `profilesDirectory`, `settingsURL`; статическими `defaultICloudRoot`, `defaultLocalDirectory`; `static func resolve(iCloudRoot: URL = defaultICloudRoot, localDirectory: URL = defaultLocalDirectory) -> SyncLocation`.

- [ ] **Step 1: Написать падающие тесты**

```swift
import XCTest
@testable import OpenWhisperCore

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
        XCTAssertEqual(location.directory.path, iCloud.appending(path: "OpenWhisper").path)
        XCTAssertEqual(location.profilesDirectory.path, iCloud.appending(path: "OpenWhisper/profiles").path)
        XCTAssertEqual(location.settingsURL.path, iCloud.appending(path: "OpenWhisper/settings.json").path)
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
        XCTAssertEqual(SyncLocation.defaultLocalDirectory.path, home + "/.config/openwhisper")
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
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `swift test --package-path Core --disable-swift-testing --filter SyncLocationTests`
Expected: ошибка компиляции `cannot find 'SyncLocation' in scope`.

- [ ] **Step 3: Реализовать `Sync/ICloudPlaceholder.swift`**

```swift
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
```

- [ ] **Step 4: Реализовать `Sync/SyncLocation.swift`**

```swift
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
            .appending(path: ".config/openwhisper", directoryHint: .isDirectory)
    }

    public static func resolve(
        iCloudRoot: URL = SyncLocation.defaultICloudRoot,
        localDirectory: URL = SyncLocation.defaultLocalDirectory
    ) -> SyncLocation {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: iCloudRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return SyncLocation(
                directory: iCloudRoot.appending(path: "OpenWhisper", directoryHint: .isDirectory), isICloud: true
            )
        }
        return SyncLocation(directory: localDirectory, isICloud: false)
    }
}
```

- [ ] **Step 5: Запустить тесты**

Run: `swift test --package-path Core --disable-swift-testing --filter SyncLocationTests`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Core
git commit -m "Add sync location resolution and iCloud placeholder helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: SharedSettingsStore

**Files:**
- Create: `Core/Sources/OpenWhisperCore/Sync/SharedSettingsStore.swift`
- Test: `Core/Tests/OpenWhisperCoreTests/SharedSettingsStoreTests.swift`

**Interfaces:**
- Consumes: `SharedSettings`, `SharedSettingsError` (Task 1); `ICloudPlaceholder` (Task 2).
- Produces: `@MainActor @Observable public final class SharedSettingsStore` с API:
  - `init(directory: URL, initial: SharedSettings = .defaults)`, `let directory: URL`, `var fileURL: URL`;
  - `private(set) var settings: SharedSettings`, `private(set) var loadError: String?`;
  - `func reload()`, `func update(_ change: (inout SharedSettings) -> Void) throws`, `func startWatching()`.

- [ ] **Step 1: Написать падающие тесты**

```swift
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
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `swift test --package-path Core --disable-swift-testing --filter SharedSettingsStoreTests`
Expected: ошибка компиляции `cannot find 'SharedSettingsStore' in scope`.

- [ ] **Step 3: Реализовать `Sync/SharedSettingsStore.swift`**

```swift
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
```

- [ ] **Step 4: Запустить тесты**

Run: `swift test --package-path Core --disable-swift-testing --filter SharedSettingsStoreTests`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Add SharedSettingsStore with atomic writes and last-good fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: SyncBootstrap

**Files:**
- Create: `Core/Sources/OpenWhisperCore/Sync/SyncBootstrap.swift`
- Test: `Core/Tests/OpenWhisperCoreTests/SyncBootstrapTests.swift`

**Interfaces:**
- Consumes: `SharedSettings` (Task 1); `ICloudPlaceholder`, `SyncLocation` (Task 2).
- Produces: `public enum SyncBootstrap { static func run(location: SyncLocation, legacyDirectory: URL, legacyDefaults: UserDefaults) throws }`.

- [ ] **Step 1: Написать падающие тесты**

```swift
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
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `swift test --package-path Core --disable-swift-testing --filter SyncBootstrapTests`
Expected: ошибка компиляции `cannot find 'SyncBootstrap' in scope`.

- [ ] **Step 3: Реализовать `Sync/SyncBootstrap.swift`**

```swift
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
```

- [ ] **Step 4: Запустить тесты**

Run: `swift test --package-path Core --disable-swift-testing --filter SyncBootstrapTests`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Add sync bootstrap that migrates settings and profiles once

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: ProfileStore и заглушки iCloud

**Files:**
- Modify: `Core/Sources/OpenWhisperCore/Profiles/ProfileStore.swift` (методы `bootstrap()` и `reload()`)
- Test: `Core/Tests/OpenWhisperCoreTests/ProfileStoreTests.swift` (добавить тесты в конец класса)

**Interfaces:**
- Consumes: `ICloudPlaceholder.pendingFiles(in:pathExtension:)`, `ICloudPlaceholder.requestDownload(_:)` (Task 2).
- Produces: API `ProfileStore` не меняется. Новое поведение: `bootstrap()` не создаёт встроенные профили, пока в каталоге есть заглушки `.md.icloud`; `reload()` запрашивает скачивание заглушек; заглушки не попадают в `entries`.

- [ ] **Step 1: Добавить падающие тесты в конец `ProfileStoreTests`** (перед закрывающей скобкой класса)

```swift
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
```

- [ ] **Step 2: Запустить и убедиться, что первый тест падает**

Run: `swift test --package-path Core --disable-swift-testing --filter ProfileStoreTests`
Expected: `testBootstrapDoesNotCreateBuiltinsWhileProfilesArePending` падает (созданы `raw.md` и `clean.md`); остальные тесты проходят.

- [ ] **Step 3: Изменить `bootstrap()` и `reload()` в `ProfileStore.swift`**

Заменить тело `bootstrap()`:

```swift
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
```

Добавить первой строкой в `reload()`:

```swift
        ICloudPlaceholder.pendingFiles(in: directory, pathExtension: "md").forEach(ICloudPlaceholder.requestDownload)
```

Обновить комментарий к `bootstrap()`:

```swift
    /// Создаёт каталог; если в нём нет ни одного .md и ни одной заглушки iCloud, кладёт встроенные профили.
    /// Затем загружает всё.
```

- [ ] **Step 4: Запустить все тесты Core**

Run: `swift test --package-path Core --disable-swift-testing`
Expected: `0 failures`; всего 141 тест (99 прежних + 10 + 7 + 11 + 11 + 3).

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Respect pending iCloud placeholders in ProfileStore

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: AppSettings и AppController на общей папке

Слой приложения: модульных тестов нет, критерий — сборка без ошибок и ручная проверка в Task 7.

**Files:**
- Modify: `App/Sources/AppSettings.swift` (заменить целиком)
- Modify: `App/Sources/AppController.swift` (`init()` и `startRecording()`)

**Interfaces:**
- Consumes: `SharedSettingsStore` (Task 3), `SyncLocation`, `SyncBootstrap` (Tasks 2, 4), `ProfileStore(directory:defaults:)`.
- Produces: `@MainActor @Observable final class AppSettings` с API:
  - `init(shared: SharedSettingsStore, syncLocation: SyncLocation, startupError: String?, defaults: UserDefaults = .standard)`;
  - `let shared: SharedSettingsStore`, `let syncLocation: SyncLocation`, `private(set) var saveError: String?`;
  - общие `defaultTranscriptionModel`, `defaultLLMModel: String`, `audioLimitGB: Double`, `soundsEnabled`, `showIndicator: Bool` (get/set через `shared`);
  - локальный `inputDeviceUID: String`;
  - `pipelineConfig: PipelineConfig`.

- [ ] **Step 1: Заменить `App/Sources/AppSettings.swift`**

```swift
import Foundation
import Observation
import OpenWhisperCore

@MainActor
@Observable
final class AppSettings {
    let shared: SharedSettingsStore
    let syncLocation: SyncLocation
    /// Ошибка подготовки или записи общей папки; показывается в настройках.
    private(set) var saveError: String?

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Общие (settings.json в общей папке)

    var defaultTranscriptionModel: String {
        get { shared.settings.defaultTranscriptionModel }
        set { updateShared { $0.defaultTranscriptionModel = newValue } }
    }
    var defaultLLMModel: String {
        get { shared.settings.defaultLLMModel }
        set { updateShared { $0.defaultLLMModel = newValue } }
    }
    var audioLimitGB: Double {
        get { shared.settings.audioLimitGB }
        set { updateShared { $0.audioLimitGB = newValue } }
    }
    var soundsEnabled: Bool {
        get { shared.settings.soundsEnabled }
        set { updateShared { $0.soundsEnabled = newValue } }
    }
    var showIndicator: Bool {
        get { shared.settings.showIndicator }
        set { updateShared { $0.showIndicator = newValue } }
    }

    // MARK: Локальные (UserDefaults этой машины)

    /// uniqueID микрофона; пустая строка — системный по умолчанию.
    var inputDeviceUID: String {
        didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDeviceUID) }
    }

    private enum Keys {
        static let inputDeviceUID = "inputDeviceUID"
    }

    init(shared: SharedSettingsStore, syncLocation: SyncLocation, startupError: String?, defaults: UserDefaults = .standard) {
        self.shared = shared
        self.syncLocation = syncLocation
        self.saveError = startupError
        self.defaults = defaults
        self.inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID) ?? ""
    }

    var pipelineConfig: PipelineConfig {
        PipelineConfig(
            defaultTranscriptionModel: defaultTranscriptionModel,
            defaultLLMModel: defaultLLMModel,
            audioLimitBytes: Int64(audioLimitGB * 1_073_741_824)
        )
    }

    private func updateShared(_ change: (inout SharedSettings) -> Void) {
        do {
            try shared.update(change)
            saveError = nil
        } catch {
            saveError = "Не удалось сохранить settings.json: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Изменить `AppController.init()`**

Заменить строки

```swift
        let settings = AppSettings()
        let profiles = ProfileStore(directory: ProfileStore.defaultDirectory, defaults: .standard)
```

на

```swift
        let location = SyncLocation.resolve()
        var startupError: String?
        do {
            try SyncBootstrap.run(
                location: location, legacyDirectory: SyncLocation.defaultLocalDirectory, legacyDefaults: .standard
            )
        } catch {
            startupError = "Не удалось подготовить папку синхронизации: \(error.localizedDescription)"
        }
        let sharedSettings = SharedSettingsStore(directory: location.directory)
        sharedSettings.reload()
        sharedSettings.startWatching()
        let settings = AppSettings(shared: sharedSettings, syncLocation: location, startupError: startupError)
        let profiles = ProfileStore(directory: location.profilesDirectory, defaults: .standard)
```

- [ ] **Step 3: Перечитывать общие настройки перед записью**

В `startRecording()` заменить строку

```swift
        profiles.reload()
        let profile = profiles.activeProfile
```

на

```swift
        settings.shared.reload()
        profiles.reload()
        let profile = profiles.activeProfile
```

- [ ] **Step 4: Собрать**

Run: `make build && echo BUILD-OK`
Expected: `BUILD-OK`, без предупреждений. Старый `SettingsView` компилируется без изменений: общие поля `AppSettings` — вычисляемые свойства с `set`, поэтому `$settings.defaultTranscriptionModel` и остальные биндинги работают (до Task 7 модели пишутся на каждый символ).

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Back shared app settings with settings.json in the sync folder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Окно настроек и README

**Files:**
- Modify: `App/Sources/UI/SettingsView.swift` (заменить целиком)
- Modify: `README.md` (разделы «Профили», «Данные», чек-лист)

**Interfaces:**
- Consumes: `AppSettings` (Task 6): `shared`, `syncLocation`, `saveError`, общие и локальные поля; `KeychainStore.read()/save(_:)`, `Permissions`, `AudioInputDevice.all()`, `AppController.client/audio/profiles/settings`.
- Produces: `struct SettingsView: View { init(controller: AppController) }` (как раньше).

- [ ] **Step 1: Заменить `App/Sources/UI/SettingsView.swift`**

```swift
import KeyboardShortcuts
import OpenWhisperCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var apiKey = KeychainStore.read() ?? ""
    @State private var showKey = false
    @State private var keyStatus = ""
    @State private var transcriptionModel = ""
    @State private var llmModel = ""
    @FocusState private var focusedModel: ModelField?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var audioUsage = ""
    @State private var microphoneGranted = Permissions.microphone == .authorized
    @State private var accessibilityGranted = Permissions.accessibilityGranted
    @State private var inputDevices = AudioInputDevice.all()

    private enum ModelField {
        case transcription
        case llm
    }

    private static let createKeyURL = URL(string: "https://openrouter.ai/settings/keys")!

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section("OpenRouter") {
                HStack {
                    if showKey {
                        TextField("API-ключ", text: $apiKey)
                    } else {
                        SecureField("API-ключ", text: $apiKey)
                    }
                    Button(showKey ? "Скрыть" : "Показать") { showKey.toggle() }
                }
                HStack {
                    Button("Сохранить") {
                        KeychainStore.save(apiKey)
                        keyStatus = apiKey.isEmpty ? "Ключ удалён" : "Сохранено"
                    }
                    Button("Проверить") { Task { await checkKey() } }
                    Button("Скопировать") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(apiKey, forType: .string)
                        keyStatus = "Скопировано"
                    }
                    .disabled(apiKey.isEmpty)
                    Text(keyStatus).foregroundStyle(.secondary)
                }
                Link("Создать ключ на OpenRouter", destination: Self.createKeyURL)
                Text("Ключ хранится только на этой машине. На другом ноутбуке вставьте его один раз или создайте отдельный.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Модель распознавания", text: $transcriptionModel)
                    .focused($focusedModel, equals: .transcription)
                    .onSubmit(commitModels)
                TextField("Модель постобработки", text: $llmModel)
                    .focused($focusedModel, equals: .llm)
                    .onSubmit(commitModels)
            }

            Section("Горячие клавиши") {
                KeyboardShortcuts.Recorder("Запись:", name: .record)
                KeyboardShortcuts.Recorder("Следующий профиль:", name: .nextProfile)
            }

            Section("Аудио") {
                Picker("Микрофон", selection: $settings.inputDeviceUID) {
                    Text("Системный по умолчанию").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                    if !settings.inputDeviceUID.isEmpty,
                       !inputDevices.contains(where: { $0.id == settings.inputDeviceUID }) {
                        Text("Отключён — используется системный").tag(settings.inputDeviceUID)
                    }
                }
                Text("С Bluetooth-наушниками выберите встроенный микрофон: запись будет чище, а звук в наушниках не будет прерываться.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $settings.audioLimitGB, in: 0.1...50, step: 0.5) {
                    Text("Лимит: \(settings.audioLimitGB, specifier: "%.1f") ГБ")
                }
                Text("Занято: \(audioUsage)").foregroundStyle(.secondary)
                Toggle("Звуки начала и конца записи", isOn: $settings.soundsEnabled)
                Toggle("Индикатор записи вверху экрана", isOn: $settings.showIndicator)
            }

            Section("Синхронизация") {
                if settings.syncLocation.isICloud {
                    Text("Общие настройки и профили — в iCloud Drive → OpenWhisper")
                } else {
                    Text("Синхронизация выключена: iCloud Drive недоступен. Файлы — в ~/.config/openwhisper")
                        .foregroundStyle(.orange)
                }
                Text("Микрофон, горячие клавиши, активный профиль, ключ и история — свои на каждой машине.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let loadError = settings.shared.loadError {
                    Text("\(loadError). Используются последние корректные значения; любое изменение здесь перезапишет файл.")
                        .foregroundStyle(.red)
                }
                if let saveError = settings.saveError {
                    Text(saveError).foregroundStyle(.red)
                }
                Button("Открыть папку") { NSWorkspace.shared.open(settings.syncLocation.directory) }
            }

            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                HStack {
                    Text(microphoneGranted ? "✓ Микрофон" : "✗ Микрофон")
                    Spacer()
                    Button("Открыть настройки") { Permissions.openMicrophoneSettings() }
                }
                HStack {
                    Text(accessibilityGranted ? "✓ Accessibility (вставка текста)" : "✗ Accessibility (вставка текста)")
                    Spacer()
                    Button("Запросить") {
                        Permissions.promptAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
                Button("Открыть папку профилей") {
                    NSWorkspace.shared.open(controller.profiles.directory)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onChange(of: focusedModel) { _, _ in commitModels() }
        .onChange(of: settings.defaultTranscriptionModel) { _, value in
            if focusedModel != .transcription { transcriptionModel = value }
        }
        .onChange(of: settings.defaultLLMModel) { _, value in
            if focusedModel != .llm { llmModel = value }
        }
    }

    private func refresh() {
        controller.settings.shared.reload()
        transcriptionModel = controller.settings.defaultTranscriptionModel
        llmModel = controller.settings.defaultLLMModel
        audioUsage = ByteCountFormatter.string(fromByteCount: controller.audio.totalSize(), countStyle: .file)
        microphoneGranted = Permissions.microphone == .authorized
        accessibilityGranted = Permissions.accessibilityGranted
        inputDevices = AudioInputDevice.all()
    }

    /// Записывает модели только если текст отличается: SharedSettingsStore не трогает файл без изменений.
    private func commitModels() {
        let settings = controller.settings
        if transcriptionModel != settings.defaultTranscriptionModel {
            settings.defaultTranscriptionModel = transcriptionModel
            transcriptionModel = settings.defaultTranscriptionModel
        }
        if llmModel != settings.defaultLLMModel {
            settings.defaultLLMModel = llmModel
            llmModel = settings.defaultLLMModel
        }
    }

    private func checkKey() async {
        KeychainStore.save(apiKey)
        keyStatus = "Проверяю…"
        do {
            try await controller.client.checkKey()
            keyStatus = "✓ Ключ работает"
        } catch {
            keyStatus = "✗ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

- [ ] **Step 2: Собрать и установить**

Run: `make install`
Expected: сборка без ошибок и предупреждений, приложение запущено.

- [ ] **Step 3: Обновить README**

В разделе «Профили» заменить первую строку

```markdown
Файлы `~/.config/openwhisper/profiles/*.md`. Имя файла — id профиля.
```

на

```markdown
Файлы `iCloud Drive/OpenWhisper/profiles/*.md` (без iCloud Drive — `~/.config/openwhisper/profiles/`).
Имя файла — id профиля. Профили и `settings.json` в той же папке общие для всех ваших Mac.
```

В разделе «Данные» добавить первой строкой списка

```markdown
- Общие настройки: `iCloud Drive/OpenWhisper/settings.json` (модели, лимит аудио, звуки, индикатор)
```

и заменить строку про ключ на

```markdown
- Ключ: Keychain этой машины, service `dev.saldin.openwhisper` (не синхронизируется: «Настройки… → Показать/Скопировать»)
```

В «Ручной чек-лист приёмки» добавить в конец

```markdown
- [ ] Первый запуск новой версии: в «iCloud Drive → OpenWhisper» появились `settings.json` с текущими моделями и прежние профили.
- [ ] «Показать» и «Скопировать» ключа работают; ссылка «Создать ключ на OpenRouter» открывается.
- [ ] Модель, изменённая в настройках, записывается по Enter или при уходе из поля, а не на каждую букву.
- [ ] Второй ноутбук после установки получает те же профили и модели; изменение на одном видно на другом без перезапуска.
- [ ] Битый `settings.json` (например, удалить закрывающую скобку): приложение работает, в настройках красное предупреждение.
```

- [ ] **Step 4: Проверка**

Run: `swift test --package-path Core --disable-swift-testing 2>&1 | grep Executed | tail -1 && make build && echo ALL-OK`
Expected: `Executed 141 tests, with 0 failures` и `ALL-OK`.

Вручную на этой машине:
1. `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/OpenWhisper/` → `profiles settings.json`; `cat` файла показывает ваши текущие модели.
2. `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/OpenWhisper/profiles/` → прежние `*.md`.
3. В меню те же профили, активный профиль не сбросился.

- [ ] **Step 5: Commit**

```bash
git add App README.md
git commit -m "Add key reveal/copy, sync status and deferred model saving to settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

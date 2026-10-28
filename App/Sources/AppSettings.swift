import Foundation
import Observation
import QuillCore

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

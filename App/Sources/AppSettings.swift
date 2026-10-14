import Foundation
import Observation
import OpenWhisperCore

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var defaultTranscriptionModel: String {
        didSet { defaults.set(defaultTranscriptionModel, forKey: Keys.transcriptionModel) }
    }
    var defaultLLMModel: String {
        didSet { defaults.set(defaultLLMModel, forKey: Keys.llmModel) }
    }
    var audioLimitGB: Double {
        didSet { defaults.set(audioLimitGB, forKey: Keys.audioLimitGB) }
    }
    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.soundsEnabled) }
    }

    private enum Keys {
        static let transcriptionModel = "defaultTranscriptionModel"
        static let llmModel = "defaultLLMModel"
        static let audioLimitGB = "audioLimitGB"
        static let soundsEnabled = "soundsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.transcriptionModel: "openai/gpt-4o-transcribe",
            Keys.llmModel: "openai/gpt-4.1-mini",
            Keys.audioLimitGB: 1.0,
            Keys.soundsEnabled: true,
        ])
        defaultTranscriptionModel = defaults.string(forKey: Keys.transcriptionModel) ?? "openai/gpt-4o-transcribe"
        defaultLLMModel = defaults.string(forKey: Keys.llmModel) ?? "openai/gpt-4.1-mini"
        audioLimitGB = defaults.double(forKey: Keys.audioLimitGB)
        soundsEnabled = defaults.bool(forKey: Keys.soundsEnabled)
    }

    var pipelineConfig: PipelineConfig {
        PipelineConfig(
            defaultTranscriptionModel: defaultTranscriptionModel,
            defaultLLMModel: defaultLLMModel,
            audioLimitBytes: Int64(max(audioLimitGB, 0.1) * 1_073_741_824)
        )
    }
}

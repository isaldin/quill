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

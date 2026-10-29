import Foundation

public protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, model: String, language: String?) async throws -> TranscriptionResult
}

public protocol PostProcessor: Sendable {
    func process(rawText: String, profile: Profile, model: String) async throws -> ChatResult
}

public enum InsertOutcome: Equatable, Sendable {
    case pasted
    case copiedToClipboard
}

@MainActor
public protocol Inserter: AnyObject {
    func insert(_ text: String) async -> InsertOutcome
}

@MainActor
public protocol Notifier: AnyObject {
    func notify(_ notice: Notice)
}

public enum Notice: Equatable, Sendable {
    case transcriptionFailed(String)
    case postprocessFailed(String)
    case emptyTranscript
    case copiedToClipboard
    case needsAPIKey
    case paymentRequired
    case storageFailed(String)
    case microphoneDenied
    case recordingFailed(String)
    case silentInput(String)

    public var message: String {
        switch self {
        case .transcriptionFailed(let reason): "Не удалось распознать: \(reason). Повторите из истории."
        case .postprocessFailed(let reason): "Постобработка не удалась (\(reason)), использован сырой текст."
        case .emptyTranscript: "Речь не распознана: пустая расшифровка."
        case .copiedToClipboard: "Нет доступа к Accessibility: текст в буфере обмена, нажмите ⌘V."
        case .needsAPIKey: "Задайте ключ OpenRouter в настройках."
        case .paymentRequired: "На OpenRouter закончились средства, пополните баланс."
        case .storageFailed(let reason): "Ошибка записи в историю: \(reason)"
        case .microphoneDenied: "Нет доступа к микрофону. Разрешите его в Системных настройках."
        case .recordingFailed(let reason): "Не удалось начать запись: \(reason)"
        case .silentInput(let device): "Микрофон «\(device)» не передал звук. Проверьте микрофон в настройках; аудио сохранено в истории."
        }
    }

    /// Короткая причина для записи в истории.
    public var recordError: String {
        switch self {
        case .silentInput(let device): "Микрофон «\(device)» не передал звук"
        default: message
        }
    }
}

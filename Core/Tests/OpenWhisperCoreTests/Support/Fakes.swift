import Foundation
@testable import OpenWhisperCore

final class FakeTranscriber: Transcriber, @unchecked Sendable {
    var result: Result<TranscriptionResult, Error> = .success(TranscriptionResult(text: "сырой текст", costUSD: 0.001))
    var onCall: (() -> Void)?
    private(set) var calls: [(url: URL, model: String, language: String?)] = []

    func transcribe(audioURL: URL, model: String, language: String?) async throws -> TranscriptionResult {
        calls.append((audioURL, model, language))
        onCall?()
        return try result.get()
    }
}

final class FakePostProcessor: PostProcessor, @unchecked Sendable {
    var result: Result<ChatResult, Error> = .success(ChatResult(text: "Итоговый текст.", costUSD: 0.0005))
    private(set) var calls: [(raw: String, profileID: String, model: String)] = []

    func process(rawText: String, profile: Profile, model: String) async throws -> ChatResult {
        calls.append((rawText, profile.id, model))
        return try result.get()
    }
}

@MainActor
final class FakeInserter: Inserter {
    var outcome: InsertOutcome = .pasted
    private(set) var inserted: [String] = []

    func insert(_ text: String) async -> InsertOutcome {
        inserted.append(text)
        return outcome
    }
}

@MainActor
final class FakeNotifier: Notifier {
    private(set) var notices: [Notice] = []

    func notify(_ notice: Notice) {
        notices.append(notice)
    }
}

/// Пробрасывает значение из nonisolated-замыкания фейка в тест.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

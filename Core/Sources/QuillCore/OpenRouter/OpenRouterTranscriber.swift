import Foundation

public struct OpenRouterTranscriber: Transcriber {
    private let client: OpenRouterClient

    public init(client: OpenRouterClient) {
        self.client = client
    }

    public func transcribe(audioURL: URL, model: String, language: String?) async throws -> TranscriptionResult {
        let audio = try Data(contentsOf: audioURL)
        let result = try await client.transcribe(
            audio: audio, format: audioURL.pathExtension.lowercased(), model: model, language: language
        )
        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            costUSD: result.costUSD
        )
    }
}

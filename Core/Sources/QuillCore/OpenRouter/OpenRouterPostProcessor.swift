import Foundation

public struct OpenRouterPostProcessor: PostProcessor {
    private let client: OpenRouterClient

    public init(client: OpenRouterClient) {
        self.client = client
    }

    public func process(rawText: String, profile: Profile, model: String) async throws -> ChatResult {
        let result = try await client.chat(
            model: model, messages: PromptBuilder.messages(rawText: rawText, profile: profile)
        )
        return ChatResult(text: Self.clean(result.text), costUSD: result.costUSD)
    }

    /// Модели иногда повторяют обёртку <transcript>; срезаем её только по краям ответа.
    public static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = "<transcript>"
        let close = "</transcript>"
        if result.hasPrefix(open) { result.removeFirst(open.count) }
        if result.hasSuffix(close) { result.removeLast(close.count) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

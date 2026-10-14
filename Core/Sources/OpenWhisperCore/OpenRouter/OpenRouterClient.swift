import Foundation

public enum OpenRouterError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case unauthorized
    case paymentRequired
    case rateLimited
    case timeout
    case server(status: Int, message: String)
    case network(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "ключ OpenRouter не задан"
        case .unauthorized: "ключ OpenRouter неверный (401)"
        case .paymentRequired: "недостаточно средств на OpenRouter (402)"
        case .rateLimited: "слишком много запросов (429)"
        case .timeout: "превышено время ожидания"
        case .server(let status, let message): "ошибка сервера \(status): \(message)"
        case .network(let message): "нет сети: \(message)"
        case .invalidResponse(let message): "неожиданный ответ: \(message)"
        }
    }
}

public struct TranscriptionResult: Equatable, Sendable {
    public let text: String
    public let costUSD: Double

    public init(text: String, costUSD: Double) {
        self.text = text
        self.costUSD = costUSD
    }
}

public struct ChatResult: Equatable, Sendable {
    public let text: String
    public let costUSD: Double

    public init(text: String, costUSD: Double) {
        self.text = text
        self.costUSD = costUSD
    }
}

public struct OpenRouterClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    private let baseURL: URL
    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    public init(
        baseURL: URL = OpenRouterClient.defaultBaseURL,
        session: URLSession = .shared,
        apiKey: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.apiKey = apiKey
    }

    private struct Usage: Decodable {
        let cost: Double?
    }

    public func transcribe(
        audio: Data, format: String, model: String, language: String?, timeout: TimeInterval = 60
    ) async throws -> TranscriptionResult {
        struct Body: Encodable {
            struct Audio: Encodable {
                let data: String
                let format: String
            }
            let model: String
            let input_audio: Audio
            let language: String?
        }
        struct Response: Decodable {
            let text: String
            let usage: Usage?
        }
        let body = Body(
            model: model,
            input_audio: .init(data: audio.base64EncodedString(), format: format),
            language: language
        )
        let response: Response = try await post("audio/transcriptions", body: body, timeout: timeout)
        return TranscriptionResult(text: response.text, costUSD: response.usage?.cost ?? 0)
    }

    public func chat(model: String, messages: [ChatMessage], timeout: TimeInterval = 30) async throws -> ChatResult {
        struct Body: Encodable {
            struct UsageFlag: Encodable {
                let include: Bool
            }
            let model: String
            let messages: [ChatMessage]
            let usage: UsageFlag
        }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
            let usage: Usage?
        }
        let body = Body(model: model, messages: messages, usage: .init(include: true))
        let response: Response = try await post("chat/completions", body: body, timeout: timeout)
        guard let content = response.choices.first?.message.content else {
            throw OpenRouterError.invalidResponse("пустой ответ модели")
        }
        return ChatResult(text: content, costUSD: response.usage?.cost ?? 0)
    }

    public func checkKey() async throws {
        var request = try makeRequest("key", timeout: 15)
        request.httpMethod = "GET"
        _ = try await send(request)
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, timeout: TimeInterval
    ) async throws -> Response {
        var request = try makeRequest(path, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenRouterError.invalidResponse(String(describing: error))
        }
    }

    private func makeRequest(_ path: String, timeout: TimeInterval) throws -> URLRequest {
        guard let key = apiKey(), !key.isEmpty else { throw OpenRouterError.missingAPIKey }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("OpenWhisper", forHTTPHeaderField: "X-Title")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenRouterError.timeout
        } catch let error as URLError {
            throw OpenRouterError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse("не HTTP-ответ")
        }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw OpenRouterError.unauthorized
        case 402: throw OpenRouterError.paymentRequired
        case 429: throw OpenRouterError.rateLimited
        default: throw OpenRouterError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Inner: Decodable {
                let message: String
            }
            let error: Inner
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.error.message
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }
}

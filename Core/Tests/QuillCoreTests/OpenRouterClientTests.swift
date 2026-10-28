import XCTest
@testable import QuillCore

final class OpenRouterClientTests: XCTestCase {
    private func makeClient(key: String? = "k") -> OpenRouterClient {
        OpenRouterClient(session: StubURLProtocol.makeSession(), apiKey: { key })
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    private func assertThrows<T>(
        _ expected: OpenRouterError,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("ожидалась ошибка \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? OpenRouterError, expected, file: file, line: line)
        }
    }

    func testTranscribeSendsBase64AudioAndParsesCost() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
            let body = request.bodyJSON()
            XCTAssertEqual(body["model"] as? String, "openai/gpt-4o-transcribe")
            XCTAssertEqual(body["language"] as? String, "ru")
            let audio = body["input_audio"] as? [String: Any]
            XCTAssertEqual(audio?["data"] as? String, Data("abc".utf8).base64EncodedString())
            XCTAssertEqual(audio?["format"] as? String, "m4a")
            return try StubURLProtocol.respond(
                status: 200, json: #"{"text":"привет","usage":{"seconds":1.5,"cost":0.0012}}"#
            )(request)
        }
        let result = try await makeClient().transcribe(
            audio: Data("abc".utf8), format: "m4a", model: "openai/gpt-4o-transcribe", language: "ru"
        )
        XCTAssertEqual(result, TranscriptionResult(text: "привет", costUSD: 0.0012))
    }

    func testTranscribeOmitsLanguageWhenNil() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.bodyJSON()["language"])
            return try StubURLProtocol.respond(status: 200, json: #"{"text":"x"}"#)(request)
        }
        let result = try await makeClient().transcribe(audio: Data(), format: "m4a", model: "m", language: nil)
        XCTAssertEqual(result, TranscriptionResult(text: "x", costUSD: 0))
    }

    func testChatSendsMessagesAndRequestsUsage() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            let body = request.bodyJSON()
            XCTAssertEqual(body["model"] as? String, "openai/gpt-4.1-mini")
            XCTAssertEqual((body["messages"] as? [[String: Any]])?.count, 2)
            XCTAssertEqual((body["usage"] as? [String: Any])?["include"] as? Bool, true)
            return try StubURLProtocol.respond(
                status: 200, json: #"{"choices":[{"message":{"content":"Готово"}}],"usage":{"cost":0.0003}}"#
            )(request)
        }
        let messages = [ChatMessage(role: "system", content: "s"), ChatMessage(role: "user", content: "u")]
        let result = try await makeClient().chat(model: "openai/gpt-4.1-mini", messages: messages)
        XCTAssertEqual(result, ChatResult(text: "Готово", costUSD: 0.0003))
    }

    func testChatWithoutChoicesIsInvalidResponse() async {
        StubURLProtocol.handler = StubURLProtocol.respond(status: 200, json: #"{"choices":[]}"#)
        await assertThrows(.invalidResponse("пустой ответ модели")) {
            try await makeClient().chat(model: "m", messages: [])
        }
    }

    func testMissingAPIKeyThrowsWithoutRequest() async {
        let called = Flag()
        StubURLProtocol.handler = { request in
            called.value = true
            return try StubURLProtocol.respond(status: 200, json: "{}")(request)
        }
        await assertThrows(.missingAPIKey) { try await makeClient(key: nil).checkKey() }
        await assertThrows(.missingAPIKey) { try await makeClient(key: "").checkKey() }
        XCTAssertFalse(called.value)
    }

    func testMapsHTTPStatusCodes() async {
        let cases: [(Int, String, OpenRouterError)] = [
            (401, "{}", .unauthorized),
            (402, "{}", .paymentRequired),
            (429, "{}", .rateLimited),
            (500, #"{"error":{"message":"boom"}}"#, .server(status: 500, message: "boom")),
            (503, "not json", .server(status: 503, message: "not json")),
        ]
        for (status, json, expected) in cases {
            StubURLProtocol.handler = StubURLProtocol.respond(status: status, json: json)
            await assertThrows(expected) { try await makeClient().checkKey() }
        }
    }

    func testMapsTimeoutAndNetworkErrors() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await assertThrows(.timeout) { try await makeClient().checkKey() }

        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            try await makeClient().checkKey()
            XCTFail("ожидалась ошибка сети")
        } catch {
            guard case .network = error as? OpenRouterError else { return XCTFail("\(error)") }
        }
    }

    func testMalformedJSONIsInvalidResponse() async {
        StubURLProtocol.handler = StubURLProtocol.respond(status: 200, json: "not json")
        do {
            _ = try await makeClient().transcribe(audio: Data(), format: "m4a", model: "m", language: nil)
            XCTFail("ожидалась ошибка")
        } catch {
            guard case .invalidResponse = error as? OpenRouterError else { return XCTFail("\(error)") }
        }
    }

    func testCheckKeyCallsKeyEndpoint() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
            XCTAssertEqual(request.httpMethod, "GET")
            return try StubURLProtocol.respond(status: 200, json: #"{"data":{}}"#)(request)
        }
        try await makeClient().checkKey()
    }
}

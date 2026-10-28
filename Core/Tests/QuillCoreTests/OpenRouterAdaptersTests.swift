import XCTest
@testable import QuillCore

final class OpenRouterAdaptersTests: XCTestCase {
    private let client = OpenRouterClient(session: StubURLProtocol.makeSession(), apiKey: { "k" })

    override func tearDown() {
        StubURLProtocol.handler = nil
    }

    func testTranscriberSendsFileWithFormatFromExtensionAndTrimsText() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        StubURLProtocol.handler = { request in
            let audio = request.bodyJSON()["input_audio"] as? [String: Any]
            XCTAssertEqual(audio?["format"] as? String, "m4a")
            XCTAssertEqual(audio?["data"] as? String, Data("audio".utf8).base64EncodedString())
            return try StubURLProtocol.respond(status: 200, json: #"{"text":"  привет мир \n","usage":{"cost":0.01}}"#)(request)
        }
        let result = try await OpenRouterTranscriber(client: client)
            .transcribe(audioURL: url, model: "m", language: "ru")
        XCTAssertEqual(result, TranscriptionResult(text: "привет мир", costUSD: 0.01))
    }

    func testTranscriberThrowsForMissingFile() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).m4a")
        do {
            _ = try await OpenRouterTranscriber(client: client).transcribe(audioURL: url, model: "m", language: nil)
            XCTFail("ожидалась ошибка")
        } catch {}
    }

    func testPostProcessorSendsPromptBuilderMessages() async throws {
        let profile = Profile(id: "p", name: "P", vocabulary: ["MR"], instructions: "Кратко.")
        let expected = PromptBuilder.messages(rawText: "сырой", profile: profile)
        StubURLProtocol.handler = { request in
            let messages = request.bodyJSON()["messages"] as? [[String: String]]
            XCTAssertEqual(messages?.map { $0["role"] }, expected.map(\.role))
            XCTAssertEqual(messages?.map { $0["content"] }, expected.map(\.content))
            XCTAssertEqual(request.bodyJSON()["model"] as? String, "llm")
            return try StubURLProtocol.respond(
                status: 200, json: #"{"choices":[{"message":{"content":"Итог"}}],"usage":{"cost":0.002}}"#
            )(request)
        }
        let result = try await OpenRouterPostProcessor(client: client).process(rawText: "сырой", profile: profile, model: "llm")
        XCTAssertEqual(result, ChatResult(text: "Итог", costUSD: 0.002))
    }

    func testPostProcessorStripsTranscriptTagsAndWhitespace() {
        XCTAssertEqual(OpenRouterPostProcessor.clean("<transcript>\nГотово.\n</transcript>\n"), "Готово.")
        XCTAssertEqual(OpenRouterPostProcessor.clean("   Текст  \n"), "Текст")
        XCTAssertEqual(OpenRouterPostProcessor.clean("Без тегов"), "Без тегов")
        XCTAssertEqual(OpenRouterPostProcessor.clean("про <transcript> внутри"), "про <transcript> внутри")
    }

    func testNoticeMessagesAreNotEmpty() {
        let notices: [Notice] = [
            .transcriptionFailed("x"), .postprocessFailed("x"), .emptyTranscript, .copiedToClipboard,
            .needsAPIKey, .paymentRequired, .storageFailed("x"), .microphoneDenied, .recordingFailed("x"),
        ]
        for notice in notices {
            XCTAssertFalse(notice.message.isEmpty, "\(notice)")
        }
    }
}

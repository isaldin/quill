import XCTest
@testable import QuillCore

@MainActor
final class DictationPipelineTests: XCTestCase {
    var history: HistoryStore!
    var audio: AudioStore!
    var audioDirectory: URL!
    var transcriber: FakeTranscriber!
    var postProcessor: FakePostProcessor!
    var inserter: FakeInserter!
    var notifier: FakeNotifier!
    var pipeline: DictationPipeline!
    var config = PipelineConfig(defaultTranscriptionModel: "default/stt", defaultLLMModel: "default/llm", audioLimitBytes: 1_000_000)
    var profiles: [String: Profile] = [:]

    let clean = Profile(id: "clean", name: "Чистка", instructions: "Чисти.")
    let raw = Profile(id: "raw", name: "Без обработки", postprocess: false)
    let created = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() async throws {
        audioDirectory = FileManager.default.temporaryDirectory.appending(path: "ow-pipeline-\(UUID().uuidString)")
        history = try HistoryStore.inMemory()
        audio = try AudioStore(directory: audioDirectory)
        transcriber = FakeTranscriber()
        postProcessor = FakePostProcessor()
        inserter = FakeInserter()
        notifier = FakeNotifier()
        profiles = [clean.id: clean, raw.id: raw]
        pipeline = DictationPipeline(
            history: history, audio: audio, transcriber: transcriber, postProcessor: postProcessor,
            inserter: inserter, notifier: notifier,
            config: { [unowned self] in self.config },
            profileLookup: { [unowned self] in self.profiles[$0] }
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: audioDirectory)
    }

    private func makeRecording(duration: TimeInterval = 2, bytes: Int = 10) throws -> FinishedRecording {
        let id = UUID().uuidString
        let url = audio.newRecordingURL(id: id)
        try Data(repeating: 1, count: bytes).write(to: url)
        return FinishedRecording(id: id, fileURL: url, duration: duration, createdAt: created)
    }

    func testHappyPathInsertsProcessedTextAndStoresRecord() async throws {
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)

        XCTAssertEqual(inserter.inserted, ["Итоговый текст."])
        XCTAssertEqual(notifier.notices, [])
        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertEqual(record.status, .inserted)
        XCTAssertEqual(record.rawText, "сырой текст")
        XCTAssertEqual(record.finalText, "Итоговый текст.")
        XCTAssertEqual(record.profileID, "clean")
        XCTAssertEqual(record.transcriptionModel, "default/stt")
        XCTAssertEqual(record.llmModel, "default/llm")
        XCTAssertEqual(record.costUSD, 0.0015, accuracy: 1e-9)
        XCTAssertEqual(record.audioFileName, "\(recording.id).m4a")
        XCTAssertEqual(record.durationSec, 2)
        XCTAssertFalse(record.postprocessFailed)
        XCTAssertNil(record.error)
        XCTAssertEqual(pipeline.activeJobs, 0)
        XCTAssertGreaterThan(pipeline.historyRevision, 0)
    }

    func testRecordIsSavedBeforeTranscription() async throws {
        let recording = try makeRecording()
        let observed = Box<DictationStatus?>(nil)
        transcriber.onCall = { [history] in
            observed.value = try? history!.record(id: recording.id)?.status
        }
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(observed.value, .recorded)
    }

    func testProfileModelsAndLanguageOverrideDefaults() async throws {
        var custom = clean
        custom.transcriptionModel = "custom/stt"
        custom.llmModel = "custom/llm"
        custom.language = "ru"
        await pipeline.handle(try makeRecording(), profile: custom)
        XCTAssertEqual(transcriber.calls.first?.model, "custom/stt")
        XCTAssertEqual(transcriber.calls.first?.language, "ru")
        XCTAssertEqual(postProcessor.calls.first?.model, "custom/llm")
    }

    func testShortRecordingIsIgnoredAndFileDeleted() async throws {
        let recording = try makeRecording(duration: 0.39)
        await pipeline.handle(recording, profile: clean)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.fileURL.path))
        XCTAssertNil(try history.record(id: recording.id))
        XCTAssertTrue(transcriber.calls.isEmpty)
        XCTAssertTrue(inserter.inserted.isEmpty)
    }

    func testTranscriptionFailureKeepsAudioAndMarksFailed() async throws {
        transcriber.result = .failure(OpenRouterError.network("offline"))
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)

        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.error, OpenRouterError.network("offline").errorDescription)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.fileURL.path))
        XCTAssertEqual(record.audioFileName, "\(recording.id).m4a")
        XCTAssertTrue(inserter.inserted.isEmpty)
        XCTAssertEqual(notifier.notices, [.transcriptionFailed(OpenRouterError.network("offline").errorDescription!)])
    }

    func testMissingKeyAndUnauthorizedAskForAPIKey() async throws {
        for error in [OpenRouterError.missingAPIKey, .unauthorized] {
            transcriber.result = .failure(error)
            await pipeline.handle(try makeRecording(), profile: clean)
        }
        XCTAssertEqual(notifier.notices, [.needsAPIKey, .needsAPIKey])
    }

    func testPaymentRequiredNotice() async throws {
        transcriber.result = .failure(OpenRouterError.paymentRequired)
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(notifier.notices, [.paymentRequired])
        XCTAssertEqual(try history.record(id: recording.id)?.status, .failed)
    }

    func testEmptyTranscriptIsNotInserted() async throws {
        transcriber.result = .success(TranscriptionResult(text: "", costUSD: 0.001))
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)

        XCTAssertTrue(inserter.inserted.isEmpty)
        XCTAssertTrue(postProcessor.calls.isEmpty)
        XCTAssertEqual(notifier.notices, [.emptyTranscript])
        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.error, "Пустая расшифровка")
        XCTAssertEqual(record.costUSD, 0.001, accuracy: 1e-9)
    }

    func testPostprocessFailureInsertsRawText() async throws {
        postProcessor.result = .failure(OpenRouterError.timeout)
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)

        XCTAssertEqual(inserter.inserted, ["сырой текст"])
        XCTAssertEqual(notifier.notices, [.postprocessFailed(OpenRouterError.timeout.errorDescription!)])
        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertEqual(record.status, .inserted)
        XCTAssertTrue(record.postprocessFailed)
        XCTAssertEqual(record.finalText, "сырой текст")
        XCTAssertEqual(record.error, OpenRouterError.timeout.errorDescription)
    }

    func testPostprocessDisabledInsertsRawWithoutCallingLLM() async throws {
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: raw)
        XCTAssertEqual(inserter.inserted, ["сырой текст"])
        XCTAssertTrue(postProcessor.calls.isEmpty)
        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertNil(record.llmModel)
        XCTAssertEqual(record.finalText, "сырой текст")
    }

    func testEmptyLLMAnswerFallsBackToRawText() async throws {
        postProcessor.result = .success(ChatResult(text: "", costUSD: 0))
        await pipeline.handle(try makeRecording(), profile: clean)
        XCTAssertEqual(inserter.inserted, ["сырой текст"])
    }

    func testClipboardFallbackNotifies() async throws {
        inserter.outcome = .copiedToClipboard
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(notifier.notices, [.copiedToClipboard])
        XCTAssertEqual(try history.record(id: recording.id)?.status, .inserted)
    }

    func testReprocessReplacesFinalTextProfileAndModelWithoutInserting() async throws {
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        let other = Profile(id: "other", name: "Другой", llmModel: "other/llm")
        postProcessor.result = .success(ChatResult(text: "Новый итог", costUSD: 0.01))

        await pipeline.reprocess(id: recording.id, profile: other)

        XCTAssertEqual(inserter.inserted.count, 1)
        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertEqual(record.finalText, "Новый итог")
        XCTAssertEqual(record.profileID, "other")
        XCTAssertEqual(record.llmModel, "other/llm")
        XCTAssertEqual(record.rawText, "сырой текст")
        XCTAssertEqual(postProcessor.calls.last?.raw, "сырой текст")
    }

    func testRetranscribeUsesRecordProfileAndDoesNotInsert() async throws {
        transcriber.result = .failure(OpenRouterError.network("offline"))
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        transcriber.result = .success(TranscriptionResult(text: "второй раз", costUSD: 0.002))

        await pipeline.retranscribe(id: recording.id)

        XCTAssertTrue(inserter.inserted.isEmpty)
        let record = try XCTUnwrap(history.record(id: recording.id))
        XCTAssertEqual(record.rawText, "второй раз")
        XCTAssertEqual(record.finalText, "Итоговый текст.")
        XCTAssertEqual(record.status, .processed)
        XCTAssertNil(record.error)
        XCTAssertEqual(postProcessor.calls.last?.profileID, "clean")
    }

    func testRetranscribeWithUnknownProfileUsesRaw() async throws {
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: Profile(id: "gone", name: "Удалён"))
        await pipeline.retranscribe(id: recording.id)
        XCTAssertEqual(try history.record(id: recording.id)?.profileID, "raw")
    }

    func testRotationAfterDictationClearsOldAudio() async throws {
        config.audioLimitBytes = 150
        let first = try makeRecording(bytes: 100)
        await pipeline.handle(first, profile: clean)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: first.fileURL.path
        )
        let second = try makeRecording(bytes: 100)
        await pipeline.handle(second, profile: clean)

        XCTAssertNil(try history.record(id: first.id)?.audioFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertEqual(try history.record(id: second.id)?.audioFileName, "\(second.id).m4a")
        XCTAssertNotNil(try history.record(id: first.id)?.finalText)
    }

    func testDeleteRemovesRecordAndAudio() async throws {
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        pipeline.delete(id: recording.id)
        XCTAssertNil(try history.record(id: recording.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.fileURL.path))
    }

    func testRotationKeepsAudioOfUntranscribedDictation() async throws {
        config.audioLimitBytes = 150
        transcriber.result = .failure(OpenRouterError.network("offline"))
        let failed = try makeRecording(bytes: 100)
        await pipeline.handle(failed, profile: clean)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: failed.fileURL.path
        )
        transcriber.result = .success(TranscriptionResult(text: "сырой текст", costUSD: 0))
        let second = try makeRecording(bytes: 100)
        await pipeline.handle(second, profile: clean)

        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.fileURL.path))
        XCTAssertEqual(try history.record(id: failed.id)?.audioFileName, "\(failed.id).m4a")
    }

    private func recordEvents() -> Box<[PipelineEvent]> {
        let events = Box<[PipelineEvent]>([])
        pipeline.onEvent = { events.value.append($0) }
        return events
    }

    func testEmitsStagesAndInsertedForHappyPath() async throws {
        let events = recordEvents()
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(events.value, [
            .stage(id: recording.id, .transcribing),
            .stage(id: recording.id, .postprocessing),
            .finished(id: recording.id, .inserted),
        ])
    }

    func testSkipsPostprocessingStageWhenDisabled() async throws {
        let events = recordEvents()
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: raw)
        XCTAssertEqual(events.value, [
            .stage(id: recording.id, .transcribing),
            .finished(id: recording.id, .inserted),
        ])
    }

    func testEmitsFailedOnTranscriptionError() async throws {
        transcriber.result = .failure(OpenRouterError.timeout)
        let events = recordEvents()
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(events.value.last, .finished(id: recording.id, .failed(OpenRouterError.timeout.errorDescription!)))
    }

    func testEmitsFailedOnEmptyTranscript() async throws {
        transcriber.result = .success(TranscriptionResult(text: "", costUSD: 0))
        let events = recordEvents()
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(events.value.last, .finished(id: recording.id, .failed("Пустая расшифровка")))
    }

    func testEmitsCopiedToClipboardOutcome() async throws {
        inserter.outcome = .copiedToClipboard
        let events = recordEvents()
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(events.value.last, .finished(id: recording.id, .copiedToClipboard))
    }

    func testEmitsDiscardedForShortRecording() async throws {
        let events = recordEvents()
        let recording = try makeRecording(duration: 0.1)
        await pipeline.handle(recording, profile: clean)
        XCTAssertEqual(events.value, [.finished(id: recording.id, .discarded)])
    }

    func testHistoryActionsEmitNoEvents() async throws {
        let recording = try makeRecording()
        await pipeline.handle(recording, profile: clean)
        let events = recordEvents()
        await pipeline.reprocess(id: recording.id, profile: raw)
        await pipeline.retranscribe(id: recording.id)
        XCTAssertEqual(events.value, [])
    }
}

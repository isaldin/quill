import Foundation
import Observation

public struct FinishedRecording: Equatable, Sendable {
    public let id: String
    public let fileURL: URL
    /// Длительность звука в файле.
    public let duration: TimeInterval
    /// Время между стартом и остановкой. Может быть больше `duration`, если микрофон не отдавал данные.
    public let elapsed: TimeInterval
    /// Имя микрофона, если вся запись — цифровая тишина (устройство отдавало нули).
    public let silentInput: String?
    public let createdAt: Date

    public init(
        id: String, fileURL: URL, duration: TimeInterval, elapsed: TimeInterval? = nil,
        silentInput: String? = nil, createdAt: Date
    ) {
        self.id = id
        self.fileURL = fileURL
        self.duration = duration
        self.elapsed = elapsed ?? duration
        self.silentInput = silentInput
        self.createdAt = createdAt
    }
}

public struct PipelineConfig: Equatable, Sendable {
    public var defaultTranscriptionModel: String
    public var defaultLLMModel: String
    public var audioLimitBytes: Int64

    public init(defaultTranscriptionModel: String, defaultLLMModel: String, audioLimitBytes: Int64) {
        self.defaultTranscriptionModel = defaultTranscriptionModel
        self.defaultLLMModel = defaultLLMModel
        self.audioLimitBytes = audioLimitBytes
    }
}

@MainActor
@Observable
public final class DictationPipeline {
    public static let minimumDuration: TimeInterval = 0.4

    /// > 0, пока идёт распознавание или постобработка; иконка в меню показывает «обработку».
    public private(set) var activeJobs = 0
    /// Растёт после каждой записи в историю; окно истории перечитывает список по этому значению.
    public private(set) var historyRevision = 0
    /// Стадии и итог новых диктовок — для плавающего индикатора.
    @ObservationIgnored public var onEvent: (@MainActor (PipelineEvent) -> Void)?

    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private let audio: AudioStore
    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let postProcessor: any PostProcessor
    @ObservationIgnored private let inserter: any Inserter
    @ObservationIgnored private let notifier: any Notifier
    @ObservationIgnored private let config: @MainActor () -> PipelineConfig
    @ObservationIgnored private let profileLookup: @MainActor (String) -> Profile?

    public init(
        history: HistoryStore,
        audio: AudioStore,
        transcriber: any Transcriber,
        postProcessor: any PostProcessor,
        inserter: any Inserter,
        notifier: any Notifier,
        config: @escaping @MainActor () -> PipelineConfig,
        profileLookup: @escaping @MainActor (String) -> Profile?
    ) {
        self.history = history
        self.audio = audio
        self.transcriber = transcriber
        self.postProcessor = postProcessor
        self.inserter = inserter
        self.notifier = notifier
        self.config = config
        self.profileLookup = profileLookup
    }

    public func handle(_ recording: FinishedRecording, profile: Profile) async {
        // Случайное короткое нажатие определяем по времени, а не по звуку в файле:
        // если микрофон не отдавал данные, длинная диктовка выглядела бы пустой и терялась.
        guard recording.elapsed >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: recording.fileURL)
            onEvent?(.finished(id: recording.id, .discarded))
            return
        }
        activeJobs += 1
        defer { activeJobs -= 1 }

        var record = DictationRecord(
            id: recording.id, createdAt: recording.createdAt, profileID: profile.id,
            durationSec: recording.duration, audioFileName: recording.fileURL.lastPathComponent
        )
        save(record, isNew: true)

        if let device = recording.silentInput {
            let notice = Notice.silentInput(device)
            record.status = .failed
            record.error = notice.recordError
            save(record)
            notifier.notify(notice)
            onEvent?(.finished(id: record.id, .failed(notice.recordError)))
            rotateAudio()
            return
        }

        onEvent?(.stage(id: record.id, .transcribing))
        if await transcribe(&record, profile: profile) {
            if profile.postprocess {
                onEvent?(.stage(id: record.id, .postprocessing))
            }
            await postprocess(&record, profile: profile)
            let outcome = await inserter.insert(record.finalText ?? "")
            record.status = .inserted
            save(record)
            if outcome == .copiedToClipboard {
                notifier.notify(.copiedToClipboard)
            }
            onEvent?(.finished(id: record.id, outcome == .pasted ? .inserted : .copiedToClipboard))
        } else {
            onEvent?(.finished(id: record.id, .failed(record.error ?? "ошибка распознавания")))
        }
        rotateAudio()
    }

    public func reprocess(id: String, profile: Profile) async {
        guard var record = try? history.record(id: id), record.rawText != nil else { return }
        activeJobs += 1
        defer { activeJobs -= 1 }
        await postprocess(&record, profile: profile)
    }

    public func retranscribe(id: String) async {
        guard var record = try? history.record(id: id), record.audioFileName != nil else { return }
        activeJobs += 1
        defer { activeJobs -= 1 }
        let profile = profileLookup(record.profileID) ?? .fallbackRaw
        if await transcribe(&record, profile: profile) {
            await postprocess(&record, profile: profile)
        }
    }

    public func delete(id: String) {
        guard let record = try? history.record(id: id) else { return }
        if let fileName = record.audioFileName {
            audio.delete(fileName: fileName)
        }
        do {
            try history.delete(id: id)
        } catch {
            notifier.notify(.storageFailed(Self.describe(error)))
        }
        historyRevision += 1
    }

    /// Возвращает true, если есть непустой сырой текст для постобработки.
    private func transcribe(_ record: inout DictationRecord, profile: Profile) async -> Bool {
        guard let fileName = record.audioFileName else { return false }
        let model = profile.transcriptionModel ?? config().defaultTranscriptionModel
        do {
            let result = try await transcriber.transcribe(
                audioURL: audio.url(for: fileName), model: model, language: profile.language
            )
            record.transcriptionModel = model
            record.costUSD += result.costUSD
            guard !result.text.isEmpty else {
                record.status = .failed
                record.error = "Пустая расшифровка"
                save(record)
                notifier.notify(.emptyTranscript)
                return false
            }
            record.rawText = result.text
            record.status = .transcribed
            record.error = nil
            save(record)
            return true
        } catch {
            record.status = .failed
            record.error = Self.describe(error)
            save(record)
            notifier.notify(Self.notice(forTranscriptionError: error))
            return false
        }
    }

    private func postprocess(_ record: inout DictationRecord, profile: Profile) async {
        let raw = record.rawText ?? ""
        record.profileID = profile.id
        record.postprocessFailed = false
        record.error = nil
        record.status = .processed

        if profile.postprocess {
            let model = profile.llmModel ?? config().defaultLLMModel
            do {
                let result = try await postProcessor.process(rawText: raw, profile: profile, model: model)
                record.finalText = result.text.isEmpty ? raw : result.text
                record.llmModel = model
                record.costUSD += result.costUSD
            } catch {
                record.finalText = raw
                record.postprocessFailed = true
                record.error = Self.describe(error)
                notifier.notify(.postprocessFailed(Self.describe(error)))
            }
        } else {
            record.finalText = raw
            record.llmModel = nil
        }
        save(record)
    }

    private func save(_ record: DictationRecord, isNew: Bool = false) {
        do {
            if isNew {
                try history.insert(record)
            } else {
                try history.update(record)
            }
        } catch {
            notifier.notify(.storageFailed(Self.describe(error)))
        }
        historyRevision += 1
    }

    private func rotateAudio() {
        guard let ids = try? history.allIDs(), let untranscribed = try? history.idsWithoutRawText() else { return }
        let removed = audio.rotate(
            limitBytes: config().audioLimitBytes, knownIDs: ids, protectedIDs: untranscribed
        )
        guard !removed.isEmpty else { return }
        try? history.clearAudio(ids: removed)
        historyRevision += 1
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func notice(forTranscriptionError error: Error) -> Notice {
        switch error as? OpenRouterError {
        case .missingAPIKey?, .unauthorized?: .needsAPIKey
        case .paymentRequired?: .paymentRequired
        default: .transcriptionFailed(describe(error))
        }
    }
}

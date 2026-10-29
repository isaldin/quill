import Foundation

public enum DictationStage: Equatable, Sendable {
    case transcribing
    case postprocessing
}

public enum DictationOutcome: Equatable, Sendable {
    case inserted
    case copiedToClipboard
    case failed(String)
    /// Запись короче минимальной длительности: ничего не сохраняется и не вставляется.
    case discarded
}

/// События конвейера для индикатора. Шлются только для новых диктовок (`handle`),
/// но не для действий из истории.
public enum PipelineEvent: Equatable, Sendable {
    case stage(id: String, DictationStage)
    case finished(id: String, DictationOutcome)

    public var id: String {
        switch self {
        case .stage(let id, _), .finished(let id, _): id
        }
    }
}

public enum IndicatorResult: Equatable, Sendable {
    case inserted
    case copiedToClipboard
    case cancelled
    case failed(String)
}

public enum IndicatorPhase: Equatable, Sendable {
    case hidden
    /// Хоткей нажат, микрофон ещё подключается (iPhone, Bluetooth): звук пока не пишется.
    case connecting(profileName: String)
    case recording(profileName: String, startedAt: Date)
    case transcribing
    case postprocessing
    case finished(IndicatorResult)
}

/// Что показывает плавающий индикатор. Следит только за последней начатой диктовкой:
/// события более ранних диктовок, которые ещё обрабатываются, игнорируются.
public struct RecordingIndicatorModel: Equatable, Sendable {
    public static let shortHideDelay: TimeInterval = 0.8
    public static let longHideDelay: TimeInterval = 2.5

    public private(set) var phase: IndicatorPhase = .hidden
    private var trackedID: String?

    public init() {}

    public mutating func recordingStarted(id: String, profileName: String, at date: Date) {
        trackedID = id
        phase = .recording(profileName: profileName, startedAt: date)
    }

    public mutating func recordingConnecting(id: String, profileName: String) {
        trackedID = id
        phase = .connecting(profileName: profileName)
    }

    /// Запись реально пошла: таймер считается с этого момента. Опоздавший сигнал
    /// (запись уже остановлена или начата другая) ничего не меняет.
    public mutating func captureStarted(id: String, at date: Date) {
        guard id == trackedID, case .connecting(let profileName) = phase else { return }
        phase = .recording(profileName: profileName, startedAt: date)
    }

    public mutating func recordingStopped() {
        guard isRecordingOrConnecting else { return }
        phase = .transcribing
    }

    public mutating func recordingCancelled() {
        guard isRecordingOrConnecting else { return }
        trackedID = nil
        phase = .finished(.cancelled)
    }

    private var isRecordingOrConnecting: Bool {
        switch phase {
        case .connecting, .recording: true
        default: false
        }
    }

    public mutating func apply(_ event: PipelineEvent) {
        guard event.id == trackedID else { return }
        switch event {
        case .stage(_, .transcribing):
            phase = .transcribing
        case .stage(_, .postprocessing):
            phase = .postprocessing
        case .finished(_, let outcome):
            trackedID = nil
            switch outcome {
            case .inserted: phase = .finished(.inserted)
            case .copiedToClipboard: phase = .finished(.copiedToClipboard)
            case .failed(let message): phase = .finished(.failed(message))
            case .discarded: phase = .hidden
            }
        }
    }

    public mutating func hide() {
        phase = .hidden
    }

    /// Через сколько секунд спрятать индикатор; nil — пока не прятать.
    public var autoHideDelay: TimeInterval? {
        guard case .finished(let result) = phase else { return nil }
        if case .failed = result { return Self.longHideDelay }
        return Self.shortHideDelay
    }
}

public enum LevelMeter {
    /// Переводит уровень в дБ (-160…0) в шкалу 0…1; всё тише -50 дБ считается тишиной.
    public static func normalized(decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        let floor: Float = -50
        return Double(min(max((decibels - floor) / -floor, 0), 1))
    }
}

import Foundation

public enum GestureAction: Equatable, Sendable {
    case start
    case stop
}

/// Одна клавиша, два режима: удержание дольше holdThreshold — «держи и говори»,
/// короткое нажатие — старт, следующее нажатие — стоп.
/// Удержание отсчитывается от реального старта записи (`captureStarted`), а не от нажатия:
/// микрофон iPhone или Bluetooth подключается секундами, и отпускание до старта — это нажатие,
/// даже если событие пришло с опозданием.
public struct RecordGestureMachine: Sendable {
    public static let holdThreshold: TimeInterval = 0.3

    private enum State {
        case idle
        /// nil — запись ещё не пошла (микрофон подключается).
        case pressed(captureStartedAt: Date?)
        case toggled
        case pressedWhileToggled
    }

    private var state: State = .idle

    public init() {}

    public mutating func keyDown(at time: Date) -> GestureAction? {
        switch state {
        case .idle:
            state = .pressed(captureStartedAt: nil)
            return .start
        case .toggled:
            state = .pressedWhileToggled
            return .stop
        case .pressed, .pressedWhileToggled:
            return nil
        }
    }

    public mutating func keyUp(at time: Date) -> GestureAction? {
        switch state {
        case .pressed(let since):
            if let since, time.timeIntervalSince(since) > Self.holdThreshold {
                state = .idle
                return .stop
            }
            state = .toggled
            return nil
        case .pressedWhileToggled:
            state = .idle
            return nil
        case .idle, .toggled:
            return nil
        }
    }

    /// Микрофон подключился и запись реально пошла: с этого момента считается удержание.
    public mutating func captureStarted(at time: Date) {
        if case .pressed(nil) = state {
            state = .pressed(captureStartedAt: time)
        }
    }

    /// Запись закончилась не от клавиши: Esc, лимит 10 минут, ошибка.
    public mutating func reset() {
        state = .idle
    }
}

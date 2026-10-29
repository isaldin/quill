import Foundation

public enum GestureAction: Equatable, Sendable {
    case start
    case stop
}

/// Одна клавиша, два режима: удержание дольше holdThreshold — «держи и говори»,
/// короткое нажатие — старт, следующее нажатие — стоп.
public struct RecordGestureMachine: Sendable {
    public static let holdThreshold: TimeInterval = 0.3

    private enum State {
        case idle
        case pressed(since: Date)
        case toggled
        case pressedWhileToggled
    }

    private var state: State = .idle

    public init() {}

    public mutating func keyDown(at time: Date) -> GestureAction? {
        switch state {
        case .idle:
            state = .pressed(since: time)
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
            if time.timeIntervalSince(since) > Self.holdThreshold {
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

    /// Микрофон подключился и запись реально пошла. Удержание считается с этого момента:
    /// пока iPhone или Bluetooth подключаются несколько секунд, пользователь держит клавишу
    /// в ожидании, и отпускание сразу после старта — это нажатие, а не «держи и говори».
    public mutating func captureStarted(at time: Date) {
        if case .pressed = state {
            state = .pressed(since: time)
        }
    }

    /// Запись закончилась не от клавиши: Esc, лимит 10 минут, ошибка.
    public mutating func reset() {
        state = .idle
    }
}

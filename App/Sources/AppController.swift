import AppKit
import KeyboardShortcuts
import Observation
import OpenWhisperCore
import SwiftUI

extension KeyboardShortcuts.Name {
    static let record = Self("record", initial: .init(.space, modifiers: [.option]))
    static let nextProfile = Self("nextProfile", initial: .init(.p, modifiers: [.option, .shift]))
}

@MainActor
@Observable
final class AppController {
    enum RecordingState {
        case idle
        case recording
    }

    static let maxRecordingDuration: Duration = .seconds(600)

    private(set) var recordingState: RecordingState = .idle

    let settings: AppSettings
    let profiles: ProfileStore
    let history: HistoryStore
    let audio: AudioStore
    let client: OpenRouterClient
    let pipeline: DictationPipeline

    @ObservationIgnored private let notifier: SystemNotifier
    @ObservationIgnored private let recorder = Recorder()
    @ObservationIgnored private let windows = WindowPresenter()
    @ObservationIgnored private var gesture = RecordGestureMachine()
    @ObservationIgnored private var escMonitors: [Any] = []
    @ObservationIgnored private var autoStopTask: Task<Void, Never>?
    @ObservationIgnored private var recordingProfile: Profile?

    static func makeOrDie() -> AppController {
        do {
            return try AppController()
        } catch {
            fatalError("OpenWhisper не смог открыть хранилище: \(error)")
        }
    }

    private init() throws {
        let settings = AppSettings()
        let profiles = ProfileStore(directory: ProfileStore.defaultDirectory, defaults: .standard)
        let history = try HistoryStore.open(at: HistoryStore.defaultURL)
        let audio = try AudioStore(directory: AudioStore.defaultDirectory)
        let client = OpenRouterClient(apiKey: { KeychainStore.read() })
        let notifier = SystemNotifier()

        self.settings = settings
        self.profiles = profiles
        self.history = history
        self.audio = audio
        self.client = client
        self.notifier = notifier
        self.pipeline = DictationPipeline(
            history: history,
            audio: audio,
            transcriber: OpenRouterTranscriber(client: client),
            postProcessor: OpenRouterPostProcessor(client: client),
            inserter: PasteboardInserter(),
            notifier: notifier,
            config: { settings.pipelineConfig },
            profileLookup: { profiles.profile(id: $0) }
        )

        try? profiles.bootstrap()
        profiles.startWatching()
        notifier.requestAuthorization()
        notifier.onNeedsAPIKey = { [weak self] in self?.showSettings() }
        registerHotkeys()
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        KeyboardShortcuts.onKeyDown(for: .record) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.gesture.keyDown(at: Date()))
            }
        }
        KeyboardShortcuts.onKeyUp(for: .record) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.gesture.keyUp(at: Date()))
            }
        }
        KeyboardShortcuts.onKeyDown(for: .nextProfile) { [weak self] in
            MainActor.assumeIsolated {
                self?.profiles.reload()
                self?.profiles.selectNext()
            }
        }
    }

    private func apply(_ action: GestureAction?) {
        switch action {
        case .start?: startRecording()
        case .stop?: stopRecording()
        case nil: break
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard recordingState == .idle else { return }
        switch Permissions.microphone {
        case .authorized:
            break
        case .notDetermined:
            gesture.reset()
            Task { _ = await Permissions.requestMicrophone() }
            return
        default:
            gesture.reset()
            notifier.notify(.microphoneDenied)
            return
        }

        profiles.reload()
        let profile = profiles.activeProfile
        let id = UUID().uuidString
        do {
            try recorder.start(id: id, url: audio.newRecordingURL(id: id))
        } catch {
            gesture.reset()
            notifier.notify(.recordingFailed(error.localizedDescription))
            return
        }

        recordingProfile = profile
        recordingState = .recording
        if settings.soundsEnabled { NSSound(named: "Tink")?.play() }
        installEscMonitors()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maxRecordingDuration)
            guard !Task.isCancelled else { return }
            self?.stopRecording()
        }
    }

    func stopRecording() {
        guard recordingState == .recording,
              let profile = recordingProfile,
              let finished = recorder.stop()
        else { return }
        endRecordingSession()
        if settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        Task { await pipeline.handle(finished, profile: profile) }
    }

    func cancelRecording() {
        guard recordingState == .recording else { return }
        recorder.cancel()
        endRecordingSession()
    }

    private func endRecordingSession() {
        recordingState = .idle
        recordingProfile = nil
        gesture.reset()
        autoStopTask?.cancel()
        autoStopTask = nil
        removeEscMonitors()
    }

    private func installEscMonitors() {
        let escape: UInt16 = 53
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == escape else { return }
            MainActor.assumeIsolated { self?.cancelRecording() }
        }) {
            escMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == escape {
                MainActor.assumeIsolated { self?.cancelRecording() }
            }
            return event
        }) {
            escMonitors.append(local)
        }
    }

    private func removeEscMonitors() {
        escMonitors.forEach(NSEvent.removeMonitor)
        escMonitors = []
    }

    // MARK: - Windows

    func showSettings() {
        windows.show(id: "settings", title: "Настройки OpenWhisper", size: NSSize(width: 520, height: 560)) {
            SettingsView(controller: self)
        }
    }

    func showHistory() {
        windows.show(id: "history", title: "История OpenWhisper", size: NSSize(width: 900, height: 600)) {
            HistoryView(controller: self)
        }
    }
}

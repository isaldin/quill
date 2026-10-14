import AVFoundation
import OpenWhisperCore

enum RecorderError: LocalizedError {
    case couldNotStart

    var errorDescription: String? { "микрофон не начал запись" }
}

@MainActor
final class Recorder {
    private var recorder: AVAudioRecorder?
    private var current: (id: String, url: URL, startedAt: Date)?

    func start(id: String, url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        current = (id, url, Date())
    }

    func stop() -> FinishedRecording? {
        guard let recorder, let current else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.current = nil
        return FinishedRecording(id: current.id, fileURL: current.url, duration: duration, createdAt: current.startedAt)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        current = nil
    }
}

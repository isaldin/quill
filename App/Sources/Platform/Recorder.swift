import AVFoundation
import OSLog
import QuillCore

extension Logger {
    /// Служебный лог записи: устройство, длительности, причины отказа. Тексты диктовок сюда не пишутся.
    /// Смотреть: `log show --last 1h --predicate 'subsystem == "dev.saldin.quill"'`
    static let recording = Logger(subsystem: "dev.saldin.quill", category: "recording")
}

enum RecorderError: LocalizedError {
    case noInputDevice
    case cannotUseDevice(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "не найден микрофон"
        case .cannotUseDevice(let name): "не удалось подключить микрофон «\(name)»"
        }
    }
}

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String

    static func all() -> [AudioInputDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}

/// Запись через AVCaptureSession: в отличие от AVAudioRecorder позволяет выбрать микрофон.
/// Выбор встроенного микрофона при Bluetooth-наушниках не переводит их в режим гарнитуры.
@MainActor
final class Recorder {
    private var active: CaptureRecording?

    /// `deviceUID == nil` или отключённое устройство — системный микрофон по умолчанию.
    func start(id: String, url: URL, deviceUID: String?) throws {
        let device = deviceUID.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw RecorderError.noInputDevice }
        let recording = try CaptureRecording(id: id, url: url, device: device)
        recording.start()
        active = recording
        Logger.recording.info("""
            start \(id, privacy: .public): device «\(device.localizedName, privacy: .public)» \
            uid \(device.uniqueID, privacy: .public), requested \(deviceUID ?? "default", privacy: .public)
            """)
    }

    /// Уровень входного сигнала в дБ (-160…0).
    var level: Float { active?.level ?? -160 }

    func stop() async -> FinishedRecording? {
        guard let recording = active else { return nil }
        active = nil
        let (duration, elapsed) = await recording.stop()
        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            Logger.recording.error("stop \(recording.id, privacy: .public): file not created, elapsed \(elapsed, format: .fixed(precision: 2))s")
            return nil
        }
        let silent = await Task.detached { AudioSilence.isDigitalSilence(recording.url) }.value
        let size = (try? FileManager.default.attributesOfItem(atPath: recording.url.path)[.size] as? Int) ?? -1
        Logger.recording.info("""
            stop \(recording.id, privacy: .public): audio \(duration, format: .fixed(precision: 2))s, \
            elapsed \(elapsed, format: .fixed(precision: 2))s, \(size) bytes, silent \(silent)
            """)
        return FinishedRecording(
            id: recording.id, fileURL: recording.url, duration: duration, elapsed: elapsed,
            silentInput: silent ? recording.deviceName : nil, createdAt: recording.startedAt
        )
    }

    func cancel() {
        guard let recording = active else { return }
        active = nil
        Task {
            _ = await recording.stop()
            try? FileManager.default.removeItem(at: recording.url)
            Logger.recording.info("cancel \(recording.id, privacy: .public)")
        }
    }
}

private final class CaptureRecording: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let id: String
    let url: URL
    let deviceName: String
    let startedAt = Date()

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private let lock = NSLock()
    private var isFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(id: String, url: URL, device: AVCaptureDevice) throws {
        self.id = id
        self.url = url
        self.deviceName = device.localizedName
        super.init()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.cannotUseDevice(device.localizedName)
        }
        session.addInput(input)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        session.addOutput(output)
    }

    func start() {
        session.startRunning()
        output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
    }

    var level: Float {
        output.connections.first?.audioChannels.first?.averagePowerLevel ?? -160
    }

    /// Останавливает запись и ждёт, пока файл будет дописан.
    /// Возвращает длительность звука в файле и время между стартом и остановкой.
    func stop() async -> (duration: TimeInterval, elapsed: TimeInterval) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let recorded = output.recordedDuration.seconds
        let duration = recorded.isFinite && recorded > 0 ? recorded : elapsed
        output.stopRecording()
        await waitUntilFinished()
        session.stopRunning()
        return (duration, elapsed)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection], error: Error?
    ) {
        finish()
    }

    private func waitUntilFinished() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isFinished {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
            // Если запись так и не успела начаться, делегат может не прийти — не ждём вечно.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in self?.finish() }
        }
    }

    private func finish() {
        lock.lock()
        isFinished = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

enum AudioSilence {
    /// true, если в файле нет ни одного ненулевого отсчёта: устройство отдавало нули.
    /// Даже тихая комната даёт шум, поэтому точные нули означают, что звук не дошёл.
    /// Нечитаемый файл тишиной не считается — пусть его разбирает распознавание.
    static func isDigitalSilence(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384)
        else { return false }
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { return false }
            guard let samples = buffer.floatChannelData?[0] else { return false }
            for index in 0..<Int(buffer.frameLength) where samples[index] != 0 { return false }
        }
        return true
    }
}

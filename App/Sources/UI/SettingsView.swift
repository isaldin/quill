import KeyboardShortcuts
import OpenWhisperCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var apiKey = KeychainStore.read() ?? ""
    @State private var showKey = false
    @State private var keyStatus = ""
    @State private var transcriptionModel = ""
    @State private var llmModel = ""
    @FocusState private var focusedModel: ModelField?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var audioUsage = ""
    @State private var microphoneGranted = Permissions.microphone == .authorized
    @State private var accessibilityGranted = Permissions.accessibilityGranted
    @State private var inputDevices = AudioInputDevice.all()

    private enum ModelField {
        case transcription
        case llm
    }

    private static let createKeyURL = URL(string: "https://openrouter.ai/settings/keys")!

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section("OpenRouter") {
                HStack {
                    if showKey {
                        TextField("API-ключ", text: $apiKey)
                    } else {
                        SecureField("API-ключ", text: $apiKey)
                    }
                    Button(showKey ? "Скрыть" : "Показать") { showKey.toggle() }
                }
                HStack {
                    Button("Сохранить") {
                        KeychainStore.save(apiKey)
                        keyStatus = apiKey.isEmpty ? "Ключ удалён" : "Сохранено"
                    }
                    Button("Проверить") { Task { await checkKey() } }
                    Button("Скопировать") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(apiKey, forType: .string)
                        keyStatus = "Скопировано"
                    }
                    .disabled(apiKey.isEmpty)
                    Text(keyStatus).foregroundStyle(.secondary)
                }
                Link("Создать ключ на OpenRouter", destination: Self.createKeyURL)
                Text("Ключ хранится только на этой машине. На другом ноутбуке вставьте его один раз или создайте отдельный.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Модель распознавания", text: $transcriptionModel)
                    .focused($focusedModel, equals: .transcription)
                    .onSubmit(commitModels)
                TextField("Модель постобработки", text: $llmModel)
                    .focused($focusedModel, equals: .llm)
                    .onSubmit(commitModels)
            }

            Section("Горячие клавиши") {
                KeyboardShortcuts.Recorder("Запись:", name: .record)
                KeyboardShortcuts.Recorder("Следующий профиль:", name: .nextProfile)
            }

            Section("Аудио") {
                Picker("Микрофон", selection: $settings.inputDeviceUID) {
                    Text("Системный по умолчанию").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                    if !settings.inputDeviceUID.isEmpty,
                       !inputDevices.contains(where: { $0.id == settings.inputDeviceUID }) {
                        Text("Отключён — используется системный").tag(settings.inputDeviceUID)
                    }
                }
                Text("С Bluetooth-наушниками выберите встроенный микрофон: запись будет чище, а звук в наушниках не будет прерываться.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $settings.audioLimitGB, in: 0.1...50, step: 0.5) {
                    Text("Лимит: \(settings.audioLimitGB, specifier: "%.1f") ГБ")
                }
                Text("Занято: \(audioUsage)").foregroundStyle(.secondary)
                Toggle("Звуки начала и конца записи", isOn: $settings.soundsEnabled)
                Toggle("Индикатор записи вверху экрана", isOn: $settings.showIndicator)
            }

            Section("Синхронизация") {
                if settings.syncLocation.isICloud {
                    Text("Общие настройки и профили — в iCloud Drive → OpenWhisper")
                } else {
                    Text("Синхронизация выключена: iCloud Drive недоступен. Файлы — в ~/.config/openwhisper")
                        .foregroundStyle(.orange)
                }
                Text("Микрофон, горячие клавиши, активный профиль, ключ и история — свои на каждой машине.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let loadError = settings.shared.loadError {
                    Text("\(loadError). Используются последние корректные значения; любое изменение здесь перезапишет файл.")
                        .foregroundStyle(.red)
                }
                if let saveError = settings.saveError {
                    Text(saveError).foregroundStyle(.red)
                }
                Button("Открыть папку") { NSWorkspace.shared.open(settings.syncLocation.directory) }
            }

            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                HStack {
                    Text(microphoneGranted ? "✓ Микрофон" : "✗ Микрофон")
                    Spacer()
                    Button("Открыть настройки") { Permissions.openMicrophoneSettings() }
                }
                HStack {
                    Text(accessibilityGranted ? "✓ Accessibility (вставка текста)" : "✗ Accessibility (вставка текста)")
                    Spacer()
                    Button("Запросить") {
                        Permissions.promptAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
                Button("Открыть папку профилей") {
                    NSWorkspace.shared.open(controller.profiles.directory)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onChange(of: focusedModel) { _, _ in commitModels() }
        .onChange(of: settings.defaultTranscriptionModel) { _, value in
            if focusedModel != .transcription { transcriptionModel = value }
        }
        .onChange(of: settings.defaultLLMModel) { _, value in
            if focusedModel != .llm { llmModel = value }
        }
    }

    private func refresh() {
        controller.settings.shared.reload()
        transcriptionModel = controller.settings.defaultTranscriptionModel
        llmModel = controller.settings.defaultLLMModel
        audioUsage = ByteCountFormatter.string(fromByteCount: controller.audio.totalSize(), countStyle: .file)
        microphoneGranted = Permissions.microphone == .authorized
        accessibilityGranted = Permissions.accessibilityGranted
        inputDevices = AudioInputDevice.all()
    }

    /// Записывает модели только если текст отличается: SharedSettingsStore не трогает файл без изменений.
    private func commitModels() {
        let settings = controller.settings
        if transcriptionModel != settings.defaultTranscriptionModel {
            settings.defaultTranscriptionModel = transcriptionModel
            transcriptionModel = settings.defaultTranscriptionModel
        }
        if llmModel != settings.defaultLLMModel {
            settings.defaultLLMModel = llmModel
            llmModel = settings.defaultLLMModel
        }
    }

    private func checkKey() async {
        KeychainStore.save(apiKey)
        keyStatus = "Проверяю…"
        do {
            try await controller.client.checkKey()
            keyStatus = "✓ Ключ работает"
        } catch {
            keyStatus = "✗ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

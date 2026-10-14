import KeyboardShortcuts
import OpenWhisperCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var apiKey = KeychainStore.read() ?? ""
    @State private var keyStatus = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var audioUsage = ""
    @State private var microphoneGranted = Permissions.microphone == .authorized
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    var body: some View {
        @Bindable var settings = controller.settings
        Form {
            Section("OpenRouter") {
                SecureField("API-ключ", text: $apiKey)
                HStack {
                    Button("Сохранить") {
                        KeychainStore.save(apiKey)
                        keyStatus = apiKey.isEmpty ? "Ключ удалён" : "Сохранено"
                    }
                    Button("Проверить") { Task { await checkKey() } }
                    Text(keyStatus).foregroundStyle(.secondary)
                }
                TextField("Модель распознавания", text: $settings.defaultTranscriptionModel)
                TextField("Модель постобработки", text: $settings.defaultLLMModel)
            }

            Section("Горячие клавиши") {
                KeyboardShortcuts.Recorder("Запись:", name: .record)
                KeyboardShortcuts.Recorder("Следующий профиль:", name: .nextProfile)
            }

            Section("Аудио") {
                Stepper(value: $settings.audioLimitGB, in: 0.1...50, step: 0.5) {
                    Text("Лимит: \(settings.audioLimitGB, specifier: "%.1f") ГБ")
                }
                Text("Занято: \(audioUsage)").foregroundStyle(.secondary)
                Toggle("Звуки начала и конца записи", isOn: $settings.soundsEnabled)
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
    }

    private func refresh() {
        audioUsage = ByteCountFormatter.string(fromByteCount: controller.audio.totalSize(), countStyle: .file)
        microphoneGranted = Permissions.microphone == .authorized
        accessibilityGranted = Permissions.accessibilityGranted
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

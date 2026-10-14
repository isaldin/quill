import OpenWhisperCore
import SwiftUI

struct MenuContent: View {
    @Bindable var controller: AppController

    var body: some View {
        @Bindable var profiles = controller.profiles
        Text(statusLine)

        Divider()

        Picker("Профиль", selection: $profiles.activeProfileID) {
            ForEach(controller.profiles.validProfiles) { profile in
                Text(profile.name).tag(profile.id)
            }
        }
        .pickerStyle(.inline)

        ForEach(controller.profiles.entries.filter { $0.profile == nil }) { entry in
            if case .invalid(let id, let message) = entry {
                Text("⚠︎ \(id).md: \(message)")
            }
        }

        Divider()

        Button("История…") { controller.showHistory() }
        Button("Настройки…") { controller.showSettings() }
            .keyboardShortcut(",")
        Button("Открыть папку профилей") { NSWorkspace.shared.open(controller.profiles.directory) }

        Divider()

        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch controller.recordingState {
        case .recording:
            return "● Запись… (Esc — отмена)"
        case .idle where controller.pipeline.activeJobs > 0:
            return "Обработка…"
        case .idle:
            return "Профиль: \(controller.profiles.activeProfile.name)"
        }
    }
}

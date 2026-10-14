import SwiftUI
import OpenWhisperCore

@main
struct OpenWhisperApp: App {
    var body: some Scene {
        MenuBarExtra("OpenWhisper", systemImage: "waveform") {
            Text("OpenWhisper \(OpenWhisperCore.version)")
            Divider()
            Button("Выйти") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

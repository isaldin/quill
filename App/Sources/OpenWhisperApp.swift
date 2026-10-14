import SwiftUI

@main
struct OpenWhisperApp: App {
    @State private var controller = AppController.makeOrDie()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            MenuBarIcon(
                isRecording: controller.recordingState == .recording,
                isProcessing: controller.pipeline.activeJobs > 0
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

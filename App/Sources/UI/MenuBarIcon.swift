import AppKit
import SwiftUI

struct MenuBarIcon: View {
    let isRecording: Bool
    let isProcessing: Bool

    var body: some View {
        if isRecording {
            Image(nsImage: Self.recordingImage)
        } else if isProcessing {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            Image(systemName: "waveform")
        }
    }

    /// Красная иконка: обычные template-изображения в строке меню монохромные.
    @MainActor
    private static let recordingImage: NSImage = {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Идёт запись")!
            .withSymbolConfiguration(configuration)!
        image.isTemplate = false
        return image
    }()
}

import AppKit
import ApplicationServices
import QuillCore

@MainActor
final class PasteboardInserter: Inserter {
    /// Вставки идут строго по очереди, иначе две параллельные диктовки перепутают
    /// сохранённое и восстановленное содержимое буфера обмена.
    private var tail: Task<InsertOutcome, Never>?

    func insert(_ text: String) async -> InsertOutcome {
        let previous = tail
        let task = Task { @MainActor in
            _ = await previous?.value
            return await self.perform(text)
        }
        tail = task
        return await task.value
    }

    private func perform(_ text: String) async -> InsertOutcome {
        let pasteboard = NSPasteboard.general
        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboard
        }

        let saved: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Self.pressCommandV()
        try? await Task.sleep(for: .milliseconds(500))

        pasteboard.clearContents()
        if !saved.isEmpty {
            pasteboard.writeObjects(saved)
        }
        return .pasted
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

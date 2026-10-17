import AppKit
import Observation
import OpenWhisperCore

/// Иконка и меню в строке меню на чистом AppKit. SwiftUI `MenuBarExtra` иногда терял картинку
/// после сна или смены экранов: элемент оставался, но ничего не рисовал. Здесь картинку
/// выставляем сами и заново после пробуждения и изменения конфигурации экранов.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(controller: AppController) {
        self.controller = controller
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon(force: true)
        trackState()
        observeSystemChanges()
    }

    // MARK: - Иконка

    private func updateIcon(force: Bool = false) {
        guard let button = statusItem.button else { return }
        let state = StatusIcon.make(
            isRecording: controller.recordingState == .recording,
            activeJobs: controller.pipeline.activeJobs
        )
        if force { button.image = nil }
        button.image = Self.image(for: state)
        button.toolTip = switch state {
        case .idle: "OpenWhisper"
        case .recording: "OpenWhisper — идёт запись"
        case .processing: "OpenWhisper — обработка"
        }
    }

    private static func image(for state: StatusIcon) -> NSImage? {
        switch state {
        case .idle:
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "OpenWhisper")
            image?.isTemplate = true
            return image
        case .processing:
            let image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Обработка")
            image?.isTemplate = true
            return image
        case .recording:
            // Красная иконка: template-изображения в строке меню монохромные.
            let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Идёт запись")?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = false
            return image
        }
    }

    /// Перерисовывает иконку при каждом изменении записи или числа задач обработки.
    private func trackState() {
        withObservationTracking {
            _ = controller.recordingState
            _ = controller.pipeline.activeJobs
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.trackState()
            }
        }
    }

    private func observeSystemChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.updateIcon(force: true) }
        }
        notificationTokens = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)),
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: refresh)),
            (app, app.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refresh)),
        ]
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        controller.profiles.reload()
        menu.removeAllItems()
        let items = StatusMenuModel.items(
            isRecording: controller.recordingState == .recording,
            activeJobs: controller.pipeline.activeJobs,
            entries: controller.profiles.entries,
            activeProfile: controller.profiles.activeProfile
        )
        for item in items {
            menu.addItem(makeMenuItem(item))
        }
    }

    private func makeMenuItem(_ item: StatusMenuItem) -> NSMenuItem {
        switch item {
        case .status(let text):
            let menuItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            menuItem.isEnabled = false
            return menuItem
        case .profile(let id, let name, let isActive):
            let menuItem = NSMenuItem(title: name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = id
            menuItem.state = isActive ? .on : .off
            menuItem.indentationLevel = 1
            return menuItem
        case .invalidProfile(let text):
            let menuItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            menuItem.isEnabled = false
            menuItem.indentationLevel = 1
            return menuItem
        case .separator:
            return .separator()
        case .action(let action):
            let (title, selector, key): (String, Selector, String) = switch action {
            case .history: ("История…", #selector(showHistory), "")
            case .settings: ("Настройки…", #selector(showSettings), ",")
            case .openProfilesFolder: ("Открыть папку профилей", #selector(openProfilesFolder), "")
            case .quit: ("Выйти", #selector(quit), "q")
            }
            let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            menuItem.target = self
            return menuItem
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.profiles.activeProfileID = id
    }

    @objc private func showHistory() { controller.showHistory() }
    @objc private func showSettings() { controller.showSettings() }
    @objc private func openProfilesFolder() { NSWorkspace.shared.open(controller.profiles.directory) }
    @objc private func quit() { NSApp.terminate(nil) }
}

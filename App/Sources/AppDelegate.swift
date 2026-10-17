import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusItem: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let controller = AppController.makeOrDie()
        self.controller = controller
        statusItem = StatusItemController(controller: controller)
    }

    /// Повторный запуск уже открытого приложения (из «Программ», Spotlight, Dock) открывает настройки:
    /// так видимый результат есть, даже если иконку в строке меню не видно.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showSettings()
        return false
    }
}

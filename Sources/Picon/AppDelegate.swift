import AppKit
import PiconCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?

    private var model: AppModel!
    private var menuBarController: MenuBarController!
    private var clipboardMonitor: ClipboardMonitor!
    private var settingsWindowController: SettingsWindowController!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        settingsWindowController = SettingsWindowController(model: model)
        menuBarController = MenuBarController(
            model: model,
            openSettings: { [weak self] in self?.settingsWindowController.show() },
            quit: { NSApp.terminate(nil) }
        )
        clipboardMonitor = ClipboardMonitor { [weak self] image in
            self?.model.addClipboardImage(image)
        }
        clipboardMonitor.start()
    }
}

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var popupController: PopupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let popupController = PopupWindowController()
        self.popupController = popupController

        statusBarController = StatusBarController(
            onToggle: { [weak popupController] in popupController?.toggle() },
            onQuit: { NSApp.terminate(nil) }
        )

        hotkeyManager = HotkeyManager { [weak popupController] in
            popupController?.toggle()
        }
        hotkeyManager?.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
    }
}

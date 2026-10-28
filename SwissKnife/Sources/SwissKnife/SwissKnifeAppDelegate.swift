import AppKit

/// Swiss Knife 统一生命周期：启动四个模块 + 整合状态栏/菜单。
@MainActor
final class SwissKnifeAppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = SwissKnifeMenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        FlowModule.shared.start()
        WatchDogModule.shared.start()
        WheelTamerModule.shared.start()
        ZoneModule.shared.start()
        ReminderModule.shared.start()
        StickyNotesModule.shared.start()
        menuController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WatchDogModule.shared.stop()
        WheelTamerModule.shared.stop()
        ZoneModule.shared.stop()
        ReminderModule.shared.stop()
        StickyNotesModule.shared.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

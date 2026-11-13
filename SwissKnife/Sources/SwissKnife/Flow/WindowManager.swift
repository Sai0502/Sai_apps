import SwiftUI
import AppKit

/// 手动管理设置窗口与休息全屏遮罩（菜单栏应用无 Dock 图标，无主窗口）
@MainActor
enum WindowManager {

    private static var settingsWindow: NSWindow?
    private static var breakOverlayWindows: [NSWindow] = []

    static func ensureSettingsWindow() -> NSWindow {
        if let w = settingsWindow { return w }
        let hosting = NSHostingView(rootView: SettingsView().environmentObject(AppState.shared))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 710),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "设置"
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.center()
        settingsWindow = w
        return w
    }

    static func showSettingsWindow() {
        let w = ensureSettingsWindow()
        w.makeKeyAndOrderFront(nil)
        NSApp.activateBestEffort()
    }

    // MARK: - 休息全屏遮罩（覆盖所有 APP，含已全屏的）

    static func showBreakOverlay() {
        hideBreakOverlay()
        let hosting = NSHostingView(rootView: FullscreenBreakView().environmentObject(AppState.shared))
        // 在所有显示器上各建一个遮罩窗口
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame,
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
            w.level = .screenSaver            // 最高窗口层级，盖过普通全屏 App
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = true
            w.backgroundColor = NSColor(red: 0.15, green: 0.47, blue: 0.40, alpha: 1)
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            w.makeKeyAndOrderFront(nil)
            breakOverlayWindows.append(w)
        }
        // 注意：borderless 窗口不能成为 main window（makeMain() 会抛
        // NSInternalInconsistencyException 并中断 timer 链），故只保持 key window。
        NSApp.activateBestEffort()
    }

    static var isBreakOverlayVisible: Bool { !breakOverlayWindows.isEmpty }

    static func hideBreakOverlay() {
        for w in breakOverlayWindows {
            w.close()
        }
        breakOverlayWindows.removeAll()
    }
}

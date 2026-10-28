import AppKit
import SwiftUI

/// Reminder 模块自己的浮层窗口管理：
/// - 右上角倒计时浮层（到点前 5→1 秒预警）
/// - 全屏图片提醒（所有屏幕，含「双击跳过」与 10 秒倒计时）
/// 与 Flow 的休息全屏遮罩完全隔离，互不影响。
@MainActor
enum ReminderWindowManager {

    // MARK: - 角落倒计时浮层

    private static var countdownOverlayWindow: NSWindow?

    static func showCountdownOverlay(_ seconds: Int, onCancel: @escaping () -> Void) {
        if countdownOverlayWindow == nil {
            let hosting = NSHostingView(rootView: CountdownOverlayView().environmentObject(CountdownOverlayModel.shared))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 230, height: 230),
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            countdownOverlayWindow = w
        }
        CountdownOverlayModel.shared.seconds = seconds
        CountdownOverlayModel.shared.onCancel = onCancel
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let size = countdownOverlayWindow!.frame.size
            countdownOverlayWindow!.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24))
        }
        countdownOverlayWindow?.makeKeyAndOrderFront(nil)
    }

    static func hideCountdownOverlay() {
        countdownOverlayWindow?.orderOut(nil)
    }

    // MARK: - 全屏图片提醒

    private static var scheduledImageWindows: [NSWindow] = []

    static func showScheduledImageOverlay(image: NSImage) {
        hideScheduledImageOverlay()
        for screen in NSScreen.screens {
            let hosting = NSHostingView(rootView: ScheduledImageOverlayView(image: image, onClose: { hideScheduledImageOverlay() }))
            let w = NSWindow(contentRect: screen.frame,
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
            w.level = .screenSaver            // 最高层级，盖过普通全屏 App 与休息遮罩
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = true
            w.backgroundColor = .black
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            w.makeKeyAndOrderFront(nil)
            scheduledImageWindows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static var isScheduledImageVisible: Bool { !scheduledImageWindows.isEmpty }

    static func hideScheduledImageOverlay() {
        for w in scheduledImageWindows {
            w.close()
        }
        scheduledImageWindows.removeAll()
    }
}

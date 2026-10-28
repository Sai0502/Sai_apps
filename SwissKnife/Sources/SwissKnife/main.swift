import AppKit

// Swiss Knife 统一入口：无 Dock 图标（LSUIElement），由 SwissKnifeAppDelegate 启动四个模块。
// 顶层代码运行在主线程，用 assumeIsolated 满足 @MainActor 隔离检查。
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { SwissKnifeAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

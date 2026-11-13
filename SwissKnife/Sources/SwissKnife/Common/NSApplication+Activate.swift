import AppKit

extension NSApplication {
    /// macOS 14 起 `activate(ignoringOtherApps:)` 已废弃，按系统版本切换。
    func activateBestEffort() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

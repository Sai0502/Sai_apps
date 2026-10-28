import AppKit

/// FitRecordZone 模块：按比例显示取景框。
/// 融合后不创建独立状态栏，菜单分组由 SwissKnife 整合控制器统一承载。
@MainActor
final class ZoneModule: NSObject, @preconcurrency OverlayControllerDelegate {
    static let shared = ZoneModule()

    private let overlayController = OverlayController()
    private let settingsStore = ZoneStore.shared
    private let logger = ZoneLogger.shared

    private override init() {
        super.init()
    }

    // MARK: - 生命周期

    func start() {
        overlayController.delegate = self
        overlayController.start()
    }

    func stop() {
        overlayController.stop()
    }

    func overlayControllerDidUpdate(_ controller: OverlayController) {
        // 菜单每次展开时重建，无需主动刷新
    }

    func overlayControllerDidRequestRatioEdit(_ controller: OverlayController) {
        promptForRatioAndShow()
    }

    // MARK: - 菜单

    /// 追加 FitRecordZone 分组菜单项：模块名 + 显示 / 设置边框颜色
    func appendMenuItems(to menu: NSMenu) {
        menu.addItem(label("FitRecordZone"))
        menu.addItem(menuItem("    显示", action: #selector(showOverlay)))
        menu.addItem(menuItem("    设置边框颜色…", action: #selector(openColorPanel)))
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// 工具设置页修改边框颜色后，立即应用到取景框
    func applyStrokeColor(_ color: NSColor) {
        overlayController.applyStrokeColor(color)
    }

    /// 四合一调试快照的 Zone 部分
    func debugSummary() -> String {        let snap = overlayController.currentSnapshot()
        var l: [String] = []
        l.append("FitRecordZone")
        if let snap {
            l.append("取景框: \(snap.visible ? "显示中" : "隐藏")")
            l.append("比例: \(snap.ratioText)")
            l.append("屏幕: \(snap.screenName ?? "未知")")
        } else {
            l.append("取景框: 未初始化")
        }
        return l.joined(separator: "\n")
    }

    // MARK: - 动作

    @objc private func showOverlay() {
        do {
            try overlayController.showUsingLastRatio()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func openColorPanel() {
        overlayController.openColorPanel()
    }

    @objc private func promptForRatioAndShow() {
        let alert = NSAlert()
        alert.messageText = "输入取景比例"
        alert.informativeText = "请输入类似 16:9、9:16、1:1"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "显示")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = settingsStore.current.lastRatioText
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        showZone(using: input.stringValue)
    }

    private func showZone(using ratioText: String) {
        do {
            try overlayController.showZone(using: ratioText)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "FitRecordZone"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

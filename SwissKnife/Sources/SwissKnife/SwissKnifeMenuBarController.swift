import AppKit

/// 整合状态栏与菜单：
/// 一格状态位 = NetWork-WatchDog 状态 emoji + FlowClone 倒计时；
/// 点开为按四模块分组的整合菜单（重复项已删减）。
@MainActor
final class SwissKnifeMenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    func start() {
        NSLog("SwissKnife: 状态栏控制器启动")
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 状态栏

    private func update() {
        let emoji = WatchDogModule.shared.statusEmoji
        let countdown = FlowModule.shared.countdownText()
        guard let button = statusItem.button else {
            NSLog("SwissKnife: statusItem.button 为空")
            return
        }
        button.title = "\(emoji) \(countdown)"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        button.toolTip = toolTipText()
        statusItem.menu = buildMenu()
        NSLog("SwissKnife: 状态栏更新 title=%@ 菜单项=%d", button.title, statusItem.menu?.items.count ?? -1)
    }

    private func toolTipText() -> String {
        var parts: [String] = ["Swiss Knife"]
        parts.append("Flow：\(FlowModule.shared.statusLine())")
        parts.append("网络：\(WatchDogModule.shared.debugSummary().split(separator: "\n").dropFirst().first ?? "")")
        return parts.joined(separator: " | ")
    }

    // MARK: - 整合菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Swiss Knife", action: nil, keyEquivalent: "")
        title.isEnabled = false
        title.attributedTitle = NSAttributedString(
            string: "Swiss Knife",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]
        )
        menu.addItem(title)
        menu.addItem(.separator())

        FlowModule.shared.appendMenuItems(to: menu)
        menu.addItem(.separator())

        WatchDogModule.shared.appendMenuItems(to: menu)
        menu.addItem(.separator())

        WheelTamerModule.shared.appendMenuItems(to: menu)
        menu.addItem(.separator())

        ZoneModule.shared.appendMenuItems(to: menu)
        menu.addItem(.separator())

        StickyNotesModule.shared.appendMenuItems(to: menu)
        menu.addItem(.separator())

        menu.addItem(item("复制调试快照", action: #selector(copySnapshot)))
        menu.addItem(item("设置", action: #selector(showSettings)))
        menu.addItem(item("退出 Swiss Knife", action: #selector(quitApp), keyEquivalent: "q"))
        return menu
    }

    // MARK: - 动作

    /// 四合一调试快照：汇总 Flow / WatchDog / WheelTamer / Zone 状态到剪贴板
    @objc private func copySnapshot() {
        var lines: [String] = []
        lines.append("Swiss Knife 调试快照 \(Date())")
        lines.append("")
        lines.append("【Flow 番茄钟】")
        lines.append(FlowModule.shared.debugSummary())
        lines.append("")
        lines.append("【NetWork-WatchDog 网络看门狗】")
        lines.append(WatchDogModule.shared.debugSummary())
        lines.append("")
        lines.append("【ATAS Wheel Tamer 滚轮倍率】")
        lines.append(WheelTamerModule.shared.debugSummary())
        lines.append("")
        lines.append("【FitRecordZone 取景框】")
        lines.append(ZoneModule.shared.debugSummary())
        lines.append("")
        lines.append("【Reminder 定时提醒】")
        lines.append(ReminderModule.shared.debugSummary())
        lines.append("")
        lines.append("【StickyNotes 便签】")
        lines.append(StickyNotesModule.shared.debugSummary())
        lines.append("")
        lines.append("【StickyNotes 调试日志】")
        lines.append(DebugLog.shared.contents)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func showSettings() {
        WindowManager.showSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }
}

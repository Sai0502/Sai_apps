import AppKit

/// ATAS Wheel Tamer 模块：鼠标滚轮缩放倍率拦截（ATAS / Parallels）。
/// 融合后不创建独立状态栏，菜单分组由 SwissKnife 整合控制器统一承载。
@MainActor
final class WheelTamerModule: NSObject, @preconcurrency WheelTamerDelegate {
    static let shared = WheelTamerModule()

    private let wheelTamer = WheelTamer()
    private let settingsStore = WheelStore.shared

    private let scalePresets: [Double] = [0.5, 0.7, 0.8, 1.0, 2.0, 5.0, 100.0]

    private struct ScaleSelection {
        var kind: TargetKind
        var value: Double
    }

    private override init() {
        super.init()
    }

    // MARK: - 生命周期

    func start() {
        wheelTamer.delegate = self
        wheelTamer.start()
    }

    func stop() {
        wheelTamer.stop()
    }

    func wheelTamerDidUpdate(_ tamer: WheelTamer) {
        // 菜单每次展开时重建，无需主动刷新
    }

    // MARK: - 菜单

    /// 追加 ATAS Wheel Tamer 分组菜单项：模块名 + 重新挂载拦截 + Atas/Parallels 配置
    func appendMenuItems(to menu: NSMenu) {
        menu.addItem(label("ATAS Wheel Tamer"))
        menu.addItem(menuItem("    重新挂载拦截", action: #selector(restartTap)))
        addTargetSection(to: menu, kind: .atas)
        addTargetSection(to: menu, kind: .parallels)
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func targetDisplayName(_ kind: TargetKind) -> String {
        kind == .atas ? "Atas" : "Parallels"
    }

    private func addTargetSection(to menu: NSMenu, kind: TargetKind) {
        let config = settingsStore.current[kind]
        let name = targetDisplayName(kind)
        let marker = config.enabled ? "✅ " : "❌ "

        let header = NSMenuItem(
            title: "    \(marker)\(name) 缩放倍率：\(formatPercent(config.scalePercent))",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        let toggle = menuItem("        启用/禁用", action: #selector(toggleTarget(_:)))
        toggle.representedObject = kind
        menu.addItem(toggle)

        let scaleItem = NSMenuItem(title: "        缩放比例", action: nil, keyEquivalent: "")
        scaleItem.submenu = buildScaleMenu(kind: kind)
        menu.addItem(scaleItem)
    }

    private func buildScaleMenu(kind: TargetKind) -> NSMenu {
        let submenu = NSMenu(title: "缩放比例")
        let config = settingsStore.current[kind]

        let current = NSMenuItem(title: "当前：\(formatPercent(config.scalePercent))", action: nil, keyEquivalent: "")
        current.isEnabled = false
        submenu.addItem(current)
        submenu.addItem(.separator())

        let custom = menuItem("自定义输入...", action: #selector(promptCustomScalePercent(_:)))
        custom.representedObject = kind
        submenu.addItem(custom)
        submenu.addItem(.separator())

        scalePresets.forEach { preset in
            let child = menuItem(formatPercent(preset), action: #selector(selectScalePercent(_:)))
            child.representedObject = ScaleSelection(kind: kind, value: preset)
            child.state = abs(config.scalePercent - preset) < 0.000_001 ? .on : .off
            submenu.addItem(child)
        }
        return submenu
    }

    /// 四合一调试快照的 WheelTamer 部分
    func debugSummary() -> String {
        let s = wheelTamer.currentSnapshot()
        var l: [String] = []
        l.append("ATAS Wheel Tamer")
        l.append("辅助功能授权: \(s.accessibilityTrusted ? "已授权" : "未授权")")
        l.append("事件拦截: \(s.eventTapInstalled && s.eventTapEnabled ? "运行中" : "未运行")")
        l.append("Atas: \(s.atasEnabled ? "启用" : "停用") \(formatPercent(s.atasScalePercent))")
        l.append("Parallels: \(s.parallelsEnabled ? "启用" : "停用") \(formatPercent(s.parallelsScalePercent))")
        l.append("前台目标: \(s.currentFrontmostBundleID)")
        return l.joined(separator: "\n")
    }

    // MARK: - 动作

    @objc private func toggleTarget(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? TargetKind else { return }
        var config = settingsStore.current[kind]
        config.enabled.toggle()
        settingsStore.update { $0[kind] = config }
        wheelTamer.refreshSettings()
    }

    @objc private func selectScalePercent(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ScaleSelection else { return }
        var config = settingsStore.current[selection.kind]
        config.scalePercent = selection.value
        settingsStore.update { $0[selection.kind] = config }
        wheelTamer.refreshSettings()
    }

    @objc private func promptCustomScalePercent(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? TargetKind else { return }
        let name = targetDisplayName(kind)

        let alert = NSAlert()
        alert.messageText = "自定义\(name)鼠标滚轮处理比例"
        alert.informativeText = "可输入 0 到 100，最多一位小数。例如 0.5、0.7、0.8、1、2。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = formatPercentNumber(settingsStore.current[kind].scalePercent)
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let rawText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = parseScalePercent(rawText) else {
            let errorAlert = NSAlert()
            errorAlert.messageText = "输入无效"
            errorAlert.informativeText = "请输入 0 到 100 之间的数字，最多一位小数。"
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "知道了")
            errorAlert.runModal()
            return
        }

        var config = settingsStore.current[kind]
        config.scalePercent = value
        settingsStore.update { $0[kind] = config }
        wheelTamer.refreshSettings()
    }

    @objc private func restartTap() {
        wheelTamer.restart()
    }

    // MARK: - 工具

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func formatPercent(_ value: Double) -> String {
        "\(formatPercentNumber(value))%"
    }

    private func parseScalePercent(_ rawText: String) -> Double? {
        let pattern = #"^(?:100(?:\.0)?|\d{1,2}(?:\.\d)?)$"#
        guard rawText.range(of: pattern, options: .regularExpression) != nil,
              let value = Double(rawText)
        else {
            return nil
        }
        return min(max(value, 0.0), 100.0)
    }

    private func formatPercentNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

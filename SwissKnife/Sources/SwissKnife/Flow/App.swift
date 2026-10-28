import AppKit
import SwiftUI

/// Flow（番茄钟）模块：复用 FlowClone 的 AppState 与计时引擎。
/// 融合后不再使用独立的 SwiftUI 菜单栏，状态栏与菜单由 SwissKnife 整合控制器统一承载。
@MainActor
final class FlowModule: NSObject {
    static let shared = FlowModule()

    private override init() {
        super.init()
    }

    var appState: AppState { AppState.shared }

    func start() {
        appState.notifications.requestAuthorizationIfNeeded()
        appState.handleLaunch()
    }

    // MARK: - 状态栏与菜单数据

    /// 状态栏倒计时文本（如 "24:53"；超过 1 小时为 "1:02:33"）
    func countdownText() -> String {
        formattedTime(appState.remainingSeconds)
    }

    /// 菜单状态行（名称 · 状态 · 倒计时，如 "Flow · 进行中 · 24:58"）
    func statusLine() -> String {
        let time = countdownText()
        switch appState.status {
        case .idle: return "Flow · 待机 · \(time)"
        case .running: return "\(appState.phase.displayName) · 进行中 · \(time)"
        case .paused: return "\(appState.phase.displayName) · 已暂停 · \(time)"
        }
    }

    /// 追加 Flow 分组菜单项：状态行 + 操作行（待机=开始/跳过置灰；进行中=暂停/跳过）
    func appendMenuItems(to menu: NSMenu) {
        let line = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        line.isEnabled = false
        menu.addItem(line)

        menu.addItem(item("    " + primaryActionTitle(), action: #selector(primaryAction)))
        let skip = item("    跳过", action: #selector(skipAction))
        skip.isEnabled = appState.status != .idle && appState.canSkipOrStop
        menu.addItem(skip)
    }

    /// 四合一调试快照的 Flow 部分
    func debugSummary() -> String {
        appState.debugInfo()
    }

    // MARK: - 动作

    private func primaryActionTitle() -> String {
        switch appState.status {
        case .idle: return "开始"
        case .running: return "暂停"
        case .paused: return "继续"
        }
    }

    @objc private func primaryAction() {
        switch appState.status {
        case .idle, .paused: appState.start()
        case .running: appState.pause()
        }
    }

    @objc private func skipAction() {
        appState.skip()
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

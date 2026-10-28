import Foundation
import UserNotifications

/// 本地通知服务：Flow 完成 / 休息完成，含通知按钮
@MainActor
final class NotificationsService: NSObject, UNUserNotificationCenterDelegate {

    static let flowCompletedID = "flow.completed"
    static let breakCompletedID = "break.completed"
    static let actionStart = "ACTION_START"
    static let actionSkip = "ACTION_SKIP"
    static let actionOpen = "ACTION_OPEN"

    override init() {
        super.init()
    }

    private func ensureDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        ensureDelegate()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                NSLog("通知授权请求失败: %@", error.localizedDescription)
            }
        }
    }

    func notifyFlowCompleted() {
        send(title: "做得好！Flow 完成了。", body: "是时候休息了。", identifier: Self.flowCompletedID)
    }

    func notifyBreakCompleted() {
        send(title: "休息时间结束了。", body: "让我们专注！", identifier: Self.breakCompletedID)
    }

    private func send(title: String, body: String, identifier: String) {
        guard AppState.shared.notificationsEnabled else { return }
        ensureDelegate()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // 不携带系统通知声音：完成/休息提示音统一由 NSSound 播放（尊重音量设置），避免双声音
            content.categoryIdentifier = "FLOW_TIMER"

            let start = UNNotificationAction(identifier: Self.actionStart, title: "开始", options: [])
            let skip = UNNotificationAction(identifier: Self.actionSkip, title: "跳过", options: [])
            let open = UNNotificationAction(identifier: Self.actionOpen, title: "打开", options: [])
            let category = UNNotificationCategory(identifier: "FLOW_TIMER",
                                                  actions: [start, skip, open],
                                                  intentIdentifiers: [],
                                                  options: [])
            center.setNotificationCategories([category])

            let request = UNNotificationRequest(identifier: identifier,
                                                content: content,
                                                trigger: nil)
            center.add(request) { error in
                if let error = error {
                    NSLog("通知发送失败: %@", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 通知点击

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor in
            let state = AppState.shared
            switch action {
            case Self.actionStart:
                state.start()
            case Self.actionSkip:
                state.skip()
            case Self.actionOpen, UNNotificationDefaultActionIdentifier:
                WindowManager.showSettingsWindow()
            default:
                break
            }
        }
        completionHandler()
    }

    // 前台时也展示通知
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

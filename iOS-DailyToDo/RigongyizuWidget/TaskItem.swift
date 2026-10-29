import Foundation
import UserNotifications

/// 单个任务：可被 App 与 Widget 共享读写
struct TaskItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var title: String
    var day: String?            // "yyyy-MM-dd"，nil = 无日期
    var hour: Int?              // 0-23，nil = 无提醒时间
    var minute: Int?            // 0-59
    var done: Bool = false
    var pendingDelete: Bool = false   // 小组件勾选后待删除
    var pendingDeleteAt: Date?
    var createdAt: Date = Date()

    var hasTime: Bool { hour != nil && minute != nil }

    var timeText: String {
        guard hasTime, let hour, let minute else { return "" }
        return String(format: "%02d:%02d", hour, minute)
    }

    var reminderDate: Date? {
        guard let day, hasTime, let hour, let minute else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        guard let base = f.date(from: day) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base)
    }
}

/// 共享数据读写：优先 App Group，兜底 Application Support
enum TaskIO {
    static let groupID = "group.com.jiangsai.rigongyizu"
    static let fileName = "tasks.json"

    static var fileURL: URL {
        let fm = FileManager.default
        if let c = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return c.appendingPathComponent(fileName)
        }
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> [TaskItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([TaskItem].self, from: data)) ?? []
    }

    static func save(_ tasks: [TaskItem]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(tasks) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 清理过期的"待删除"任务（5 秒后删除逻辑）
    static func purgeExpired(_ tasks: [TaskItem]) -> [TaskItem] {
        var changed = false
        let kept = tasks.filter { item in
            if item.pendingDelete, let at = item.pendingDeleteAt, Date() >= at {
                changed = true
                return false
            }
            return true
        }
        if changed { save(kept) }
        return kept
    }
}

/// 本地通知调度：任务的 day+hour+minute 即提醒时间
enum ReminderScheduler {
    /// App 启动时请求通知权限
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 调度任务提醒（先移除旧的同 id 通知再按当前状态调度）
    static func schedule(_ task: TaskItem) {
        cancel(task)
        guard let date = task.reminderDate,
              !task.done,
              date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? "日拱一卒" : task.title
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// 移除任务提醒（删除/完成/改时间时）
    static func cancel(_ task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
}

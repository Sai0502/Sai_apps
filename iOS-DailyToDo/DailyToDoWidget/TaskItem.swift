import Foundation
import UserNotifications

/// 单个任务：可被 App 与 Widget 共享读写
/// ⚠️ 本文件在 DailyToDo/ 与 DailyToDoWidget/ 各有一份完全相同的副本（两个 target 各自编译，无法共享同一文件），
///    改一份必须同步改另一份，否则 App 与小组件的行为会分叉。
struct TaskItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var title: String
    var day: String?            // "yyyy-MM-dd"，nil = 无日期
    var hour: Int?              // 0-23，nil = 无提醒时间
    var minute: Int?            // 0-59
    var done: Bool
    /// 小组件撤回窗口的截止时间：**只有在小组件里勾选时才会写入**。
    /// 窗口内该任务仍显示在小组件上（带对勾、带删除线），期间再点一次即撤销；
    /// 到点后从小组件消失。任务本身不会被删除。
    /// 在 App 里勾选不会写入这个字段 —— App 里已经勾完的任务，小组件立刻不再显示。
    var graceUntil: Date?
    var createdAt: Date

    /// 小组件里勾选后保留的秒数：期间再点一次即撤回
    static let undoGrace: TimeInterval = 5

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

    /// 是否处于小组件的「撤回窗口」（只影响小组件是否展示，不影响 App 列表）
    func inUndoGrace(at now: Date = Date()) -> Bool {
        guard done, let until = graceUntil else { return false }
        return now < until
    }

    // MARK: - 容错解码
    // 合成的 Decodable 不会使用属性默认值：老文件 / 缺字段 / 损坏的文件都会抛 keyNotFound，
    // 而 load() 一旦返回空数组，下一次 commit 就会把用户全部任务覆盖成空。
    // 所以这里逐字段做「缺了就取默认值」的容错解码。

    init(id: UUID, title: String, day: String?, hour: Int?, minute: Int?,
         done: Bool = false, graceUntil: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.day = day
        self.hour = hour
        self.minute = minute
        self.done = done
        self.graceUntil = graceUntil
        self.createdAt = createdAt
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
        init(_ string: String) { self.stringValue = string; self.intValue = nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)

        id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        title = (try? c.decode(String.self, forKey: AnyKey("title"))) ?? ""
        day = try? c.decode(String.self, forKey: AnyKey("day"))
        hour = try? c.decode(Int.self, forKey: AnyKey("hour"))
        minute = try? c.decode(Int.self, forKey: AnyKey("minute"))
        done = (try? c.decode(Bool.self, forKey: AnyKey("done"))) ?? false
        createdAt = (try? c.decode(Date.self, forKey: AnyKey("createdAt"))) ?? Date()
        graceUntil = try? c.decode(Date.self, forKey: AnyKey("graceUntil"))

        // 旧版「小组件勾选后 5 秒删除」留下的待删任务：迁移为普通已完成任务，
        // 不再删除，让 App 列表里能重新看到它。迁移来的没有撤回窗口，小组件不展示。
        let legacyPendingDelete = (try? c.decode(Bool.self, forKey: AnyKey("pendingDelete"))) ?? false
        if legacyPendingDelete {
            done = true
            graceUntil = nil
        }
    }
}

/// 小组件的展示规则（纯 Foundation，不依赖 WidgetKit，便于单独自测）
enum WidgetFeed {
    /// 小组件该显示哪些任务：所有未完成的任务 + 刚在小组件里勾选、还在 5 秒撤回窗口内的任务。
    /// 在 App 里勾选的任务不写 graceUntil，所以它们不会出现在这里。
    static func visible(_ all: [TaskItem], at now: Date) -> [TaskItem] {
        all.filter { $0.inUndoGrace(at: now) || !$0.done }
            .sorted { a, b in
                // 日期最新在前；同日按时间早->晚；无日期排最后
                let da = a.day ?? ""
                let db = b.day ?? ""
                if da != db { return da > db }
                let ta = (a.hour ?? 24) * 60 + (a.minute ?? 0)
                let tb = (b.hour ?? 24) * 60 + (b.minute ?? 0)
                if ta == tb { return a.createdAt < b.createdAt }
                return ta < tb
            }
    }

    /// 时间线上还需要补的「切换时刻」：每个撤回窗口的到点时刻（未到点的、升序）。
    /// 把这些时刻直接排进 Timeline，即使 intent 里那次 reload 被系统吞掉，
    /// 到点后系统也会自己切到下一条 entry，把刚勾选的任务撤下。
    static func cutovers(after now: Date, in all: [TaskItem]) -> [Date] {
        all.compactMap { task -> Date? in
            guard task.done, let until = task.graceUntil, until > now else { return nil }
            return until
        }
        .sorted()
    }
}

/// 共享数据读写：优先 App Group，兜底 Application Support
enum TaskIO {
    /// 历史标识符：用户看不到，且一旦改动就会换掉共享容器，导致现有任务读不到，故保持不变。
    static let groupID = "group.com.sai.dailytodo"
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

    /// 上一次成功解码的内容，主文件损坏时用它兜底
    static var backupURL: URL { fileURL.appendingPathExtension("bak") }

    static func load() -> [TaskItem] {
        if let tasks = decode(fileURL) { return tasks }
        if let tasks = decode(backupURL) {
            save(tasks)   // 用备份把主文件修回来
            return tasks
        }
        return []
    }

    private static func decode(_ url: URL) -> [TaskItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([TaskItem].self, from: data)
    }

    static func save(_ tasks: [TaskItem]) {
        // 先留一份能正常解码的旧内容作为兜底
        if let old = try? Data(contentsOf: fileURL),
           (try? JSONDecoder().decode([TaskItem].self, from: old)) != nil {
            try? old.write(to: backupURL, options: .atomic)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(tasks) {
            try? data.write(to: fileURL, options: .atomic)
        }
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
        content.title = task.title.isEmpty ? "DailyToDo" : task.title
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

    /// 全量重排：清掉本 App 所有待发提醒，再按当前任务状态重新调度。
    /// 小组件进程无法操作通知中心（那边的 schedule/cancel 都是空操作），
    /// 所以小组件侧改出来的状态，由 App 在启动/回前台时统一收敛。
    static func resync(_ tasks: [TaskItem]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
            for task in tasks where !task.done {
                schedule(task)
            }
        }
    }
}

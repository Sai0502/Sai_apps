import AppIntents
import WidgetKit

/// 小组件点击勾选框时的动作：
/// - 未完成 -> 标记完成并进入 5 秒待删除
/// - 待删除中 -> 取消（恢复未完成）
/// - 已过期待删除 -> 真正删除
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "切换任务"
    static var description = IntentDescription("勾选、取消或删除任务")

    @Parameter(title: "任务ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        var tasks = TaskIO.purgeExpired(TaskIO.load())
        if let i = tasks.firstIndex(where: { $0.id.uuidString == taskID }) {
            let item = tasks[i]
            if item.pendingDelete {
                if let at = item.pendingDeleteAt, Date() >= at {
                    tasks.remove(at: i)
                    ReminderScheduler.cancel(item)
                } else {
                    tasks[i].done = false
                    tasks[i].pendingDelete = false
                    tasks[i].pendingDeleteAt = nil
                    ReminderScheduler.schedule(tasks[i])
                }
            } else if item.done {
                tasks[i].done = false
                ReminderScheduler.schedule(tasks[i])
            } else {
                tasks[i].done = true
                tasks[i].pendingDelete = true
                tasks[i].pendingDeleteAt = Date().addingTimeInterval(5)
                ReminderScheduler.cancel(tasks[i])
            }
            TaskIO.save(tasks)
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}

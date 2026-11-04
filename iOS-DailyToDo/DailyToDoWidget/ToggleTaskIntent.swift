import AppIntents
import WidgetKit

/// 小组件里点勾选框：切换完成状态。
/// 勾选后任务先在小组件里保留 5 秒（带对勾、带删除线），期间再点一次即撤销；
/// 超过 5 秒自动从小组件消失，但任务本身不会被删除，App 列表里仍显示为已完成。
/// 在 App 里勾选的任务不会写入 graceUntil —— 那种勾选的热任务立刻从小组件消失。
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "切换任务"
    static var description = IntentDescription("勾选或取消勾选任务")

    @Parameter(title: "任务ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        var tasks = TaskIO.load()
        guard let i = tasks.firstIndex(where: { $0.id.uuidString == taskID }) else {
            return .result()
        }

        let done = !tasks[i].done
        tasks[i].done = done
        // 只有小组件勾选才给 5 秒撤回窗口：窗口内仍显示（带对勾+删除线），到点后消失
        tasks[i].graceUntil = done ? Date().addingTimeInterval(TaskItem.undoGrace) : nil
        TaskIO.save(tasks)

        // 交互式小组件里 reloadTimelines 有时会被系统合并/丢弃（表现为：点了没删除线、5 秒也不消失）。
        // 这里先立刻刷一次，再等一拍补刷一次，让扩展进程在这段时间内保持存活以提高命中率。
        // 等待从 400ms 缩到 150ms：缩短点击到勾选的可感知延迟（5 秒消失由时间线预埋条目兜底）。
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        try? await Task.sleep(for: .milliseconds(150))
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)

        return .result()
    }
}

import Foundation
import Combine
import WidgetKit

/// 数据仓库：App 内唯一数据源，变更即落盘并刷新小组件
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var searchText: String = ""

    init() {
        tasks = TaskIO.load()
    }

    var filtered: [TaskItem] {
        let t = searchText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return tasks }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(t) }
    }

    func commit() {
        TaskIO.save(tasks)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func add(_ item: TaskItem) {
        tasks.append(item)
        commit()
        ReminderScheduler.schedule(item)
    }

    func update(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[i] = item
        commit()
        ReminderScheduler.schedule(item)
    }

    func delete(_ item: TaskItem) {
        tasks.removeAll { $0.id == item.id }
        commit()
        ReminderScheduler.cancel(item)
    }

    /// 主列表勾选 = 完成/取消完成（完成项保留在列表里，只影响小组件是否展示）
    func toggleDone(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        let done = !tasks[i].done
        tasks[i].done = done
        // 在 App 里勾完的任务，小组件立刻不再显示（不给撤回窗口，撤回就在 App 里做）
        tasks[i].graceUntil = nil
        commit()
        if done {
            ReminderScheduler.cancel(tasks[i])
        } else {
            ReminderScheduler.schedule(tasks[i])
        }
    }

    /// 重读磁盘数据（回前台时同步小组件侧的修改）
    func reload() {
        tasks = TaskIO.load()
    }
}

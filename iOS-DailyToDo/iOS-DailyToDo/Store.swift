import Foundation
import Combine
import WidgetKit

/// 数据仓库：App 内唯一数据源，变更即落盘并刷新小组件
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var searchText: String = ""

    init() {
        tasks = TaskIO.purgeExpired(TaskIO.load())
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

    /// 主列表勾选 = 完成/取消完成
    func toggleDone(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[i].done.toggle()
        if !tasks[i].done {
            tasks[i].pendingDelete = false
            tasks[i].pendingDeleteAt = nil
        }
        commit()
        if tasks[i].done {
            ReminderScheduler.cancel(tasks[i])
        } else {
            ReminderScheduler.schedule(tasks[i])
        }
    }

    /// 进入前台/定时清理过期的待删除任务
    func purgeExpired() {
        let before = tasks.count
        tasks = TaskIO.purgeExpired(tasks)
        if tasks.count != before { commit() }
    }

    /// 重读磁盘数据（回前台时同步小组件侧的修改）
    func reload() {
        tasks = TaskIO.purgeExpired(TaskIO.load())
    }
}

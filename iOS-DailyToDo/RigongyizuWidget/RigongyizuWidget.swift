import WidgetKit
import SwiftUI

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let nextRefresh: Date
}

/// 小组件数据源：读取共享文件，展示全部待办（日期最新在前）
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), tasks: [], nextRefresh: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(entries: [entry], policy: .after(entry.nextRefresh)))
    }

    private func makeEntry() -> TaskEntry {
        let tasks = TaskIO.purgeExpired(TaskIO.load())
            .sorted { a, b in
                // 日期最新在前；同日按时间早->晚；无日期排最后
                let da = a.day ?? ""
                let db = b.day ?? ""
                if da != db { return da > db }
                let ta = (a.hour ?? 24) * 60 + (a.minute ?? 0)
                let tb = (b.hour ?? 24) * 60 + (b.minute ?? 0)
                return ta < tb
            }
        // 若存在待删除任务，安排在删除时间后刷新一次
        var next = Date().addingTimeInterval(300)
        for t in tasks where t.pendingDelete {
            if let at = t.pendingDeleteAt, at > Date() {
                next = min(next, at.addingTimeInterval(1))
            }
        }
        return TaskEntry(date: Date(), tasks: tasks, nextRefresh: next)
    }
}

struct RigongyizuWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                Text("暂无任务")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                Spacer(minLength: 0)
            } else {
                let limit = family == .systemSmall ? 4 : (family == .systemMedium ? 6 : 10)
                ForEach(entry.tasks.prefix(limit)) { task in
                    WidgetRow(task: task)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(red: 0.05, green: 0.05, blue: 0.06)
        }
    }
}

struct WidgetRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTaskIntent(taskID: task.id.uuidString)) {
                ZStack {
                    Circle()
                        .strokeBorder(task.done ? Color.orange : Color.gray.opacity(0.7),
                                      lineWidth: 1.5)
                        .frame(width: 17, height: 17)
                    if task.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title.isEmpty ? "未命名任务" : task.title)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .strikethrough(task.done, color: .gray)
                    .lineLimit(1)
                if task.hasTime {
                    Text("\(dateLabel) \(task.timeText)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 小组件无日期分组，故每行在时间前补上日期
    private var dateLabel: String {
        guard let day = task.day else { return "" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let d = fmt.date(from: day) else { return day }
        let today = cal.startOfDay(for: Date())
        let dayStart = cal.startOfDay(for: d)
        if dayStart == today { return "今天" }
        if dayStart == cal.date(byAdding: .day, value: 1, to: today)! { return "明天" }
        if dayStart == cal.date(byAdding: .day, value: -1, to: today)! { return "昨天" }
        let out = DateFormatter()
        out.dateFormat = "M月d日"
        out.locale = Locale(identifier: "zh_CN")
        return out.string(from: d)
    }
}

@main
struct RigongyizuWidget: Widget {
    let kind = "RigongyizuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RigongyizuWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("日拱一卒")
        .description("全部待办，点击对勾可直接完成任务")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

import WidgetKit
import SwiftUI

/// 小组件 kind：App/Intent 刷新小组件时也用这个常量，避免两处字符串写错
let widgetKind = "DailyToDoWidget"

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
}

/// 小组件数据源：只展示待办；刚在小组件里勾选的任务保留 5 秒撤回窗口（带对勾+删除线），到点后消失
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), tasks: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let now = Date()
        var entries = [entry(at: now)]
        var lastDate = now

        // 关键：把「撤回窗口到点」这件事排进时间线本身。
        // 这样即使小组件进程里那次 reloadTimelines 被系统合并/丢掉，
        // 到点后系统也会自动切到下一条 entry，把刚勾选的任务撤下——不需要第二次刷新。
        let expiries = WidgetFeed.cutovers(after: now, in: TaskIO.load())

        for until in expiries {
            let cut = until.addingTimeInterval(0.5)   // 留半秒，确保已经越过截止时间
            if cut > lastDate {
                entries.append(entry(at: cut))
                lastDate = cut
            }
        }

        // 跨午夜补一条，让「今天/明天/昨天」跟着日期变
        if let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ), midnight > lastDate {
            entries.append(entry(at: midnight))
        }

        let policy: TimelineReloadPolicy = entries.count > 1
            ? .atEnd
            : .after(now.addingTimeInterval(1800))
        completion(Timeline(entries: entries, policy: policy))
    }

    /// 以某个时刻为「现在」，算出那一刻小组件该显示什么
    private func entry(at now: Date) -> TaskEntry {
        TaskEntry(date: now, tasks: WidgetFeed.visible(TaskIO.load(), at: now))
    }
}

struct DailyToDoWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TaskEntry

    private var limit: Int {
        switch family {
        case .systemSmall: return 4
        case .systemMedium: return 6
        default: return 10
        }
    }

    var body: some View {
        // 行间距优先 10pt（比原来的 6pt 更透气）；小号组件在「4 条带日期任务 + 还有 N 项」
        // 同时出现时空间放不下，ViewThatFits 自动退回 6pt，避免底部内容被截断。
        ViewThatFits(in: .vertical) {
            list(spacing: 10)
            list(spacing: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(red: 0.05, green: 0.05, blue: 0.06)
        }
    }

    @ViewBuilder
    private func list(spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                Text("暂无待办")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    WidgetRow(task: task, now: entry.date)
                }
                if entry.tasks.count > limit {
                    Text("还有 \(entry.tasks.count - limit) 项")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct WidgetRow: View {
    let task: TaskItem
    /// 这一帧对应的时刻，用于算「今天/明天/昨天」
    let now: Date

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
                    .foregroundColor(task.done ? Color.gray.opacity(0.6) : .white)
                    .strikethrough(task.done, color: .gray)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 小组件无日期分组，故每行在时间前补上日期；只有日期没有时间的任务也显示日期
    private var subtitle: String {
        guard task.day != nil else { return task.hasTime ? task.timeText : "" }
        let label = dateLabel
        return task.hasTime ? "\(label) \(task.timeText)" : label
    }

    private var dateLabel: String {
        guard let day = task.day else { return "" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let d = fmt.date(from: day) else { return day }
        let today = cal.startOfDay(for: now)
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
struct DailyToDoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: Provider()) { entry in
            DailyToDoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DailyToDo")
        .description("全部待办，点击对勾可直接完成任务")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

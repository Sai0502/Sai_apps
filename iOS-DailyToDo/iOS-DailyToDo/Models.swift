import Foundation

/// 按天分组后的一个组
struct TaskGroup: Identifiable {
    var id: String { dayKey }
    var dayKey: String
    var title: String
    var items: [TaskItem]
}

extension Array where Element == TaskItem {
    /// 分组规则：日期最新在前；组内按提醒时间升序（无时间排最后）；无日期任务放最后
    func groupedByDay() -> [TaskGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let todayKey = fmt.string(from: today)
        let tomorrowKey = fmt.string(from: cal.date(byAdding: .day, value: 1, to: today)!)
        let yesterdayKey = fmt.string(from: cal.date(byAdding: .day, value: -1, to: today)!)

        var dated: [String: [TaskItem]] = [:]
        var undated: [TaskItem] = []
        for t in self {
            if let d = t.day {
                dated[d, default: []].append(t)
            } else {
                undated.append(t)
            }
        }

        var groups: [TaskGroup] = []
        for key in dated.keys.sorted(by: >) {
            let items = (dated[key] ?? []).sorted { a, b in
                let at = (a.hour ?? 24) * 60 + (a.minute ?? 0)
                let bt = (b.hour ?? 24) * 60 + (b.minute ?? 0)
                if at == bt { return a.createdAt < b.createdAt }
                return at < bt
            }
            var title: String
            if key == todayKey {
                title = "今天"
            } else if key == tomorrowKey {
                title = "明天"
            } else if key == yesterdayKey {
                title = "昨天"
            } else {
                title = Self.displayDate(key)
            }
            groups.append(TaskGroup(dayKey: key, title: title, items: items))
        }

        if !undated.isEmpty {
            let items = undated.sorted { $0.createdAt < $1.createdAt }
            groups.append(TaskGroup(dayKey: "none", title: "无日期", items: items))
        }
        return groups
    }

    private static func displayDate(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: key) else { return key }
        let out = DateFormatter()
        out.dateFormat = "M月d日 EEEE"
        out.locale = Locale(identifier: "zh_CN")
        return out.string(from: d)
    }
}

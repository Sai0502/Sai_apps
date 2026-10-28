import Foundation

// MARK: - 定时播放（定时提醒）

/// 定时播放设置：每天在指定时刻（时:分）触发一次提醒。
/// 与 Flow 计时引擎完全独立，不依赖计时状态。
/// 每行三项：时间（必选，未设置则整行不触发）+ 音频/视频 + 图片（可单选或同选）。
struct ScheduledPlayback: Identifiable, Codable, Equatable {
    var id: Int                       // 行号（0/1/2/3/4）
    var timeSet: Bool = false         // 是否已设置时间；false = 整行不触发
    var hour: Int = 7                 // 小时 0–23
    var minute: Int = 0               // 分钟 0–59
    var avPath: String = ""           // 音频/视频文件路径；空 = 未选择
    var imagePath: String = ""        // 图片文件路径；空 = 未选择
    var lastTriggeredDay: String? = nil  // 已触发日期（yyyy-MM-dd），避免同一天重复提醒

    /// 生效星期：7 个布尔值，下标 0=周一 … 6=周日；true = 当天生效。默认全选 = 每天生效。
    /// 旧配置缺少该键时保留默认值，自动按「每天」处理，兼容升级。
    var weekdays: [Bool] = [true, true, true, true, true, true, true]

    /// 今天（按本地日历）是否在该行的生效星期内；weekdays 长度异常时按每天处理
    var isActiveToday: Bool {
        guard weekdays.count == 7 else { return true }
        let weekdayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7   // 周一→0 … 周日→6
        return weekdays[weekdayIndex]
    }

    /// 整行是否生效：必须已设置时间，且至少选了音频/视频或图片之一
    var isConfigured: Bool { timeSet && (!avPath.isEmpty || !imagePath.isEmpty) }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
    var avFileName: String { (avPath as NSString).lastPathComponent }
    var imageFileName: String { (imagePath as NSString).lastPathComponent }
}

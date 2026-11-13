import Foundation

/// FitRecordZone 模块日志：统一走 RecentLinesLogger。
final class ZoneLogger: RecentLinesLogger {
    static let shared = ZoneLogger(directoryName: "FitRecordZone")

    private init(directoryName: String) {
        super.init(directoryName: directoryName)
    }
}

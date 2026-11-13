import Foundation

/// ATASWheelTamer 模块日志：统一走 RecentLinesLogger。
final class WheelLogger: RecentLinesLogger {
    static let shared = WheelLogger(directoryName: "ATASWheelTamer")

    private init(directoryName: String) {
        super.init(directoryName: directoryName)
    }
}

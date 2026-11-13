import Foundation

/// FitRecordZone 设置存储：统一走 JSONFileStore。
final class ZoneStore: JSONFileStore<ZoneSettings> {
    static let shared = ZoneStore()

    private init() {
        super.init(directoryName: "FitRecordZone", defaultValue: ZoneSettings())
    }
}

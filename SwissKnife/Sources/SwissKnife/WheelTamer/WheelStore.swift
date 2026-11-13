import Foundation

/// ATASWheelTamer 设置存储：统一走 JSONFileStore。
final class WheelStore: JSONFileStore<WheelSettings> {
    static let shared = WheelStore()

    private init() {
        super.init(directoryName: "ATASWheelTamer", defaultValue: WheelSettings())
    }
}

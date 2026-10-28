import Foundation

struct AppConfiguration {
    let settings: WatchDogSettings
    let checkInterval: TimeInterval
    let failureThreshold: Int
    let maxReconnectAttempts: Int
    let connectVerifySeconds: Int
    let connectProgressGraceSeconds: Int
    let usbVerifySeconds: Int
    let usbProgressGraceSeconds: Int
    let testURLs: [URL]
    let logDirectory: URL

    var wifiName: String { settings.wifiName }
    var wifiPassword: String { settings.wifiPassword }

    static var `default`: AppConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = WatchDogSettings(
            defaultWiFiName: ProcessInfo.processInfo.environment["NWD_WIFI_NAME"] ?? "Sai",
            defaultWiFiPassword: ProcessInfo.processInfo.environment["NWD_WIFI_PASSWORD"] ?? "11223344"
        )
        return AppConfiguration(
            settings: settings,
            checkInterval: 1,
            failureThreshold: 2,
            maxReconnectAttempts: 3,
            connectVerifySeconds: 3,
            connectProgressGraceSeconds: 12,
            usbVerifySeconds: 6,
            usbProgressGraceSeconds: 10,
            testURLs: [
                URL(string: "https://captive.apple.com/hotspot-detect.html")!,
                URL(string: "https://www.baidu.com/favicon.ico")!,
                URL(string: "https://connectivitycheck.gstatic.com/generate_204")!,
                URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!
            ],
            logDirectory: home.appendingPathComponent("Desktop/自动联网日志", isDirectory: true)
        )
    }
}

import Foundation

struct AppConfiguration {
    let checkInterval: TimeInterval
    let offlineAlertThreshold: Int
    let testURLs: [URL]

    static var `default`: AppConfiguration {
        AppConfiguration(
            checkInterval: 1,
            offlineAlertThreshold: 3,
            testURLs: [
                URL(string: "https://connectivitycheck.gstatic.com/generate_204")!,
                URL(string: "https://captive.apple.com/hotspot-detect.html")!,
                URL(string: "https://www.baidu.com/favicon.ico")!,
                URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!
            ]
        )
    }
}

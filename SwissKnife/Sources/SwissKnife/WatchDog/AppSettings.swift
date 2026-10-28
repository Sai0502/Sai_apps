import Foundation

final class WatchDogSettings: @unchecked Sendable {
    private enum Key {
        static let wifiName = "wifiName"
        static let wifiPassword = "wifiPassword"
    }

    private let queue = DispatchQueue(label: "network-watchdog.settings")
    private let defaults: UserDefaults
    private let defaultWiFiName: String
    private let defaultWiFiPassword: String

    init(
        defaults: UserDefaults = .standard,
        defaultWiFiName: String,
        defaultWiFiPassword: String
    ) {
        self.defaults = defaults
        self.defaultWiFiName = defaultWiFiName
        self.defaultWiFiPassword = defaultWiFiPassword
    }

    var wifiName: String {
        queue.sync {
            let saved = defaults.string(forKey: Key.wifiName)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return saved?.isEmpty == false ? saved! : defaultWiFiName
        }
    }

    var wifiPassword: String {
        queue.sync {
            defaults.string(forKey: Key.wifiPassword) ?? defaultWiFiPassword
        }
    }

    func updateWiFi(name: String, password: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        queue.sync {
            defaults.set(cleanName, forKey: Key.wifiName)
            defaults.set(password, forKey: Key.wifiPassword)
        }
    }
}

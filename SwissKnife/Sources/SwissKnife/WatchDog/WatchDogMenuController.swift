import Foundation

/// NetWork-WatchDog 模块：只监控网络通断。
/// 状态栏显示 🟢/❌，连续断网若干秒后响一声提醒用户，是否恢复由用户自己决定。
@MainActor
final class WatchDogModule: NSObject, NetworkStateObserver {
    static let shared = WatchDogModule.make()

    private let configuration: AppConfiguration
    private let stateMachine: NetworkStateMachine
    private let monitor: NetworkMonitor
    private var latestState: NetworkState = .online

    // MARK: - 组装

    static func make() -> WatchDogModule {
        let configuration = AppConfiguration.default
        let internetChecker = InternetChecker(configuration: configuration)
        let notificationManager = NotificationManager()
        let stateMachine = NetworkStateMachine()
        let monitor = NetworkMonitor(
            configuration: configuration,
            stateMachine: stateMachine,
            internetChecker: internetChecker,
            notificationManager: notificationManager
        )

        return WatchDogModule(
            configuration: configuration,
            stateMachine: stateMachine,
            monitor: monitor
        )
    }

    private init(
        configuration: AppConfiguration,
        stateMachine: NetworkStateMachine,
        monitor: NetworkMonitor
    ) {
        self.configuration = configuration
        self.stateMachine = stateMachine
        self.monitor = monitor
        super.init()
        stateMachine.addObserver(self)
    }

    // MARK: - 生命周期

    func start() {
        monitor.start()
    }

    func stop() {
        monitor.stop()
    }

    func networkStateDidChange(_ state: NetworkState) {
        latestState = state
    }

    // MARK: - 状态栏

    /// 两种状态：能上网 = 🟢；不能上网 = ❌
    var statusEmoji: String {
        latestState == .online ? "🟢" : "❌"
    }

    /// 四合一调试快照的 WatchDog 部分
    func debugSummary() -> String {
        var l: [String] = []
        l.append("NetWork-WatchDog")
        l.append("状态: \(statusEmoji) \(latestState.rawValue)")
        l.append("断网提醒: 连续 \(configuration.offlineAlertThreshold) 秒无网络时响铃")
        return l.joined(separator: "\n")
    }
}

import Foundation

/// 周期性检测网络连通性：连续失败达到阈值后响铃提醒，不做任何自动切换/重连。
final class NetworkMonitor: @unchecked Sendable {
    private let configuration: AppConfiguration
    private let stateMachine: NetworkStateMachine
    private let internetChecker: InternetChecker
    private let notificationManager: NotificationManager
    private let queue = DispatchQueue(label: "network-watchdog.monitor")
    private var timer: DispatchSourceTimer?
    private var failureCount = 0
    private var alertPlayed = false

    init(
        configuration: AppConfiguration,
        stateMachine: NetworkStateMachine,
        internetChecker: InternetChecker,
        notificationManager: NotificationManager
    ) {
        self.configuration = configuration
        self.stateMachine = stateMachine
        self.internetChecker = internetChecker
        self.notificationManager = notificationManager
    }

    func start() {
        queue.async {
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.configuration.checkInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func tick() {
        if internetChecker.isReachable() {
            failureCount = 0
            alertPlayed = false
            stateMachine.send(.internetAvailable)
            return
        }

        failureCount += 1

        if failureCount == 1 {
            stateMachine.send(.internetLost)
        }

        guard failureCount >= configuration.offlineAlertThreshold, !alertPlayed else {
            return
        }

        alertPlayed = true
        stateMachine.send(.offlineConfirmed)
        notificationManager.playOfflineAlert()
    }
}

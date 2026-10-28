import Foundation

final class NetworkMonitor: @unchecked Sendable {
    private let configuration: AppConfiguration
    private let stateMachine: NetworkStateMachine
    private let internetChecker: InternetChecker
    private let interfaceManager: NetworkInterfaceManager
    private let recoveryCoordinator: RecoveryCoordinator
    private let logger: EventLogger
    private let queue = DispatchQueue(label: "network-watchdog.monitor")
    private var timer: DispatchSourceTimer?
    private var failureCount = 0
    private var manualActionRequired = false
    private var recoveryInProgress = false
    private var abnormalEpisodeActive = false

    init(
        configuration: AppConfiguration,
        stateMachine: NetworkStateMachine,
        internetChecker: InternetChecker,
        interfaceManager: NetworkInterfaceManager,
        recoveryCoordinator: RecoveryCoordinator,
        logger: EventLogger
    ) {
        self.configuration = configuration
        self.stateMachine = stateMachine
        self.internetChecker = internetChecker
        self.interfaceManager = interfaceManager
        self.recoveryCoordinator = recoveryCoordinator
        self.logger = logger
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
        guard !recoveryInProgress else { return }

        let defaultInterface = interfaceManager.defaultInterface()
        let defaultType = interfaceManager.interfaceType(defaultInterface).rawValue
        let defaultIPv4 = interfaceManager.ipv4Address(for: defaultInterface)
        let defaultGateway = interfaceManager.defaultGateway()

        if internetChecker.isReachable() {
            if abnormalEpisodeActive {
                logger.log("ONLINE interface=\(defaultInterface ?? "unknown") type=\(defaultType) ipv4=\(defaultIPv4 ?? "none") gateway=\(defaultGateway ?? "none") internet=ok action=none")
                abnormalEpisodeActive = false
            }
            failureCount = 0
            manualActionRequired = false
            stateMachine.send(.internetAvailable)
            return
        }

        abnormalEpisodeActive = true

        if manualActionRequired {
            logger.log("WAITING_MANUAL_ACTION network=\(configuration.wifiName) internet=offline sound=already_played action=continue_monitoring")
            stateMachine.send(.manualRequired)
            return
        }

        failureCount += 1
        logger.log("VERIFYING_OFFLINE failure=\(failureCount)/\(configuration.failureThreshold) interface=\(defaultInterface ?? "none") type=\(defaultType) internet=unreachable")
        stateMachine.send(.internetLost)

        if failureCount >= configuration.failureThreshold {
            logger.log("OFFLINE_CONFIRMED interface=\(defaultInterface ?? "none") type=\(defaultType) action=start_usb_first_recovery")
            stateMachine.send(.offlineConfirmed)
            recoveryInProgress = true
            let ok = recoveryCoordinator.recoverWithUSBFirstThenWiFi()
            manualActionRequired = !ok
            failureCount = 0
            recoveryInProgress = false
        }
    }
}

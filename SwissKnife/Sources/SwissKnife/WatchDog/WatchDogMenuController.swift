import AppKit

/// NetWork-WatchDog 模块：网络与 iPhone USB 共享监控 + 断线自动恢复。
/// 融合后不创建独立状态栏，只提供状态 emoji、菜单分组与 WiFi 配置能力。
@MainActor
final class WatchDogModule: NSObject, NetworkStateObserver {
    static let shared = WatchDogModule.make()

    private let configuration: AppConfiguration
    private let stateMachine: NetworkStateMachine
    private let internetChecker: InternetChecker
    private let interfaceManager: NetworkInterfaceManager
    private let logger: EventLogger
    private let monitor: NetworkMonitor
    private var uiTimer: Timer?
    private var latestState: NetworkState = .online
    private var latestLatency: Int?
    private var latestSnapshot = USBStatusSnapshot(
        connected: false, interface: nil, service: nil,
        enabled: false, ipAddress: nil, gateway: nil, isDefaultRoute: false
    )

    // MARK: - 组装（沿用原 main.swift 的依赖装配）

    static func make() -> WatchDogModule {
        let configuration = AppConfiguration.default
        let logger = EventLogger(configuration: configuration)
        let shell = ShellCommandRunner(logger: logger)
        let interfaceManager = NetworkInterfaceManager(shell: shell)
        let internetChecker = InternetChecker(configuration: configuration)
        let notificationManager = NotificationManager(configuration: configuration)
        let stateMachine = NetworkStateMachine(logger: logger)

        let connectionVerifier = ConnectionVerifier(
            configuration: configuration,
            internetChecker: internetChecker,
            interfaceManager: interfaceManager,
            logger: logger
        )
        let usbVerifier = USBConnectionVerifier(
            configuration: configuration,
            internetChecker: internetChecker,
            interfaceManager: interfaceManager,
            logger: logger
        )
        let wifiRecoveryManager = WiFiRecoveryManager(
            configuration: configuration,
            shell: shell,
            internetChecker: internetChecker,
            verifier: connectionVerifier,
            logger: logger
        )
        let usbRecoveryManager = USBRecoveryManager(
            shell: shell,
            interfaceManager: interfaceManager,
            verifier: usbVerifier,
            logger: logger
        )
        let recoveryCoordinator = RecoveryCoordinator(
            configuration: configuration,
            stateMachine: stateMachine,
            internetChecker: internetChecker,
            interfaceManager: interfaceManager,
            usbRecoveryManager: usbRecoveryManager,
            wifiRecoveryManager: wifiRecoveryManager,
            notificationManager: notificationManager,
            logger: logger
        )
        let monitor = NetworkMonitor(
            configuration: configuration,
            stateMachine: stateMachine,
            internetChecker: internetChecker,
            interfaceManager: interfaceManager,
            recoveryCoordinator: recoveryCoordinator,
            logger: logger
        )

        return WatchDogModule(
            configuration: configuration,
            stateMachine: stateMachine,
            internetChecker: internetChecker,
            interfaceManager: interfaceManager,
            logger: logger,
            monitor: monitor
        )
    }

    private init(
        configuration: AppConfiguration,
        stateMachine: NetworkStateMachine,
        internetChecker: InternetChecker,
        interfaceManager: NetworkInterfaceManager,
        logger: EventLogger,
        monitor: NetworkMonitor
    ) {
        self.configuration = configuration
        self.stateMachine = stateMachine
        self.internetChecker = internetChecker
        self.interfaceManager = interfaceManager
        self.logger = logger
        self.monitor = monitor
        super.init()
        stateMachine.addObserver(self)
    }

    // MARK: - 生命周期

    func start() {
        updateNow()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateNow()
            }
        }
        monitor.start()
    }

    func stop() {
        uiTimer?.invalidate()
        uiTimer = nil
        monitor.stop()
    }

    func networkStateDidChange(_ state: NetworkState) {
        latestState = state
        updateNow()
    }

    private func updateNow() {
        let internetChecker = internetChecker
        let interfaceManager = interfaceManager
        DispatchQueue.global(qos: .utility).async {
            let latency = internetChecker.latencyMilliseconds()
            let snapshot = interfaceManager.usbSnapshot()
            Task { @MainActor in
                self.latestLatency = latency
                self.latestSnapshot = snapshot
            }
        }
    }

    // MARK: - 状态栏

    /// 状态 emoji：有延迟数据 = 在线；USB 未连/被禁用 = 断开；其余 = 离线
    var statusEmoji: String {
        if latestLatency != nil { return "🟢" }
        if !latestSnapshot.connected || !latestSnapshot.enabled { return "❌" }
        return "🔴"
    }

    // MARK: - 菜单

    /// 追加 NetWork-WatchDog 分组菜单项：名称·状态 + Logs
    func appendMenuItems(to menu: NSMenu) {
        menu.addItem(label("NetWork-WatchDog · \(statusText)"))
        menu.addItem(openLogItem())
    }

    private var statusText: String {
        let snapshot = latestSnapshot
        if !snapshot.connected { return "Not Connected" }
        if !snapshot.enabled { return "Disabled" }
        if snapshot.isDefaultRoute, latestLatency != nil { return "Online" }
        return "Offline"
    }

    /// 统一日志目录（桌面「自动联网日志」）
    var logDirectoryURL: URL { configuration.logDirectory }

    var wifiName: String { configuration.wifiName }

    /// 工具设置页写入备用 WiFi（队列保护）
    func updateWiFi(name: String, password: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        configuration.settings.updateWiFi(name: cleanName, password: password)
        logger.log("SETTINGS_UPDATED wifi=\(cleanName) source=settings")
        updateNow()
    }

    /// 四合一调试快照的 WatchDog 部分
    func debugSummary() -> String {
        var l: [String] = []
        l.append("NetWork-WatchDog")
        l.append("状态: \(statusEmoji) \(statusText)")
        l.append("延迟: \(latestLatency.map { "\($0) ms" } ?? "未知")")
        l.append("备用 WiFi: \(configuration.wifiName)")
        l.append("日志目录: \(configuration.logDirectory.path)")
        return l.joined(separator: "\n")
    }

    // MARK: - 动作

    @objc private func openLog() {
        NSWorkspace.shared.open(logger.currentLogFileURL())
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func openLogItem() -> NSMenuItem {
        item("    Logs", action: #selector(openLog))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

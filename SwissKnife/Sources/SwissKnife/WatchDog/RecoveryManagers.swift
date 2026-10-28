import Foundation

final class WiFiRecoveryManager {
    private let configuration: AppConfiguration
    private let shell: ShellCommandRunner
    private let internetChecker: InternetChecker
    private let verifier: ConnectionVerifier
    private let logger: EventLogger

    init(
        configuration: AppConfiguration,
        shell: ShellCommandRunner,
        internetChecker: InternetChecker,
        verifier: ConnectionVerifier,
        logger: EventLogger
    ) {
        self.configuration = configuration
        self.shell = shell
        self.internetChecker = internetChecker
        self.verifier = verifier
        self.logger = logger
    }

    func recover(interface: String) -> Bool {
        for attempt in 1...configuration.maxReconnectAttempts {
            if reconnectOnce(interface: interface, attempt: attempt) {
                return true
            }
        }
        return false
    }

    private func reconnectOnce(interface: String, attempt: Int) -> Bool {
        if internetChecker.isReachable() {
            logger.log("INTERNET_RECOVERED before_attempt=\(attempt) action=cancel_wifi_recovery")
            return true
        }

        let result = shell.run(
            "/usr/sbin/networksetup",
            ["-setairportnetwork", interface, configuration.wifiName, configuration.wifiPassword],
            timeout: 20
        )
        logger.log("WIFI_CONNECT attempt=\(attempt)/\(configuration.maxReconnectAttempts) join_status=\(result.status) interface=\(interface) network=\(configuration.wifiName)")
        return verifier.waitForWiFi(interface: interface)
    }
}

final class USBRecoveryManager {
    private let shell: ShellCommandRunner
    private let interfaceManager: NetworkInterfaceManager
    private let verifier: USBConnectionVerifier
    private let logger: EventLogger

    init(
        shell: ShellCommandRunner,
        interfaceManager: NetworkInterfaceManager,
        verifier: USBConnectionVerifier,
        logger: EventLogger
    ) {
        self.shell = shell
        self.interfaceManager = interfaceManager
        self.verifier = verifier
        self.logger = logger
    }

    func recover() -> Bool {
        guard interfaceManager.iPhoneUSBDeviceConnected() else {
            logger.log("USB_DEVICE_NOT_CONNECTED action=skip_usb_recovery")
            return false
        }
        guard let interface = interfaceManager.iPhoneUSBInterface() else {
            logger.log("USB_RECOVERY_SKIPPED reason=iphone_usb_network_port_not_found action=start_wifi_recovery")
            return false
        }
        guard let service = interfaceManager.networkService(for: interface) else {
            logger.log("USB_RECOVERY_SKIPPED interface=\(interface) reason=service_not_found action=start_wifi_recovery")
            return false
        }

        let enabled = interfaceManager.networkServiceEnabled(service)
        logger.log("USB_CHECK interface=\(interface) service=\(normalize(service)) enabled=\(enabled ? "Enabled" : "Disabled")")
        if !enabled {
            if !interfaceManager.setNetworkService(service, enabled: true) {
                logger.log("USB_ENABLE_FAILED interface=\(interface) service=\(normalize(service)) action=ask_wifi_fallback")
                return false
            }
            logger.log("USB_ENABLED interface=\(interface) service=\(normalize(service)) action=verify_internet")
        } else {
            logger.log("USB_ALREADY_ENABLED interface=\(interface) service=\(normalize(service)) action=verify_internet")
        }

        return verifier.waitForUSB(interface: interface)
    }

    func disableFailedService(interface: String) -> Bool {
        guard let service = interfaceManager.networkService(for: interface) else {
            logger.log("USB_DISABLE_SKIPPED interface=\(interface) reason=service_not_found")
            return false
        }
        let ok = interfaceManager.setNetworkService(service, enabled: false)
        if ok {
            logger.log("USB_DISABLED interface=\(interface) service=\(normalize(service)) action=one_time")
        } else {
            logger.log("USB_DISABLE_FAILED interface=\(interface) service=\(normalize(service)) action=continue_wifi_recovery")
        }
        return ok
    }

    private func normalize(_ service: String) -> String {
        service.replacingOccurrences(of: " ", with: "_")
    }
}

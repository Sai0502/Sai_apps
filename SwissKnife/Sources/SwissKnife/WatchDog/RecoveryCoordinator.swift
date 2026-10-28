import Foundation

final class RecoveryCoordinator {
    private let configuration: AppConfiguration
    private let stateMachine: NetworkStateMachine
    private let internetChecker: InternetChecker
    private let interfaceManager: NetworkInterfaceManager
    private let usbRecoveryManager: USBRecoveryManager
    private let wifiRecoveryManager: WiFiRecoveryManager
    private let notificationManager: NotificationManager
    private let logger: EventLogger

    init(
        configuration: AppConfiguration,
        stateMachine: NetworkStateMachine,
        internetChecker: InternetChecker,
        interfaceManager: NetworkInterfaceManager,
        usbRecoveryManager: USBRecoveryManager,
        wifiRecoveryManager: WiFiRecoveryManager,
        notificationManager: NotificationManager,
        logger: EventLogger
    ) {
        self.configuration = configuration
        self.stateMachine = stateMachine
        self.internetChecker = internetChecker
        self.interfaceManager = interfaceManager
        self.usbRecoveryManager = usbRecoveryManager
        self.wifiRecoveryManager = wifiRecoveryManager
        self.notificationManager = notificationManager
        self.logger = logger
    }

    func recoverWithUSBFirstThenWiFi() -> Bool {
        guard let wifiInterface = interfaceManager.wifiInterface() else {
            logger.log("FATAL reason=wifi_interface_not_found")
            stateMachine.send(.manualRequired)
            return false
        }

        if !interfaceManager.iPhoneUSBDeviceConnected() {
            logger.log("USB_DEVICE_NOT_CONNECTED action=start_wifi_recovery")
            return recoverWiFi(interface: wifiInterface)
        }

        logger.log("USB_DEVICE_CONNECTED device=iPhone action=check_network_service")
        let usbInterface = interfaceManager.iPhoneUSBInterface()
        let usbService = usbInterface.flatMap { interfaceManager.networkService(for: $0) }

        guard let usbInterface, let usbService else {
            logger.log("USB_RECOVERY_SKIPPED reason=iphone_usb_network_port_or_service_not_found action=start_wifi_recovery")
            return recoverWiFi(interface: wifiInterface)
        }

        stateMachine.send(.usbRecoveryStarted)
        if usbRecoveryManager.recover() {
            logger.log("AUTO_RECOVERY_SUCCESS source=iphone_usb")
            stateMachine.send(.usbRecoverySucceeded)
            return true
        }
        stateMachine.send(.usbRecoveryFailed)

        // Retain the interactive fallback for possible future use, but keep it disabled.
        #if false
        if !notificationManager.askDisableUSBAndUseWiFi(service: usbService) {
            logger.log("USB_FALLBACK_DECLINED interface=\(usbInterface) service=\(usbService.replacingOccurrences(of: " ", with: "_")) action=manual_intervention")
            stateMachine.send(.manualRequired)
            return false
        }

        logger.log("USB_FALLBACK_CONFIRMED interface=\(usbInterface) service=\(usbService.replacingOccurrences(of: " ", with: "_")) action=disable_usb_and_start_wifi_recovery")
        _ = usbRecoveryManager.disableFailedService(interface: usbInterface)
        if internetChecker.isReachable() {
            logger.log("INTERNET_RECOVERED before_wifi_attempt action=resume_monitoring")
            stateMachine.send(.internetAvailable)
            return true
        }
        return recoverWiFi(interface: wifiInterface)
        #endif

        logger.log("USB_RECOVERY_FAILED interface=\(usbInterface) service=\(usbService.replacingOccurrences(of: " ", with: "_")) action=notify_and_continue_monitoring")
        notificationManager.playManualInterventionSound()
        stateMachine.send(.manualRequired)
        return false
    }

    private func recoverWiFi(interface: String) -> Bool {
        stateMachine.send(.wifiRecoveryStarted)
        if wifiRecoveryManager.recover(interface: interface) {
            logger.log("AUTO_RECOVERY_SUCCESS source=wifi network=\(configuration.wifiName)")
            stateMachine.send(.wifiRecoverySucceeded)
            return true
        }

        logger.log("AUTO_RECOVERY_FAILED attempts=\(configuration.maxReconnectAttempts) network=\(configuration.wifiName) manual_connection_required=yes")
        #if false
        notificationManager.showManualConnectionAlert()
        #endif
        notificationManager.playManualInterventionSound()
        stateMachine.send(.wifiRecoveryFailed)
        return false
    }
}
